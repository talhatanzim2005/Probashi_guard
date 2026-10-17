import test from 'node:test';
import assert from 'node:assert';
import http from 'node:http';
import app from '../server.js';
import { buildReport, normalizeAnalysis, parseImage } from '../routes/documents.js';
import { detectTipShoi } from '../documents/fraudRules.js';
import { parsePassportMrz, passportMrzToRawAnalysis, type PassportMrz } from '../documents/identity.js';

const JPEG_HEADER = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]);

let server: http.Server;
let baseUrl: string;

test.before(async () => {
  return new Promise<void>((resolve) => {
    server = app.listen(0, () => {
      const addr = server.address() as any;
      baseUrl = `http://127.0.0.1:${addr.port}`;
      resolve();
    });
  });
});

test.after(async () => {
  return new Promise<void>((resolve) => {
    server.close(() => resolve());
  });
});

test('parseImage detects JPEG and strips a data URL prefix', () => {
  const parsed = parseImage(`data:image/jpeg;base64,${JPEG_HEADER.toString('base64')}`);
  assert.ok(!('error' in parsed));
  assert.strictEqual(parsed.mime, 'image/jpeg');
  assert.strictEqual(parsed.sha256.length, 64);
});

test('parseImage rejects non-image payloads', () => {
  const parsed = parseImage(Buffer.from('%PDF-1.7 not an image').toString('base64'));
  assert.ok('error' in parsed);
});

test('salary under SAR 1,000 is forced to high risk and blocks SAFE_TO_SIGN', () => {
  const result = normalizeAnalysis({
    salary: { amount: 900, currency: 'SAR', period: 'monthly', monthly_amount: 900, risk: 'low' },
    tip_shoi_detected: false,
    verdict: 'SAFE_TO_SIGN',
    summary_3_lines: ['a', 'b', 'c'],
  });
  assert.strictEqual(result.salary.risk, 'high');
  assert.strictEqual(result.salary.monthly_sar_equivalent, 900);
  assert.strictEqual(result.verdict, 'PROCEED_WITH_CAUTION');
});

test('the legacy SIGN_WITH_CAUTION verdict maps to PROCEED_WITH_CAUTION', () => {
  assert.strictEqual(normalizeAnalysis({ verdict: 'SIGN_WITH_CAUTION' }).verdict, 'PROCEED_WITH_CAUTION');
});

test('pegged Gulf currencies are converted before the SAR floor check', () => {
  // AED 950 ≈ SAR 970 (< 1,000); AED 1,000 ≈ SAR 1,021 (>= 1,000)
  const low = normalizeAnalysis({ salary: { currency: 'aed', monthly_amount: 950, risk: 'low' } });
  const ok = normalizeAnalysis({ salary: { currency: 'AED', monthly_amount: 1000, risk: 'low' } });
  assert.strictEqual(low.salary.risk, 'high');
  assert.strictEqual(ok.salary.risk, 'low');
});

test('any Tip Shoi finding forces tip_shoi_detected and DO_NOT_SIGN', () => {
  const result = normalizeAnalysis({
    tip_shoi_detected: false,
    tip_shoi_findings: [{ type: 'blank_promissory_note', location: 'page 2', explanation: 'blank Sanad Li Amr' }],
    verdict: 'SAFE_TO_SIGN',
  });
  assert.strictEqual(result.tip_shoi_detected, true);
  assert.strictEqual(result.verdict, 'DO_NOT_SIGN');
});

test('full translation is built from the side-by-side segments', () => {
  const result = normalizeAnalysis({
    translation_segments: [
      { original: 'Salary: SAR 800', translated: 'বেতন: ৮০০ রিয়াল' },
      { original: '[BLANK]', translated: '' },
      { original: '', translated: '' },
    ],
  });
  assert.strictEqual(result.translation_segments.length, 2);
  assert.strictEqual(result.full_translation, 'বেতন: ৮০০ রিয়াল');
});

test('malformed model output is coerced into the fixed shape', () => {
  const result = normalizeAnalysis({
    verdict: 'MAYBE',
    salary: 'lots',
    summary_3_lines: 'one\ntwo\nthree\nfour',
    tip_shoi_findings: [{ type: 'made_up' }],
  });
  assert.strictEqual(result.verdict, 'DO_NOT_SIGN'); // the finding still counts
  assert.strictEqual(result.tip_shoi_findings[0].type, 'other');
  assert.deepStrictEqual(result.summary_3_lines, ['one', 'two', 'three']);
  assert.strictEqual(result.salary.amount, null);
});

const noEvidence = { segments: [], workerFees: [] };

test('rules catch a promissory note the model missed, even with Arabic diacritics', () => {
  const result = normalizeAnalysis({
    verdict: 'SAFE_TO_SIGN',
    tip_shoi_detected: false,
    translation_segments: [{ original: 'أتعهد بموجب هذا السَّنَد لأمر بدفع المبلغ', translated: 'I promise to pay' }],
  });
  assert.deepStrictEqual(result.tip_shoi_findings.map((f) => f.type), ['blank_promissory_note']);
  assert.strictEqual(result.verdict, 'DO_NOT_SIGN');
});

test('rules catch a SAR 6,000-25,000 loan acknowledgment written in Arabic-Indic digits', () => {
  const findings = detectTipShoi(
    { ...noEvidence, segments: ['أقر أنا الموقع أدناه بأنني استلمت مبلغ ١٥٬٠٠٠ ريال كقرض من المكتب'] },
    'en',
  );
  assert.strictEqual(findings.length, 1);
  assert.strictEqual(findings[0].type, 'unauthorized_loan_acknowledgment');
  assert.match(findings[0].explanation, /SAR 15,000/);
});

test('rules ignore loans outside the trap range and penalties that are not debts', () => {
  const findings = detectTipShoi(
    {
      ...noEvidence,
      segments: [
        'The worker received a salary advance of SAR 3,000.',
        'If the worker leaves early he shall pay SAR 10,000 as compensation.',
      ],
    },
    'en',
  );
  assert.deepStrictEqual(findings, []);
});

test('a worker-paid recruitment fee in range is flagged unless the model already reported a money trap', () => {
  const fee = { description: 'Recruitment fee', amount: 8000, currency: 'SAR', paid_by: 'worker' };
  const flagged = normalizeAnalysis({ fees: { items: [fee] } });
  assert.deepStrictEqual(flagged.tip_shoi_findings.map((f) => f.type), ['recruitment_fee_acknowledgment']);

  const modelFinding = { type: 'unauthorized_loan_acknowledgment', location: 'Clause 8', explanation: 'Loan' };
  const deduped = normalizeAnalysis({ fees: { items: [fee] }, tip_shoi_findings: [modelFinding] });
  assert.deepStrictEqual(deduped.tip_shoi_findings.map((f) => f.type), ['unauthorized_loan_acknowledgment']);
});

test('a [BLANK] segment directly above a signature line is a Tip Shoi trap', () => {
  const findings = detectTipShoi(
    { ...noEvidence, segments: ['9. Notice period: 30 days.', '[BLANK]', 'توقيع العامل / بصمة الإبهام'] },
    'bn',
  );
  assert.strictEqual(findings[0].type, 'blank_space_before_signature');
  assert.match(findings[0].explanation, /স্বাক্ষর/);
});

test('stamp and seal observations are kept, with unknown stamp kinds coerced to unclear', () => {
  const result = normalizeAnalysis({
    authenticity: { signature_present: false, stamp_present: true, stamp_kind: 'made_up', stamp_text: 'سفارة المملكة العربية السعودية' },
  });
  assert.strictEqual(result.authenticity.stamp_present, true);
  assert.strictEqual(result.authenticity.stamp_kind, 'unclear');
  assert.strictEqual(result.authenticity.stamp_text, 'سفارة المملكة العربية السعودية');
});

const passport = {
  document_number: 'A01234567',
  given_names: 'MOHAMMAD<RAHIM',
  surnames: 'UDDIN',
  nationality_country_code: 'BGD',
  issuing_country_code: 'BGD',
  expiry_date: '2031-05-01',
};

test('parsePassportMrz validates and cleans the fields read on the phone', () => {
  const mrz = parsePassportMrz({ ...passport, document_number: 'a0123456<' }) as PassportMrz;
  assert.strictEqual(mrz.document_number, 'A0123456');
  assert.strictEqual(mrz.given_names, 'MOHAMMAD RAHIM');
  assert.ok('error' in parsePassportMrz({ ...passport, expiry_date: '01/05/2031' }));
  assert.ok('error' in parsePassportMrz({ ...passport, nationality_country_code: 'BD' }));
  assert.ok('error' in parsePassportMrz({ ...passport, document_number: '' }));
  assert.ok('error' in parsePassportMrz(undefined));
});

test('an on-device passport scan is checked for six months of validity', () => {
  const today = new Date('2026-10-17T00:00:00Z');
  const mrz = parsePassportMrz(passport) as PassportMrz;
  const valid = normalizeAnalysis(passportMrzToRawAnalysis(mrz, 'en', today));
  const expiring = normalizeAnalysis(passportMrzToRawAnalysis({ ...mrz, expiry_date: '2027-02-01' }, 'en', today));
  const expired = normalizeAnalysis(passportMrzToRawAnalysis({ ...mrz, expiry_date: '2026-01-01' }, 'bn', today));

  assert.strictEqual(valid.document_category, 'PASSPORT');
  assert.strictEqual(valid.identity.full_name, 'MOHAMMAD RAHIM UDDIN');
  assert.strictEqual(valid.identity.date_of_expiry, '2031-05-01');
  assert.strictEqual(valid.verdict, 'SAFE_TO_SIGN');
  assert.strictEqual(valid.summary_3_lines.length, 3);
  assert.strictEqual(expiring.verdict, 'PROCEED_WITH_CAUTION');
  assert.strictEqual(expired.verdict, 'PROCEED_WITH_CAUTION');
  assert.match(expired.summary_3_lines[1], /মেয়াদ/);
});

test('buildReport produces the flat report shape', () => {
  const analysis = {
    ...normalizeAnalysis({
      document_category: 'CONTRACT',
      salary: { amount: 800, currency: 'SAR', period: 'monthly', monthly_amount: 800 },
      fees: {
        items: [
          { description: 'Visa fee', amount: 15000, currency: 'SAR', paid_by: 'worker' },
          { description: 'Airfare', amount: 1200, currency: 'SAR', paid_by: 'employer' },
        ],
      },
      duration: { text: '2 years' },
      summary_3_lines: ['a', 'b', 'c'],
      translation_segments: [{ original: 'Clause 1', translated: 'ধারা ১' }],
    }),
    source_engine: 'Gemini' as const,
  };
  const report = buildReport(analysis);
  assert.deepStrictEqual(Object.keys(report), [
    'document_type',
    'source_engine',
    'salary',
    'fees',
    'duration',
    'cancellation',
    'tip_shoi_detected',
    'verdict',
    'summary_3_lines',
    'translated_text',
  ]);
  assert.strictEqual(report.document_type, 'CONTRACT');
  assert.strictEqual(report.salary, 'SAR 800 / monthly');
  assert.strictEqual(report.fees, 'Visa fee: SAR 15,000');
  assert.strictEqual(report.cancellation, null);
  assert.strictEqual(report.tip_shoi_detected, true); // the SAR 15,000 worker fee
  assert.strictEqual(report.verdict, 'DO_NOT_SIGN');
  assert.strictEqual(report.translated_text, 'ধারা ১');
});

const postJson = (path: string, body: unknown) =>
  fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

test('POST /api/documents/scan rejects a non-image with 400', async () => {
  const res = await postJson('/api/documents/scan', { imageBase64: Buffer.from('hello').toString('base64'), language: 'bn' });
  assert.strictEqual(res.status, 400);
});

test('POST /api/documents/analyze (the old name) still validates like /scan', async () => {
  const res = await postJson('/api/documents/analyze', { imageBase64: JPEG_HEADER.toString('base64'), language: 'fr' });
  assert.strictEqual(res.status, 400);
});

test('POST /api/documents/scan accepts large bodies but caps the decoded image at 8 MB', async () => {
  const res = await postJson('/api/documents/scan', { imageBase64: 'A'.repeat(13 * 1024 * 1024), language: 'bn' });
  assert.strictEqual(res.status, 400);
  assert.match(((await res.json()) as any).error, /too large \(max 8 MB\)/);
});

test('POST /api/documents/scan answers a body over 50 MB with 413 and a message', async () => {
  const res = await postJson('/api/documents/scan', { imageBase64: 'A'.repeat(51 * 1024 * 1024) });
  assert.strictEqual(res.status, 413);
  assert.match(((await res.json()) as any).error, /too large/);
});

test('POST /api/documents/mrz rejects invalid passport fields with 400', async () => {
  const res = await postJson('/api/documents/mrz', { language: 'en', mrz: { ...passport, expiry_date: 'soon' } });
  assert.strictEqual(res.status, 400);
});

test('POST /api/documents/mrz without a session returns the passport analysis unsaved', async () => {
  const res = await postJson('/api/documents/mrz', { language: 'en', mrz: passport });
  assert.strictEqual(res.status, 200);
  const body = (await res.json()) as any;
  assert.strictEqual(body.saved, false);
  assert.strictEqual(body.analysis.source_engine, 'On-device MRZ');
  assert.strictEqual(body.analysis.identity.document_number, 'A01234567');
  assert.strictEqual(body.report.document_type, 'PASSPORT');
  assert.strictEqual(body.report.salary, null);
});
