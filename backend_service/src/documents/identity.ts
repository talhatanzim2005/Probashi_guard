// Identity documents. Passports are read on the phone from their machine-readable
// zone (MRZ) and only the parsed fields reach the server; visas and BMET cards
// are read by Gemini from a photo.

export const DOCUMENT_CATEGORIES = ['PASSPORT', 'VISA', 'CONTRACT'] as const;
export type DocumentCategory = (typeof DOCUMENT_CATEGORIES)[number];

export const ID_DOCUMENT_KINDS = [
  'passport',
  'bmet_smart_card',
  'national_id',
  'work_visa',
  'residence_permit',
  'other',
] as const;

export const IDENTITY_KEYS = [
  'full_name',
  'document_number',
  'nationality',
  'date_of_birth',
  'date_of_expiry',
  'sex',
  'issuing_country',
  'visa_type',
  'sponsor',
  'occupation',
] as const;
export type IdentityFields = Record<(typeof IDENTITY_KEYS)[number], string | null>;

/** Gulf entry and residence permits generally need six months of passport validity left. */
const MIN_VALIDITY_MONTHS = 6;

export type PassportMrz = {
  document_number: string;
  given_names: string;
  surnames: string;
  nationality_country_code: string;
  issuing_country_code: string | null;
  /** YYYY-MM-DD */
  expiry_date: string;
};

const COUNTRY_CODE = /^[A-Z<]{3}$/;
const DOCUMENT_NUMBER = /^[A-Z0-9]{1,20}$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const text = (v: unknown) => (typeof v === 'string' ? v.trim().toUpperCase() : '');
// The MRZ uses "<" as filler and separator.
const name = (v: unknown) => text(v).replace(/</g, ' ').replace(/\s+/g, ' ').trim();

/**
 * Validates the fields the app parsed from a passport MRZ. The app has already
 * checked the MRZ check digits; this guards the shape of what is stored.
 */
export function parsePassportMrz(input: unknown): PassportMrz | { error: string } {
  const raw = input && typeof input === 'object' ? (input as Record<string, unknown>) : {};
  const documentNumber = text(raw.document_number).replace(/</g, '');
  const nationality = text(raw.nationality_country_code);
  const issuing = text(raw.issuing_country_code);
  const expiry = text(raw.expiry_date);
  const mrz: PassportMrz = {
    document_number: documentNumber,
    given_names: name(raw.given_names),
    surnames: name(raw.surnames),
    nationality_country_code: nationality,
    issuing_country_code: issuing || null,
    expiry_date: expiry,
  };

  if (!DOCUMENT_NUMBER.test(mrz.document_number)) return { error: 'mrz.document_number is missing or invalid' };
  if (!mrz.surnames && !mrz.given_names) return { error: 'mrz.surnames or mrz.given_names is required' };
  if (mrz.surnames.length > 100 || mrz.given_names.length > 100) return { error: 'mrz names are too long' };
  if (!COUNTRY_CODE.test(nationality)) return { error: 'mrz.nationality_country_code must be a 3-letter code' };
  if (issuing && !COUNTRY_CODE.test(issuing)) return { error: 'mrz.issuing_country_code must be a 3-letter code' };
  if (!ISO_DATE.test(expiry) || Number.isNaN(Date.parse(`${expiry}T00:00:00Z`))) {
    return { error: 'mrz.expiry_date must be a date in YYYY-MM-DD format' };
  }
  return mrz;
}

type Language = 'bn' | 'en' | 'zh';
type Validity = 'valid' | 'expiring' | 'expired';

const SUMMARY: Record<Language, { title: string; lines: (m: PassportMrz, fullName: string, v: Validity) => string[] }> = {
  bn: {
    title: 'পাসপোর্ট',
    lines: (m, fullName, v) => [
      `এটি ${fullName}-এর পাসপোর্ট (${m.nationality_country_code}), নম্বর ${m.document_number}।`,
      v === 'expired'
        ? `এই পাসপোর্টের মেয়াদ ${m.expiry_date} তারিখে শেষ হয়ে গেছে।`
        : v === 'expiring'
          ? `মেয়াদ শেষ হবে ${m.expiry_date} তারিখে, ৬ মাসেরও কম বাকি।`
          : `মেয়াদ আছে ${m.expiry_date} পর্যন্ত।`,
      v === 'valid'
        ? 'পাসপোর্ট সবসময় নিজের কাছে রাখুন; মালিক বা দালালকে রাখতে দেবেন না।'
        : 'বিদেশ যাওয়া বা চুক্তি করার আগে পাসপোর্ট নবায়ন করুন।',
    ],
  },
  en: {
    title: 'Passport',
    lines: (m, fullName, v) => [
      `This is the passport of ${fullName} (${m.nationality_country_code}), number ${m.document_number}.`,
      v === 'expired'
        ? `This passport expired on ${m.expiry_date}.`
        : v === 'expiring'
          ? `It expires on ${m.expiry_date}, less than 6 months from now.`
          : `It is valid until ${m.expiry_date}.`,
      v === 'valid'
        ? 'Always keep your passport yourself; never let an employer or agent hold it.'
        : 'Renew your passport before you travel or sign a work contract.',
    ],
  },
  zh: {
    title: '护照',
    lines: (m, fullName, v) => [
      `这是 ${fullName}（${m.nationality_country_code}）的护照，号码 ${m.document_number}。`,
      v === 'expired'
        ? `此护照已于 ${m.expiry_date} 过期。`
        : v === 'expiring'
          ? `此护照将于 ${m.expiry_date} 到期，剩余不足 6 个月。`
          : `有效期至 ${m.expiry_date}。`,
      v === 'valid' ? '请始终自己保管护照，不要交给雇主或中介保管。' : '出行或签署劳动合同前请先更新护照。',
    ],
  },
};

const NOTES: Record<Language, string> = {
  bn: 'মেশিন-রিডেবল জোন (MRZ) ফোনেই পড়া ও যাচাই করা হয়েছে।',
  en: 'The machine-readable zone (MRZ) was read and check-digit verified on the phone.',
  zh: '机读区（MRZ）已在手机上读取并通过校验位验证。',
};

/**
 * The analysis for an on-device passport scan, in the same raw shape the model
 * returns, so it goes through the same normalization and storage.
 */
export function passportMrzToRawAnalysis(mrz: PassportMrz, language: Language, today = new Date()) {
  const expiry = new Date(`${mrz.expiry_date}T00:00:00Z`);
  const cutoff = new Date(today);
  cutoff.setUTCMonth(cutoff.getUTCMonth() + MIN_VALIDITY_MONTHS);
  const validity: Validity = expiry < today ? 'expired' : expiry < cutoff ? 'expiring' : 'valid';
  const fullName = [mrz.given_names, mrz.surnames].filter(Boolean).join(' ');
  const summary = SUMMARY[language];

  return {
    document_category: 'PASSPORT',
    document_type: summary.title,
    is_legible: true,
    identity: {
      document_kind: 'passport',
      full_name: fullName,
      document_number: mrz.document_number,
      nationality: mrz.nationality_country_code,
      date_of_expiry: mrz.expiry_date,
      issuing_country: mrz.issuing_country_code,
    },
    authenticity: { notes: NOTES[language] },
    tip_shoi_detected: false,
    verdict: validity === 'valid' ? 'SAFE_TO_SIGN' : 'PROCEED_WITH_CAUTION',
    summary_3_lines: summary.lines(mrz, fullName, validity),
  };
}
