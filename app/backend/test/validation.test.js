const test = require('node:test');
const assert = require('node:assert/strict');
const { validateTaskText } = require('../server.js');

test('rejects empty text', () => {
  assert.equal(validateTaskText(''), 'text must not be empty');
  assert.equal(validateTaskText('   '), 'text must not be empty');
});

test('rejects non-string text', () => {
  assert.equal(validateTaskText(123), 'text must be a string');
  assert.equal(validateTaskText(undefined), 'text must be a string');
});

test('rejects text over 140 chars', () => {
  const long = 'a'.repeat(141);
  assert.equal(validateTaskText(long), 'text must be 140 characters or fewer');
});

test('accepts valid text', () => {
  assert.equal(validateTaskText('ship the alerting rules'), null);
});

test('accepts text at exactly 140 chars', () => {
  assert.equal(validateTaskText('a'.repeat(140)), null);
});
