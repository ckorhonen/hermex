import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('worker exposes feedback and admin routes', () => {
  assert.match(source, /\/api\/feedback/);
  assert.match(source, /\/api\/admin\/feedback/);
  assert.match(source, /validateFeedbackPayload/);
});

test('worker enforces bounded feedback payloads and rate limits', () => {
  assert.match(source, /maxFeedbackBodyBytes = 5 \* 1024 \* 1024/);
  assert.match(source, /feedbackRateLimit = 12/);
  assert.match(source, /Too many feedback reports/);
});

test('worker stores screenshot and annotation json in D1', () => {
  assert.match(source, /screenshot_json/);
  assert.match(source, /annotation_json/);
  assert.match(source, /INSERT INTO feedback/);
});
