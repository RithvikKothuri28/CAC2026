const { test } = require('node:test');
const assert = require('node:assert/strict');
const { sanitizePassport, sanitizeExplanationContext, renderExplanation, documentId } = require('../lib/validation');
const { renderPassportPage } = require('../lib/passport_page');

test('public page escapes farmer HTML and omits unknown properties', () => {
  const page = renderPassportPage({ crop: '<script>alert(1)</script>', notes: 'Hello & goodbye', ownerId: 'SECRET_OWNER' });
  assert.match(page, /&lt;script&gt;/);
  assert.match(page, /Hello &amp; goodbye/);
  assert.equal(page.includes('<script>'), false);
  assert.equal(page.includes('SECRET_OWNER'), false);
  assert.match(renderPassportPage({ crop: 'Example crop', provenance: 'sample' }), /Sample Farm/);
});

test('passport selected allowlist excludes every unselected private value', () => {
  const result = sanitizePassport({ crop: 'Test crop', field: 'Test field', notes: 'Private note', ownerId: 'secret-owner', debts: [900], financials: { revenue: 800 } }, ['crop']);
  assert.deepEqual(result, { schemaVersion: 1, provenance: 'farmerSupplied', selectedFields: ['crop'], crop: 'Test crop' });
});

test('passport validates nested events, dates, publication keys and duplicates', () => {
  for (const fields of [['crop', 'ownerId'], ['crop', 'crop'], [], ['field']]) {
    assert.throws(() => sanitizePassport({ crop: 'Test', field: 'Field' }, fields), { code: 'invalid-argument' });
  }
  assert.throws(() => sanitizePassport({ crop: 'Test', plantingDate: '2026-02-30' }, ['crop', 'plantingDate']), { code: 'invalid-argument' });
  assert.throws(() => sanitizePassport({ crop: 'Test', plantingDate: '2026-03-01', harvestDate: '2026-02-01' }, ['crop', 'plantingDate', 'harvestDate']), { code: 'invalid-argument' });
  assert.throws(() => sanitizePassport({ crop: 'Test', inputRecords: [{ name: 'Input', cost: 10 }] }, ['crop', 'inputRecords']), { code: 'invalid-argument' });
  assert.throws(() => sanitizePassport({ crop: 'Test' }, ['crop', 'notes']), { code: 'invalid-argument' });
  const result = sanitizePassport({ crop: 'Test', handlingEvents: [{ name: 'Washed', date: '2026-03-01', details: 'Farmer reported' }] }, ['crop', 'handlingEvents']);
  assert.equal(result.handlingEvents[0].date, '2026-03-01');
});

test('explanation context allows only finite calculated metrics', () => {
  assert.deepEqual(sanitizeExplanationContext({ waterUsage: 5, operatingIncome: -100 }), { waterUsage: 5, operatingIncome: -100 });
  for (const context of [{ ownerEmail: 'private@example.test' }, { waterUsage: Infinity }, {}, { waterUsage: '5' }]) {
    assert.throws(() => sanitizeExplanationContext(context), { code: 'invalid-argument' });
  }
});

test('provider cannot add numerical literals or reference absent metrics', () => {
  const metrics = { operatingIncome: -102.25, waterUsage: 100 };
  assert.equal(renderExplanation('Modeled income is {{operatingIncome}} with water use {{waterUsage}}.', metrics), 'Modeled income is -102.25 with water use 100.');
  for (const narrative of ['Revenue will be 6000.', 'Income improves by ten percent.', 'Water is {{unknown}}.', '{{waterUsage}} and 200.', '{malformed}', 'Revenue will be ①.']) {
    assert.throws(() => renderExplanation(narrative, metrics), { code: 'unavailable' });
  }
});

test('document path injection is rejected', () => {
  assert.equal(documentId('safe-123_abc', 'ID'), 'safe-123_abc');
  for (const id of ['../farms/private', '/', '', ' ', 'x'.repeat(129)]) assert.throws(() => documentId(id, 'ID'), { code: 'invalid-argument' });
});
