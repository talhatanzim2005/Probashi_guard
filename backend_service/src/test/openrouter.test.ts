import test from 'node:test';
import assert from 'node:assert';
import OpenAI from 'openai';
import { ModelOutputError, modelList, statusOf, withModelFallback } from '../ai/openrouter.js';
import { plainText } from '../ai/prohori.js';

const apiError = (status: number) => OpenAI.APIError.generate(status, { message: `HTTP ${status}` }, `HTTP ${status}`, new Headers());

test('modelList splits a comma list, trims it and falls back to the defaults', () => {
  assert.deepStrictEqual(modelList(' a/b:free , c/d ,,', ['x']), ['a/b:free', 'c/d']);
  assert.deepStrictEqual(modelList('', ['x', 'y']), ['x', 'y']);
  assert.deepStrictEqual(modelList(undefined, ['x']), ['x']);
});

test('the first model that answers wins, and the rest are not called', async () => {
  const called: string[] = [];
  const served = await withModelFallback(['a', 'b', 'c'], async (m) => {
    called.push(m);
    return `from ${m}`;
  });
  assert.deepStrictEqual(served, { value: 'from a', model: 'a' });
  assert.deepStrictEqual(called, ['a']);
});

test('a model that is gone, forbidden, busy or erroring hands over to the next', async () => {
  for (const status of [403, 404, 429, 500, 503]) {
    const called: string[] = [];
    const served = await withModelFallback(['a', 'b'], async (m) => {
      called.push(m);
      if (m === 'a') throw apiError(status);
      return 'ok';
    });
    assert.strictEqual(served.model, 'b', `status ${status}`);
    assert.deepStrictEqual(called, ['a', 'b']);
  }
});

test('an empty or unusable answer also moves on to the next model', async () => {
  const served = await withModelFallback(['a', 'b'], async (m) => {
    if (m === 'a') throw new ModelOutputError('empty');
    return 'ok';
  });
  assert.strictEqual(served.model, 'b');
});

test('a bad request or a bad key stops at once: another model would fail the same way', async () => {
  for (const status of [400, 401]) {
    const called: string[] = [];
    await assert.rejects(
      withModelFallback(['a', 'b'], async (m) => {
        called.push(m);
        throw apiError(status);
      }),
      (err: unknown) => statusOf(err) === status,
    );
    assert.deepStrictEqual(called, ['a'], `status ${status}`);
  }
});

test('when every model fails, a 429 is the error reported, so the caller can say "busy"', async () => {
  await assert.rejects(
    withModelFallback(['a', 'b', 'c'], async (m) => {
      throw apiError(m === 'b' ? 429 : 404);
    }),
    (err: unknown) => statusOf(err) === 429,
  );
  await assert.rejects(
    withModelFallback(['a', 'b'], async () => {
      throw apiError(503);
    }),
    (err: unknown) => statusOf(err) === 503,
  );
});

test('once the deadline has passed no further model is tried', async () => {
  const controller = new AbortController();
  const called: string[] = [];
  await assert.rejects(
    withModelFallback(
      ['a', 'b'],
      async (m) => {
        called.push(m);
        controller.abort(new Error('deadline'));
        throw apiError(429);
      },
      controller.signal,
    ),
    // The attempt's own error comes back; callers check the signal to answer 504.
    (err: unknown) => statusOf(err) === 429,
  );
  assert.deepStrictEqual(called, ['a']);
  assert.ok(controller.signal.aborted);

  // Already past the deadline before the first model: nothing is called at all.
  const none: string[] = [];
  await assert.rejects(
    withModelFallback(['a'], async (m) => void none.push(m), AbortSignal.abort(new Error('too late'))),
    /too late/,
  );
  assert.deepStrictEqual(none, []);
});

test('an empty model list is an error, not a silent success', async () => {
  await assert.rejects(withModelFallback([], async () => 'x'), /No model is configured/);
});

test('plainText removes the markdown the app would show as stray symbols', () => {
  assert.strictEqual(
    plainText('Tap the **Payment** tab, then *Send* and `Receive`.'),
    'Tap the Payment tab, then Send and Receive.',
  );
  assert.strictEqual(plainText('## Steps\n* First\n- Second\n1. Third'), 'Steps\n• First\n• Second\n1. Third');
  assert.strictEqual(plainText('```text\nhello\n```'), 'hello');
  assert.strictEqual(plainText('a\n\n\n\nb'), 'a\n\nb');
  assert.strictEqual(plainText('1. Open Payment.  \n2. Tap Send.  '), '1. Open Payment.\n2. Tap Send.');
});

test('plainText leaves ordinary text, Bangla and arithmetic alone', () => {
  assert.strictEqual(plainText('বেতন কমপক্ষে ১,০০০ রিয়াল হওয়া উচিত।'), 'বেতন কমপক্ষে ১,০০০ রিয়াল হওয়া উচিত।');
  assert.strictEqual(plainText('2 * 3 = 6 and snake_case_name stays'), '2 * 3 = 6 and snake_case_name stays');
  assert.strictEqual(plainText('  hello  '), 'hello');
});
