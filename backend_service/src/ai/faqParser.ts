/**
 * Splits the two AI flow documents (instruction/probashi_guard_ai_flow_*.txt)
 * into one chunk per question: exactly one question with its AI Assistant
 * answer, which is what gets embedded and later handed to the model as context.
 *
 * The documents share a layout in both languages:
 *
 *   SECTION 3: THE REMITTANCE WORKER ...        (সেকশন ৩: ...)
 *   Q1: question text                           (প্রশ্ন ১: ...)
 *   AI Assistant: answer text, possibly         (এআই অ্যাসিস্ট্যান্ট: ...)
 *   spread over several lines or a list
 *
 * Anything before the first question of a section (the title block, "Target
 * User:" lines, separator rules) is dropped. A question without an answer, or
 * an answer without a question, throws: a half-parsed document should fail the
 * seeding run loudly rather than quietly leave a hole in the knowledge base.
 */

export type FaqLanguage = 'bn' | 'en';

export interface FaqChunk {
  /** Stable id, e.g. `en-s3-q12`. The same question has the same number in both languages. */
  key: string;
  language: FaqLanguage;
  /** The section heading, e.g. "THE REMITTANCE WORKER (...)". */
  section: string;
  question: string;
  answer: string;
  /** `Q: ...` and `A: ...` together: the text that is embedded and shown to the model. */
  content: string;
}

const DIGITS = '০১২৩৪৫৬৭৮৯';

/** "১২" and "12" are both 12. */
function toNumber(text: string): number {
  let out = '';
  for (const ch of text) {
    const bn = DIGITS.indexOf(ch);
    out += bn >= 0 ? String(bn) : ch;
  }
  return Number.parseInt(out, 10);
}

const NUM = '([0-9০-৯]+)';
const COLON = '\\s*[:：]\\s*';
const SECTION_RE = new RegExp(`^(?:SECTION|সেকশন)\\s+${NUM}${COLON}(.+)$`, 'i');
const QUESTION_RE = new RegExp(`^(?:Q|প্রশ্ন)\\s*${NUM}${COLON}(.*)$`);
// The English file has one "AI   Assistant:" with extra spaces; allow any.
const ANSWER_RE = new RegExp(
  `^(?:AI\\s+Assistant|এআই\\s+অ্যাসিস্ট্যান্ট)${COLON}(.*)$`,
  'i',
);
const RULE_RE = /^[-=_]{4,}$/;

interface Open {
  section: number;
  sectionTitle: string;
  number: number;
  question: string[];
  answer: string[];
  inAnswer: boolean;
  line: number;
}

export function parseFaqDocument(raw: string, language: FaqLanguage): FaqChunk[] {
  // NFC, because the same Bangla conjunct can be typed as different code point
  // sequences, and the markers above must match whichever way the file has it.
  const lines = raw
    .replace(/^﻿/, '')
    .normalize('NFC')
    .split(/\r?\n/);

  const chunks: FaqChunk[] = [];
  let sectionNo = 0;
  let sectionTitle = '';
  let open: Open | null = null;

  const finish = () => {
    if (!open) return;
    const question = open.question.join(' ').replace(/\s+/g, ' ').trim();
    const answer = open.answer.join('\n').trim();
    if (!question || !answer) {
      throw new Error(
        `${language}: question ${open.number} in section ${open.section} (line ${open.line}) ` +
          `has no ${question ? 'answer' : 'question text'}`,
      );
    }
    chunks.push({
      key: `${language}-s${open.section}-q${open.number}`,
      language,
      section: open.sectionTitle,
      question,
      answer,
      content: `Q: ${question}\nA: ${answer}`,
    });
    open = null;
  };

  lines.forEach((rawLine, index) => {
    const line = rawLine.trim();
    const lineNo = index + 1;

    if (RULE_RE.test(line)) {
      finish();
      return;
    }

    const section = SECTION_RE.exec(line);
    if (section) {
      finish();
      sectionNo = toNumber(section[1]);
      sectionTitle = section[2].trim();
      return;
    }

    const question = QUESTION_RE.exec(line);
    if (question) {
      finish();
      if (sectionNo === 0) {
        throw new Error(`${language}: question on line ${lineNo} comes before any section heading`);
      }
      open = {
        section: sectionNo,
        sectionTitle,
        number: toNumber(question[1]),
        question: [question[2]],
        answer: [],
        inAnswer: false,
        line: lineNo,
      };
      return;
    }

    const answer = ANSWER_RE.exec(line);
    if (answer) {
      if (!open) {
        throw new Error(`${language}: answer on line ${lineNo} has no question before it`);
      }
      if (open.inAnswer) {
        throw new Error(`${language}: question ${open.number} has two answers (line ${lineNo})`);
      }
      open.inAnswer = true;
      open.answer.push(answer[1]);
      return;
    }

    // A wrapped line of whatever part we are in. Blank lines and text outside a
    // question (preamble, "Target User:" lines) are not part of any chunk.
    if (open && line) (open.inAnswer ? open.answer : open.question).push(line);
  });
  finish();

  const seen = new Set<string>();
  for (const chunk of chunks) {
    if (seen.has(chunk.key)) throw new Error(`${language}: duplicate question ${chunk.key}`);
    seen.add(chunk.key);
  }
  return chunks;
}
