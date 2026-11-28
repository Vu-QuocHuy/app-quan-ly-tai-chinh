/* Finmi AI Lab - synthetic metrics for UI development.
 * Loaded ONLY when the page URL has ?mock=1 (see index.html / metrics.html).
 * Produces objects shaped exactly like the protocol `metrics` event.
 */
(function (root) {
  'use strict';
  var L = root.FinmiLib;
  var KEYS = L.FLAG_KEYS;

  function rng(seed) {
    var s = seed >>> 0;
    return function () {
      s = (s + 0x6D2B79F5) >>> 0;
      var t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function create(opts) {
    opts = opts || {};
    var mismatch = !!opts.mismatch;
    var rand = rng(20260101);
    var panes = {};

    function allFlags(v) {
      var f = {};
      KEYS.forEach(function (k) { f[k] = v; });
      return f;
    }

    function makeTurn(pane, i) {
      var flags = panes[pane].flags;
      var localOn = flags['ai.chat.local_router'];
      var r = rand();
      var route, ms, llm, provider;
      if (localOn && r < 0.55) {
        route = 'local'; ms = 20 + Math.round(rand() * 60); llm = 0; provider = null;
      } else if (r > 0.93) {
        route = 'degraded'; ms = 800 + Math.round(rand() * 900); llm = 0; provider = null;
      } else if (r > 0.86) {
        route = 'fallback'; ms = 2600 + Math.round(rand() * 2500); llm = 1; provider = 'gemini';
      } else {
        route = 'cloud';
        var base = flags['ai.chat.prompt_v2'] ? 1300 : 2300;
        ms = base + Math.round(rand() * 1700);
        llm = flags['ai.chat.merge_calls'] ? 1 : 2; provider = '9router';
      }
      return { messageId: pane + '-' + i, route: route, llmCalls: llm, durationMs: ms, provider: provider };
    }

    function makeCall(pane) {
      var flags = panes[pane].flags;
      var pick = rand();
      var action = pick < 0.5 ? 'chat' : pick < 0.7 ? 'assistant_command' : pick < 0.9 ? 'extract' : 'classify';
      var failover = flags['ai.router.failover'] ? rand() > 0.85 : rand() > 0.97;
      var thinking = action === 'extract' ? (flags['ai.extract.thinking_low'] ? 0 : 1200 + Math.round(rand() * 600)) : null;
      var inTok = action === 'extract'
        ? (flags['ai.extract.image_1600'] ? 1500 : 2500) + Math.round(rand() * 300)
        : (flags['ai.chat.prompt_v2'] ? 500 : 900) + Math.round(rand() * 200);
      return {
        action: action,
        durationMs: (action === 'extract' ? 4500 : 1400) + Math.round(rand() * 2400),
        llmCalls: 1,
        provider: failover ? 'gemini' : '9router',
        failover: failover,
        inputTokens: inTok,
        outputTokens: 80 + Math.round(rand() * 160),
        thinkingTokens: thinking
      };
    }

    function init(pane, on) {
      panes[pane] = {
        flags: allFlags(on), turns: [], calls: [], counter: 0, ts: 0,
        llmCalls: 0, tokens: 0, saved: 0, savedUsd: 0, costUsd: 0, savedOcr: 0, extractSeen: false
      };
      for (var i = 0; i < 14; i++) step(pane);
    }

    function step(pane) {
      var p = panes[pane];
      var t = makeTurn(pane, p.counter++);
      p.turns.push(t); if (p.turns.length > 20) p.turns.shift();
      var c = makeCall(pane);
      p.calls.push(c); if (p.calls.length > 30) p.calls.shift();
      p.llmCalls += t.llmCalls + 1;
      p.tokens += (c.inputTokens || 0) + (c.outputTokens || 0) + (c.thinkingTokens || 0);
      p.costUsd += 0.0004 * (t.llmCalls + 1);
      if (p.flags['ai.chat.local_router'] && t.route === 'local') { p.saved += 1; p.savedUsd += 0.0004; }
      if (p.flags['ai.extract.precheck_dedup'] && rand() > 0.9) { p.savedOcr += 1; }
      if (c.action === 'extract') p.extractSeen = true;
    }

    function snapshot(pane) {
      var p = panes[pane];
      var on = KEYS.filter(function (k) { return p.flags[k]; });
      var n = on.length;
      var extract = null;
      for (var i = p.calls.length - 1; i >= 0; i--) {
        if (p.calls[i].action === 'extract') {
          var c = p.calls[i];
          extract = { inputTokens: c.inputTokens, thinkingTokens: c.thinkingTokens,
            outputTokens: c.outputTokens, durationMs: c.durationMs, provider: c.provider };
          break;
        }
      }
      var flagSet = on.length ? on.join(',') : 'none';
      var server = flagSet;
      if (mismatch && pane === 'b1') server = on.slice(0, Math.max(0, on.length - 3)).join(',') || 'none';
      return {
        ailab: 1, event: 'metrics', ts: Date.now(),
        launchProfile: pane === 'b0' ? 'b0' : 'b1',
        profile: n === 0 ? 'b0' : n === KEYS.length ? 'b1' : 'custom',
        enabledCount: n,
        flagSet: flagSet,
        flags: JSON.parse(JSON.stringify(p.flags)),
        serverFlagSet: server,
        totals: { llmCalls: p.llmCalls, tokens: p.tokens, savedLlmCalls: p.saved,
          costUsd: p.costUsd, savedUsd: p.savedUsd, savedOcrCalls: p.savedOcr },
        lastExtract: extract,
        turns: JSON.parse(JSON.stringify(p.turns)),
        calls: JSON.parse(JSON.stringify(p.calls))
      };
    }

    /** Mimics the app's `flags` command: "b0" | "b1" | {key: bool}. */
    function setFlags(pane, value) {
      var p = panes[pane];
      if (value === 'b0') p.flags = allFlags(false);
      else if (value === 'b1') p.flags = allFlags(true);
      else if (value && typeof value === 'object') {
        KEYS.forEach(function (k) { if (typeof value[k] === 'boolean') p.flags[k] = value[k]; });
      }
    }

    function reset(pane) {
      var f = panes[pane].flags;
      init(pane, false);
      panes[pane].flags = f;
      panes[pane].turns = []; panes[pane].calls = [];
      panes[pane].llmCalls = panes[pane].tokens = panes[pane].saved = panes[pane].savedUsd =
        panes[pane].costUsd = panes[pane].savedOcr = 0;
    }

    init('b0', false);
    init('b1', true);
    return { snapshot: snapshot, step: step, setFlags: setFlags, reset: reset };
  }

  function isMockRequested(search) {
    var m = /[?&]mock=([^&]*)/.exec(search || '');
    return !!m && m[1] === '1';
  }
  function isMismatchRequested(search) {
    var m = /[?&]mismatch=([^&]*)/.exec(search || '');
    return !!m && m[1] === '1';
  }

  var BANNER_TEXT = 'DỮ LIỆU GIẢ LẬP – CHỈ ĐỂ THỬ GIAO DIỆN';
  function showBanner() {
    var el = document.createElement('div');
    el.id = 'mock-banner';
    el.setAttribute('role', 'alert');
    el.textContent = BANNER_TEXT;
    document.body.insertBefore(el, document.body.firstChild);
  }

  root.FinmiMock = {
    create: create, showBanner: showBanner, BANNER_TEXT: BANNER_TEXT,
    isMockRequested: isMockRequested, isMismatchRequested: isMismatchRequested
  };
})(window);
