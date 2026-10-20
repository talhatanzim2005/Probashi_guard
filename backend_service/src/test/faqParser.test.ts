import test from 'node:test';
import assert from 'node:assert';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { parseFaqDocument } from '../ai/faqParser.js';

// dist/test/ -> backend_service/ -> repo root -> instruction/
const DOCS = path.resolve(__dirname, '..', '..', '..', 'instruction');
const english = parseFaqDocument(readFileSync(path.join(DOCS, 'probashi_guard_ai_flow_english.txt'), 'utf8'), 'en');
const bangla = parseFaqDocument(readFileSync(path.join(DOCS, 'probashi_guard_ai_flow_bangla.txt'), 'utf8'), 'bn');

test('both documents split into 39 questions: 7 + 9 + 15 + 8 per section', () => {
  for (const chunks of [english, bangla]) {
    assert.strictEqual(chunks.length, 39);
    const perSection = [1, 2, 3, 4].map((n) => chunks.filter((c) => c.key.includes(`-s${n}-`)).length);
    assert.deepStrictEqual(perSection, [7, 9, 15, 8]);
  }
});

test('the same question carries the same number in both languages', () => {
  const strip = (key: string) => key.replace(/^(en|bn)-/, '');
  assert.deepStrictEqual(english.map((c) => strip(c.key)), bangla.map((c) => strip(c.key)));
});

test('every chunk is exactly one question with its answer, and nothing else', () => {
  for (const chunk of [...english, ...bangla]) {
    assert.ok(chunk.question.length > 10, chunk.key);
    assert.ok(chunk.answer.length > 20, chunk.key);
    assert.strictEqual(chunk.content, `Q: ${chunk.question}\nA: ${chunk.answer}`);
    // A marker inside the text would mean two questions ran together.
    assert.doesNotMatch(chunk.answer, /^(Q\d+|প্রশ্ন\s*[\d০-৯]+)\s*:/m, chunk.key);
    assert.doesNotMatch(chunk.question, /AI\s+Assistant\s*:|এআই\s+অ্যাসিস্ট্যান্ট\s*:/, chunk.key);
    // Section titles and "Target User" lines stay out of the answers.
    assert.doesNotMatch(chunk.answer, /^(SECTION|সেকশন)\s+[\d০-৯]+/m, chunk.key);
    assert.doesNotMatch(chunk.answer, /Target User|টার্গেট ইউজার/, chunk.key);
    assert.doesNotMatch(chunk.answer, /^[-=]{4,}$/m, chunk.key);
  }
});

test('the English Q12 is found although its marker is typed "AI   Assistant:" with extra spaces', () => {
  const q12 = english.find((c) => c.key === 'en-s3-q12');
  assert.ok(q12);
  assert.match(q12.question, /police checked my Iqama/);
  assert.match(q12.answer, /routine police checks/);
});

test('Bangla question numbers in Bangla digits are read (প্রশ্ন ১০, ১৫)', () => {
  assert.ok(bangla.some((c) => c.key === 'bn-s3-q10'));
  const q15 = bangla.find((c) => c.key === 'bn-s3-q15');
  assert.ok(q15);
  assert.match(q15.question, /প্রবাসী গার্ড অ্যাপ আমাকে কীভাবে সাহায্য/);
});

test('an answer that runs over several lines (a numbered list) is kept whole', () => {
  const en = english.find((c) => c.key === 'en-s4-q5')!;
  assert.match(en.answer, /three ways/);
  assert.match(en.answer, /1\. Tap the menu icon[\s\S]*2\. Tap your profile icon[\s\S]*3\. Use the "Quick Features"/);
  const bn = bangla.find((c) => c.key === 'bn-s4-q5')!;
  assert.match(bn.answer, /১\.[\s\S]*২\.[\s\S]*৩\./);
});

test('each chunk remembers its section heading', () => {
  assert.match(english[0].section, /CAREFUL CITIZEN ON FINANCE/);
  assert.match(english.find((c) => c.key === 'en-s4-q1')!.section, /INSTRUCTION & NAVIGATION GUIDE/);
  assert.match(bangla.find((c) => c.key === 'bn-s3-q1')!.section, /রেমিট্যান্স কর্মী/);
});

test('a malformed document fails loudly instead of leaving a hole', () => {
  const noAnswer = 'SECTION 1: TEST\nQ1: A question with nothing after it?\n\nQ2: Another?\nAI Assistant: Yes.';
  assert.throws(() => parseFaqDocument(noAnswer, 'en'), /question 1.*no answer/);

  const orphan = 'SECTION 1: TEST\nAI Assistant: An answer from nowhere.';
  assert.throws(() => parseFaqDocument(orphan, 'en'), /no question before it/);

  const noSection = 'Q1: Where am I?\nAI Assistant: Nowhere.';
  assert.throws(() => parseFaqDocument(noSection, 'en'), /before any section/);

  const twice = 'SECTION 1: T\nQ1: x?\nAI Assistant: a\nQ1: y?\nAI Assistant: b';
  assert.throws(() => parseFaqDocument(twice, 'en'), /duplicate question en-s1-q1/);
});

test('Windows line endings and a byte-order mark parse the same as plain text', () => {
  const text = '﻿SECTION 1: T\r\nQ1: One?\r\nAI Assistant: First.\r\n\r\nQ2: Two?\r\nAI Assistant: Second\r\nline.\r\n';
  const chunks = parseFaqDocument(text, 'en');
  assert.deepStrictEqual(chunks.map((c) => c.key), ['en-s1-q1', 'en-s1-q2']);
  assert.strictEqual(chunks[1].answer, 'Second\nline.');
});
