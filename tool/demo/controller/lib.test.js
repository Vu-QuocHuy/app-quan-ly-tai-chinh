'use strict';
// Run: node --test tool/demo/controller/
const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('./lib.js');

const allFlags = (v) => Object.fromEntries(L.FLAG_KEYS.map((k) => [k, v]));

function sample(over) {
  return Object.assign({
    ailab: 1, event: 'metrics', ts: 1764300000000, launchProfile: 'b0', profile: 'b0',
    enabledCount: 0, flagSet: 'none', flags: allFlags(false), serverFlagSet: 'none',
    totals: { llmCalls: 12, tokens: 18450, savedLlmCalls: 9, costUsd: 0.5, savedUsd: 0.1, savedOcrCalls: 1 },
    lastExtract: { inputTokens: 2094, thinkingTokens: 0, outputTokens: 191, durationMs: 7022, provider: 'gemini' },
    turns: [{ messageId: 'a', route: 'local', llmCalls: 0, durationMs: 40, provider: null }],
    calls: [{ action: 'chat', durationMs: 2100, llmCalls: 1, provider: '9router', failover: false,
      inputTokens: 900, outputTokens: 120, thinkingTokens: null }]
  }, over || {});
}

test('flag table has the 10 protocol flags in order', () => {
  assert.equal(L.FLAGS.length, 10);
  assert.equal(L.FLAGS[0].key, 'ai.extract.thinking_low');
  assert.equal(L.FLAGS[9].key, 'ai.telemetry.upload');
  assert.equal(new Set(L.FLAG_KEYS).size, 10);
});

test('normalizeMetrics keeps a valid message intact', () => {
  const m = L.normalizeMetrics(sample());
  assert.equal(m.profile, 'b0');
  assert.equal(m.totals.tokens, 18450);
  assert.equal(m.lastExtract.inputTokens, 2094);
  assert.equal(m.turns[0].route, 'local');
  assert.equal(m.calls[0].provider, '9router');
  assert.equal(m.calls[0].thinkingTokens, null);
  assert.equal(Object.keys(m.flags).length, 10);
});

test('normalizeMetrics never throws and returns null for non-objects', () => {
  for (const bad of [null, undefined, 5, 'x', [], true, () => 1]) {
    assert.equal(L.normalizeMetrics(bad), null);
  }
  const hostile = {
    get totals() { throw new Error('boom'); },
  };
  assert.doesNotThrow(() => L.normalizeMetrics(hostile));
});

test('normalizeMetrics turns wrong types into nulls and defaults', () => {
  const m = L.normalizeMetrics({
    profile: 42, enabledCount: '3', flags: 'nope', totals: [1], lastExtract: 'x',
    turns: 'x', calls: { a: 1 }, flagSet: 7,
  });
  assert.equal(m.profile, null);
  assert.equal(m.enabledCount, null);
  assert.equal(m.flagSet, null);
  assert.ok(L.FLAG_KEYS.every((k) => m.flags[k] === null));
  assert.equal(m.totals.llmCalls, null);
  assert.equal(m.lastExtract, null);
  assert.deepEqual(m.turns, []);
  assert.deepEqual(m.calls, []);
});

test('normalizeMetrics rejects NaN/Infinity and bad list entries', () => {
  const m = L.normalizeMetrics(sample({
    totals: { llmCalls: NaN, tokens: Infinity, costUsd: '1' },
    turns: [null, 5, { route: 3, durationMs: 'x' }],
    calls: [{ failover: 'yes', durationMs: -Infinity }],
  }));
  assert.equal(m.totals.llmCalls, null);
  assert.equal(m.totals.tokens, null);
  assert.equal(m.totals.costUsd, null);
  assert.equal(m.turns.length, 3);
  assert.equal(m.turns[2].route, null);
  assert.equal(m.turns[2].durationMs, null);
  assert.equal(m.calls[0].failover, false);
  assert.equal(m.calls[0].durationMs, null);
});

test('normalizeMetrics clamps lists to the newest 20 turns and 30 calls', () => {
  const turns = Array.from({ length: 50 }, (_, i) => ({ route: 'cloud', durationMs: i }));
  const calls = Array.from({ length: 80 }, (_, i) => ({ action: 'chat', durationMs: i }));
  const m = L.normalizeMetrics(sample({ turns, calls }));
  assert.equal(m.turns.length, 20);
  assert.equal(m.turns[19].durationMs, 49);
  assert.equal(m.turns[0].durationMs, 30);
  assert.equal(m.calls.length, 30);
  assert.equal(m.calls[29].durationMs, 79);
});

test('normalizeMetrics truncates huge strings and derives enabledCount', () => {
  const m = L.normalizeMetrics(sample({
    enabledCount: undefined, flags: allFlags(true), launchProfile: 'x'.repeat(5000),
  }));
  assert.equal(m.launchProfile.length, 200);
  assert.equal(m.enabledCount, 10);
});

test('isMetricsMessage / paneFromOrigin', () => {
  assert.ok(L.isMetricsMessage({ ailab: 1, event: 'metrics' }));
  assert.ok(!L.isMetricsMessage({ ailab: 2, event: 'metrics' }));
  assert.ok(!L.isMetricsMessage({ ailab: 1, event: 'other' }));
  assert.ok(!L.isMetricsMessage(null));
  assert.equal(L.paneFromOrigin('http://localhost:8080'), 'b0');
  assert.equal(L.paneFromOrigin('http://127.0.0.1:8081'), 'b1');
  assert.equal(L.paneFromOrigin('http://localhost:8090'), null);
  assert.equal(L.paneFromOrigin('http://evil.example:8080'), null);
  assert.equal(L.paneFromOrigin('toString'), null);
  assert.equal(L.paneFromOrigin(undefined), null);
});

test('profileLabel', () => {
  const n = (o) => L.normalizeMetrics(sample(o));
  assert.equal(L.profileLabel(n({ profile: 'b0' })), 'B0 – GỐC');
  assert.equal(L.profileLabel(n({ profile: 'b1', enabledCount: 10 })), 'B1 – TỐI ƯU');
  assert.equal(L.profileLabel(n({ profile: 'custom', enabledCount: 4 })), 'TÙY CHỈNH 4/10');
  assert.equal(L.profileLabel(n({ profile: 'server' })), 'SERVER');
  assert.equal(L.profileLabel(null), 'CHƯA CÓ DỮ LIỆU');
  assert.equal(L.profileTone(n({ profile: 'custom' })), 'custom');
  assert.equal(L.profileTone(null), 'none');
});

test('profileLabel falls back to enabledCount when profile is unknown', () => {
  const n = (o) => L.normalizeMetrics(sample(Object.assign({ profile: 'zzz' }, o)));
  assert.equal(L.profileLabel(n({ enabledCount: 0 })), 'B0 – GỐC');
  assert.equal(L.profileLabel(n({ enabledCount: 10 })), 'B1 – TỐI ƯU');
  assert.equal(L.profileLabel(n({ enabledCount: 7 })), 'TÙY CHỈNH 7/10');
});

test('flagMismatch', () => {
  const n = (o) => L.normalizeMetrics(sample(o));
  assert.equal(L.flagMismatch(null), false);
  assert.equal(L.flagMismatch(n({ flagSet: 'a,b', serverFlagSet: 'b,a' })), false);
  assert.equal(L.flagMismatch(n({ flagSet: 'a,b', serverFlagSet: 'a' })), true);
  assert.equal(L.flagMismatch(n({ flagSet: 'a', serverFlagSet: 'none' })), true);
  assert.equal(L.flagMismatch(n({ flagSet: 'none', serverFlagSet: 'none' })), false);
  assert.equal(L.flagMismatch(n({ flagSet: '', serverFlagSet: 'none' })), false);
  assert.equal(L.flagMismatch(n({ flagSet: 'a', serverFlagSet: null })), false);
  assert.equal(L.flagMismatch(n({ flagSet: 'a', serverFlagSet: 'null' })), false);
  assert.equal(L.flagMismatch(n({ flagSet: null, serverFlagSet: 'a' })), false);
});

test('flagsDiff lists only keys known on both sides and different', () => {
  const a = L.normalizeMetrics(sample({ flags: allFlags(false) }));
  const f = allFlags(true);
  f['ai.chat.merge_calls'] = false;
  const b = L.normalizeMetrics(sample({ flags: f }));
  assert.equal(L.flagsDiff(a, b).length, 9);
  assert.ok(!L.flagsDiff(a, b).includes('ai.chat.merge_calls'));
  assert.deepEqual(L.flagsDiff(a, null), []);
  const unknown = L.normalizeMetrics({ flags: {} });
  assert.deepEqual(L.flagsDiff(a, unknown), []);
});

test('percentDelta is null-safe', () => {
  assert.equal(Math.round(L.percentDelta(1000, 690)), -31);
  assert.equal(L.percentDelta(100, 150), 50);
  assert.equal(L.percentDelta(0, 5), null);
  assert.equal(L.percentDelta(null, 5), null);
  assert.equal(L.percentDelta(5, undefined), null);
  assert.equal(L.percentDelta(NaN, 5), null);
  assert.equal(L.percentDelta('5', 5), null);
  assert.equal(L.percentDelta(-100, -50), 50);
});

test('formatDelta', () => {
  assert.equal(L.formatDelta(-31.2), '−31%');
  assert.equal(L.formatDelta(12.4), '+12%');
  assert.equal(L.formatDelta(0.2), '0%');
  assert.equal(L.formatDelta(-0.3), '0%');
  assert.equal(L.formatDelta(null), '—');
});

test('formatMs uses Vietnamese decimal comma', () => {
  assert.equal(L.formatMs(40), '40 ms');
  assert.equal(L.formatMs(0), '0 ms');
  assert.equal(L.formatMs(2100), '2,1 s');
  assert.equal(L.formatMs(7022), '7,0 s');
  assert.equal(L.formatMs(61000), '61,0 s');
  assert.equal(L.formatMs(null), '—');
  assert.equal(L.formatMs(-5), '—');
  assert.equal(L.formatMs(NaN), '—');
});

test('formatInt uses dot thousands', () => {
  assert.equal(L.formatInt(1234), '1.234');
  assert.equal(L.formatInt(18450), '18.450');
  assert.equal(L.formatInt(1234567), '1.234.567');
  assert.equal(L.formatInt(12), '12');
  assert.equal(L.formatInt(0), '0');
  assert.equal(L.formatInt(1234.6), '1.235');
  assert.equal(L.formatInt(-1500), '−1.500');
  assert.equal(L.formatInt(null), '—');
  assert.equal(L.formatInt('7'), '—');
});

test('formatUsd / formatVnd', () => {
  assert.equal(L.formatUsd(1.25), '$1,25');
  assert.equal(L.formatUsd(0.0042), '$0,0042');
  assert.equal(L.formatUsd(0), '$0,00');
  assert.equal(L.formatUsd(1234.5), '$1.234,50');
  assert.equal(L.formatUsd(null), '—');
  assert.equal(L.formatVnd(25000), '25.000 ₫');
  assert.equal(L.formatVnd(null), '—');
  assert.equal(L.usdToVnd(2), 50000);
  assert.equal(L.usdToVnd(undefined), null);
});

test('localShare', () => {
  assert.equal(L.localShare([]), null);
  assert.equal(L.localShare(null), null);
  assert.equal(L.localShare([{ route: 'local' }, { route: 'cloud' }]), 50);
  assert.equal(L.localShare([{ route: 'local' }, null, { route: 'x' }, { route: 'local' }]), 50);
  assert.equal(L.localShare([{ route: 'cloud' }]), 0);
  assert.equal(L.formatPercent(L.localShare([{ route: 'local' }, { route: 'cloud' }, { route: 'cloud' }])), '33%');
});

test('routeLabel / routeColor', () => {
  assert.equal(L.routeLabel('local'), 'Trên máy');
  assert.equal(L.routeLabel('cloud'), 'Đám mây');
  assert.equal(L.routeLabel('fallback'), 'Dự phòng');
  assert.equal(L.routeLabel('degraded'), 'Suy giảm');
  assert.equal(L.routeLabel('weird'), 'weird');
  assert.equal(L.routeLabel(null), '—');
  assert.equal(L.routeColor('local'), 'var(--route-local)');
  assert.equal(L.routeColor('nope'), 'var(--route-other)');
  assert.equal(new Set(L.ROUTE_ORDER.map(L.routeShort)).size, 4);
});

test('sumTokens and ageLabel', () => {
  assert.equal(L.sumTokens({ inputTokens: 900, outputTokens: 120, thinkingTokens: null }), 1020);
  assert.equal(L.sumTokens({ inputTokens: null }), null);
  assert.equal(L.sumTokens(null), null);
  assert.equal(L.ageLabel(500), 'vừa xong');
  assert.equal(L.ageLabel(5000), '5 giây trước');
  assert.equal(L.ageLabel(125000), '2 phút trước');
  assert.equal(L.ageLabel(null), '—');
});
