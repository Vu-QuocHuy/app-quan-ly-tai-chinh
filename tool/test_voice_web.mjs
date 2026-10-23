import fs from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const html = fs.readFileSync('web/index.html', 'utf8');
const script = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/g)].map((m) => m[1]).find((s) => s.includes('_finmiStartSpeech'));
assert.ok(script, 'Speech bridge not found');
let time = 0, amplitude = 0, stopped = 0, closed = 0, requested;
const intervals = new Map();
const recognizers = [];
class Recognition {
  constructor() { recognizers.push(this); }
  start() {}
  stop() {
    this.onresult?.({results: [[{transcript: 'final words'}]]});
    this.onend?.();
  }
  abort() { this.onend?.(); }
}
class AudioContext {
  resume() { return Promise.resolve(); }
  close() { closed++; return Promise.resolve(); }
  createMediaStreamSource() { return {connect() {}}; }
  createAnalyser() { return {fftSize: 2048, getFloatTimeDomainData(samples) { samples.fill(amplitude); }}; }
}
const stream = {getTracks() { return [{stop() { stopped++; }}]; }};
const window = {SpeechRecognition: Recognition, AudioContext};
const context = vm.createContext({window, navigator: {mediaDevices: {getUserMedia() { return requested ?? Promise.resolve(stream); }}}, console,
  performance: {now: () => time}, Float32Array,
  setInterval(fn) { const id = intervals.size + 1; intervals.set(id, fn); return id; },
  clearInterval(id) { intervals.delete(id); },
});
vm.runInContext(script, context);
const events = [];
window._finmiStartSpeech('en-US', (text) => events.push(text), (e) => { throw new Error(e); }, () => events.push('end'), () => { events.push('silence'); window._finmiStopSpeech(); });
await Promise.resolve(); await Promise.resolve();
assert.equal(recognizers[0].lang, 'en-US');
function sample(at, value) { time = at; amplitude = value; [...intervals.values()].forEach((fn) => fn()); }
sample(1000, 0); sample(5000, 0);
assert.deepEqual(events, [], 'Empty microphone must not submit');
sample(5100, 0.1); sample(5300, 0.1); sample(7700, 0);
assert.deepEqual(events, [], 'Must wait a full 2.5 seconds after speech');
sample(7800, 0);
assert.deepEqual(events, ['silence', 'final words', 'end'], 'Final transcript must precede completion');
assert.equal(intervals.size, 0); assert.ok(stopped > 0); assert.ok(closed > 0);
const stale = recognizers[0].onresult;
window._finmiStartSpeech('vi-VN', (text) => events.push(text), () => {}, () => {}, () => {});
await Promise.resolve(); await Promise.resolve();
stale({results: [[{transcript: 'stale'}]]});
assert.ok(!events.includes('stale'), 'Old session callback leaked');
window._finmiAbortSpeech();
let resolve;
requested = new Promise((done) => { resolve = done; });
const count = recognizers.length;
window._finmiStartSpeech('vi-VN', () => {}, () => {}, () => {}, () => {});
window._finmiAbortSpeech();
resolve(stream);
await Promise.resolve(); await Promise.resolve();
assert.equal(recognizers.length, count, 'Cancelled permission request restarted recording');
console.log('PASS: web speech languages, VAD silence, final words, cleanup, stale callbacks and permission cancellation');
