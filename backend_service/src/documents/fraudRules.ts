// Deterministic labor-fraud and Tip Shoi (টিপ সই) checks. They run on every scan,
// over the text the model read, so a model that misses a trap can't clear it.

export const MIN_MONTHLY_SALARY_SAR = 1000;
export const LOAN_TRAP_MIN_SAR = 6000;
export const LOAN_TRAP_MAX_SAR = 25000;

// SAR per unit for USD-pegged currencies, so the salary floor check is exact
// rather than left to the model's arithmetic.
export const SAR_PER_UNIT: Record<string, number> = {
  SAR: 1,
  USD: 3.75,
  AED: 3.75 / 3.6725,
  QAR: 3.75 / 3.64,
  BHD: 3.75 / 0.376,
  OMR: 3.75 / 0.3845,
};

export function toSar(amount: number | null, currency: string | null): number | null {
  const rate = currency ? SAR_PER_UNIT[currency.toUpperCase()] : undefined;
  return amount !== null && rate !== undefined ? Math.round(amount * rate * 100) / 100 : null;
}

export const TIP_SHOI_TYPES = [
  'blank_space_before_signature',
  'blank_promissory_note',
  'unauthorized_loan_acknowledgment',
  'recruitment_fee_acknowledgment',
  'other',
] as const;
export type TipShoiType = (typeof TIP_SHOI_TYPES)[number];
export type TipShoiFinding = { type: TipShoiType; location: string; explanation: string };

export type RuleLanguage = 'bn' | 'en' | 'zh';

export type FraudEvidence = {
  /** Original-language text of each clause, in reading order ("[BLANK]" marks empty space). */
  segments: string[];
  /** Fees the document says the worker pays. */
  workerFees: { description: string; amount: number | null; currency: string | null }[];
};

const MONEY_TRAP_TYPES = new Set<TipShoiType>(['unauthorized_loan_acknowledgment', 'recruitment_fee_acknowledgment']);

const SIGNATURE_WORDS =
  /signature|signed by|sign here|thumb ?print|توقيع|التوقيع|بصمة|الإمضاء|إمضاء|امضاء|স্বাক্ষর|টিপ ?সই|签名|签字|手印/iu;
const PROMISSORY_NOTE =
  /سند\s*(?:لل?|ال)[أاإآ]مر|كمبيال[ةه]|promissory\s+note|\bsanad\s*(?:li|le|el|l)?[\s-]*amr\b|প্রমিসরি\s*নোট|本票/iu;
const DEBT_WORDS =
  /loan|debt|\bowe[sd]?\b|borrow|advance|recruitment|commission|agency fee|visa fee|قرض|دين|مدين|مديون|سلف|استلمت|رسوم|عمولة|استقدام|ঋণ|ধার|দেনা|কমিশন|ফি|借款|欠款|债务|招聘费|中介费/iu;
const SAR_MARK = String.raw`(?:SAR|SR|S\.R\.?|ر\.?\s?س\.?|ريال|riyals?|রিয়াল|里亚尔)`;
const AMOUNT = String.raw`(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?`;
const SAR_AMOUNT = new RegExp(`${SAR_MARK}\\s*${AMOUNT}|${AMOUNT}\\s*${SAR_MARK}`, 'giu');

/** Arabic-Indic, Persian and Bengali digits to ASCII; strips Arabic diacritics and tatweel. */
export function normalizeText(text: string): string {
  return text
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/[০-৯]/g, (d) => String(d.charCodeAt(0) - 0x09e6))
    .replace(/٬/g, ',')
    .replace(/٫/g, '.')
    .replace(/[ً-ْـ]/g, '');
}

const snippet = (text: string) => {
  const flat = text.replace(/\s+/g, ' ').trim();
  return flat.length > 90 ? `${flat.slice(0, 87)}…` : flat;
};

const formatSar = (amount: number) => amount.toLocaleString('en-US', { maximumFractionDigits: 0 });

const EXPLANATIONS: Record<Exclude<TipShoiType, 'other'>, Record<RuleLanguage, (sar?: number) => string>> = {
  blank_space_before_signature: {
    bn: () => 'স্বাক্ষর বা টিপ সইয়ের জায়গার উপরে বড় ফাঁকা জায়গা আছে। সই করার পরে সেখানে নতুন শর্ত বা ঋণের কথা লিখে দেওয়া যায়।',
    en: () => 'There is a large empty space above the signature or thumbprint area. Terms or a debt could be written there after you sign.',
    zh: () => '签名或按手印处上方有大片空白。您签字后，对方可能在空白处添加条款或债务。',
  },
  blank_promissory_note: {
    bn: () => 'এই কাগজে "সনদ লি আমর" (سند لأمر) বা প্রমিসরি নোটের কথা আছে। এতে সই দিলে আইনত আপনি টাকা দেনা হয়ে যাবেন।',
    en: () => 'This paper contains a promissory note (Sanad Li Amr, سند لأمر). Signing it makes you legally owe money.',
    zh: () => '此文件包含本票（Sanad Li Amr，سند لأمر）。签署后，您在法律上就欠下这笔钱。',
  },
  unauthorized_loan_acknowledgment: {
    bn: (sar) => `এখানে লেখা আছে আপনি ${formatSar(sar ?? 0)} রিয়াল ঋণ নিয়েছেন বা দেনা আছেন। এই টাকা না নিয়ে থাকলে সই করবেন না।`,
    en: (sar) => `The paper says you received or owe SAR ${formatSar(sar ?? 0)} as a loan. Do not sign if you did not receive this money.`,
    zh: (sar) => `文件写明您收到或欠下 ${formatSar(sar ?? 0)} 沙特里亚尔借款。如果您没有收到这笔钱，请不要签字。`,
  },
  recruitment_fee_acknowledgment: {
    bn: (sar) => `আপনাকে ${formatSar(sar ?? 0)} রিয়াল নিয়োগ বা ভিসা ফি দিতে বা স্বীকার করতে বলা হয়েছে। নিয়োগের খরচ কর্মীর দেওয়ার কথা নয়।`,
    en: (sar) => `You are asked to pay or acknowledge SAR ${formatSar(sar ?? 0)} in recruitment or visa fees. Workers should not pay recruitment costs.`,
    zh: (sar) => `文件要求您支付或承认 ${formatSar(sar ?? 0)} 沙特里亚尔的招聘或签证费用。工人不应承担招聘费用。`,
  },
};

const finding = (type: Exclude<TipShoiType, 'other'>, location: string, language: RuleLanguage, sar?: number): TipShoiFinding => ({
  type,
  location,
  explanation: EXPLANATIONS[type][language](sar),
});

/** Every SAR amount within the debt-trap range in a passage that talks about a loan, debt or fee. */
function loanTrapAmounts(passage: string): number[] {
  if (!DEBT_WORDS.test(passage)) return [];
  const amounts: number[] = [];
  for (const match of passage.matchAll(SAR_AMOUNT)) {
    const amount = Number((match[1] ?? match[2]).replace(/,/g, ''));
    if (amount >= LOAN_TRAP_MIN_SAR && amount <= LOAN_TRAP_MAX_SAR) amounts.push(amount);
  }
  return amounts;
}

/**
 * Tip Shoi findings the rules can prove from the extracted clauses:
 * promissory notes, loan or recruitment-fee acknowledgments of SAR 6,000-25,000,
 * and blank space directly above a signature.
 */
export function detectTipShoi(evidence: FraudEvidence, language: RuleLanguage): TipShoiFinding[] {
  const findings: TipShoiFinding[] = [];
  const passages = evidence.segments.map(normalizeText);

  const note = passages.find((p) => PROMISSORY_NOTE.test(p));
  if (note) findings.push(finding('blank_promissory_note', snippet(note), language));

  const feeTrap = evidence.workerFees
    .map((fee) => ({ fee, sar: toSar(fee.amount, fee.currency) }))
    .find(({ sar }) => sar !== null && sar >= LOAN_TRAP_MIN_SAR && sar <= LOAN_TRAP_MAX_SAR);
  if (feeTrap) {
    findings.push(finding('recruitment_fee_acknowledgment', snippet(feeTrap.fee.description), language, feeTrap.sar!));
  } else {
    for (const passage of passages) {
      const [amount] = loanTrapAmounts(passage);
      if (amount === undefined) continue;
      findings.push(finding('unauthorized_loan_acknowledgment', snippet(passage), language, amount));
      break;
    }
  }

  const blankBeforeSignature = passages.findIndex(
    (s, i) => s.trim() === '[BLANK]' && SIGNATURE_WORDS.test(passages[i + 1] ?? ''),
  );
  if (blankBeforeSignature >= 0) {
    findings.push(finding('blank_space_before_signature', snippet(passages[blankBeforeSignature + 1]), language));
  }

  return findings;
}

/**
 * Adds rule findings the model didn't already report. Loan and recruitment-fee
 * acknowledgments count as one kind of trap, so a model finding of either suppresses both.
 */
export function mergeFindings(modelFindings: TipShoiFinding[], ruleFindings: TipShoiFinding[]): TipShoiFinding[] {
  const reported = new Set(modelFindings.map((f) => f.type));
  const hasMoneyTrap = modelFindings.some((f) => MONEY_TRAP_TYPES.has(f.type));
  const added = ruleFindings.filter((f) => !reported.has(f.type) && !(MONEY_TRAP_TYPES.has(f.type) && hasMoneyTrap));
  return [...modelFindings, ...added];
}
