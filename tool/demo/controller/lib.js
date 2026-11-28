/* Finmi AI Lab - pure helpers shared by index.html (controller), metrics.html
 * and the Node unit tests (lib.test.js).  Classic script, no dependencies.
 * Protocol: docs/ai-optimization/ailab-protocol.md
 */
(function (root, factory) {
  'use strict';
  var api = factory();
  if (typeof module === 'object' && module && module.exports) {
    module.exports = api;
  }
  if (root) root.FinmiLib = api;
})(typeof window !== 'undefined' ? window : (typeof globalThis !== 'undefined' ? globalThis : this), function () {
  'use strict';

  var DASH = '—';          // "—" shown for missing values
  var MINUS = '−';         // "−" used for negative deltas
  var EN = '–';            // "–" in the profile names

  // ---- Protocol constants (section 4 of the protocol) ----------------------
  var FLAGS = [
    { key: 'ai.extract.thinking_low',   group: 'Đọc hóa đơn', name: 'Giảm suy luận của AI',             where: 'server' },
    { key: 'ai.extract.image_1600',     group: 'Đọc hóa đơn', name: 'Thu nhỏ ảnh về 1600 px',           where: 'máy' },
    { key: 'ai.extract.precheck_dedup', group: 'Đọc hóa đơn', name: 'Chặn ảnh trùng trước khi gọi AI',  where: 'máy' },
    { key: 'ai.extract.validator',      group: 'Đọc hóa đơn', name: 'Hậu kiểm số học hóa đơn',          where: 'máy' },
    { key: 'ai.chat.local_router',      group: 'Chat',        name: 'Trả lời câu tra cứu trên máy',     where: 'máy' },
    { key: 'ai.chat.merge_calls',       group: 'Chat',        name: 'Gộp lượt gọi chat',                where: 'máy' },
    { key: 'ai.chat.prompt_v2',         group: 'Chat',        name: 'Prompt chat rút gọn',              where: 'server' },
    { key: 'ai.classify.local',         group: 'Chat',        name: 'Phân loại cửa hàng trên máy',      where: 'máy' },
    { key: 'ai.router.failover',        group: 'Nền tảng',    name: 'Dự phòng 9Router → Gemini',        where: 'server' },
    { key: 'ai.telemetry.upload',       group: 'Nền tảng',    name: 'Gửi telemetry lên server',         where: 'máy' }
  ];
  var FLAG_KEYS = FLAGS.map(function (f) { return f.key; });

  // Origins the apps run on -> pane.  The controller itself runs on 8090.
  var ORIGIN_PANES = {
    'http://localhost:8080': 'b0',
    'http://127.0.0.1:8080': 'b0',
    'http://localhost:8081': 'b1',
    'http://127.0.0.1:8081': 'b1'
  };
  var APP_URLS = { b0: 'http://localhost:8080/', b1: 'http://localhost:8081/' };
  var CHANNEL_NAME = 'finmi-ailab';

  // Fields of the `metrics` event the pages are allowed to read (protocol 2).
  var METRIC_FIELDS = {
    top: ['ailab', 'event', 'ts', 'launchProfile', 'profile', 'enabledCount',
      'flagSet', 'flags', 'serverFlagSet', 'totals', 'lastExtract', 'turns', 'calls'],
    totals: ['llmCalls', 'tokens', 'savedLlmCalls', 'costUsd', 'savedUsd', 'savedOcrCalls'],
    lastExtract: ['inputTokens', 'thinkingTokens', 'outputTokens', 'durationMs', 'provider'],
    turn: ['messageId', 'route', 'llmCalls', 'durationMs', 'provider'],
    call: ['action', 'durationMs', 'llmCalls', 'provider', 'failover',
      'inputTokens', 'outputTokens', 'thinkingTokens']
  };
  var MAX_TURNS = 20;
  var MAX_CALLS = 30;
  var MAX_STR = 200;

  // ---- tolerant readers ----------------------------------------------------
  function isObj(v) { return v !== null && typeof v === 'object' && !Array.isArray(v); }
  function num(v) { return typeof v === 'number' && isFinite(v) ? v : null; }
  function str(v) {
    if (typeof v !== 'string') return null;
    return v.length > MAX_STR ? v.slice(0, MAX_STR) : v;
  }
  function bool(v) { return typeof v === 'boolean' ? v : null; }
  function lastN(list, n) {
    return Array.isArray(list) ? list.slice(Math.max(0, list.length - n)) : [];
  }

  function normalizeTurn(raw) {
    var t = isObj(raw) ? raw : {};
    return {
      messageId: str(t.messageId),
      route: str(t.route),
      llmCalls: num(t.llmCalls),
      durationMs: num(t.durationMs),
      provider: str(t.provider)
    };
  }

  function normalizeCall(raw) {
    var c = isObj(raw) ? raw : {};
    return {
      action: str(c.action),
      durationMs: num(c.durationMs),
      llmCalls: num(c.llmCalls),
      provider: str(c.provider),
      failover: c.failover === true,
      inputTokens: num(c.inputTokens),
      outputTokens: num(c.outputTokens),
      thinkingTokens: num(c.thinkingTokens)
    };
  }

  /** Never throws.  Returns null when `raw` is not an object. */
  function normalizeMetrics(raw) {
    try {
      if (!isObj(raw)) return null;
      var profile = str(raw.profile);
      if (['b0', 'b1', 'custom', 'server'].indexOf(profile) < 0) profile = null;

      var rawFlags = isObj(raw.flags) ? raw.flags : {};
      var flags = {};
      FLAG_KEYS.forEach(function (k) { flags[k] = bool(rawFlags[k]); });

      var enabledCount = num(raw.enabledCount);
      if (enabledCount === null) {
        var known = FLAG_KEYS.filter(function (k) { return flags[k] !== null; });
        if (known.length === FLAG_KEYS.length) {
          enabledCount = known.filter(function (k) { return flags[k]; }).length;
        }
      }

      var tot = isObj(raw.totals) ? raw.totals : {};
      var totals = {};
      METRIC_FIELDS.totals.forEach(function (k) { totals[k] = num(tot[k]); });

      var lastExtract = null;
      if (isObj(raw.lastExtract)) {
        var ex = raw.lastExtract;
        lastExtract = {
          inputTokens: num(ex.inputTokens),
          thinkingTokens: num(ex.thinkingTokens),
          outputTokens: num(ex.outputTokens),
          durationMs: num(ex.durationMs),
          provider: str(ex.provider)
        };
      }

      return {
        ailab: 1,
        event: 'metrics',
        ts: num(raw.ts),
        launchProfile: str(raw.launchProfile),
        profile: profile,
        enabledCount: enabledCount,
        flagSet: str(raw.flagSet),
        flags: flags,
        serverFlagSet: str(raw.serverFlagSet),
        totals: totals,
        lastExtract: lastExtract,
        turns: lastN(raw.turns, MAX_TURNS).map(normalizeTurn),
        calls: lastN(raw.calls, MAX_CALLS).map(normalizeCall)
      };
    } catch (e) {
      return null;
    }
  }

  /** A well-formed envelope from an app (not yet normalised). */
  function isMetricsMessage(data) {
    return isObj(data) && data.ailab === 1 && data.event === 'metrics';
  }

  function paneFromOrigin(origin) {
    return Object.prototype.hasOwnProperty.call(ORIGIN_PANES, origin) ? ORIGIN_PANES[origin] : null;
  }

  // ---- profile / flags -----------------------------------------------------
  /** 'b0' | 'b1' | 'custom' | 'server' | 'none' (no data) */
  function profileTone(metrics) {
    if (!metrics) return 'none';
    var p = metrics.profile;
    if (p === 'b0' || p === 'b1' || p === 'custom' || p === 'server') return p;
    var n = metrics.enabledCount;
    if (n === 0) return 'b0';
    if (n === FLAG_KEYS.length) return 'b1';
    if (n !== null && n !== undefined) return 'custom';
    return 'none';
  }

  function profileLabel(metrics) {
    var tone = profileTone(metrics);
    if (tone === 'b0') return 'B0 ' + EN + ' GỐC';
    if (tone === 'b1') return 'B1 ' + EN + ' TỐI ƯU';
    if (tone === 'server') return 'SERVER';
    if (tone === 'custom') {
      var n = metrics.enabledCount;
      return 'TÙY CHỈNH ' + (typeof n === 'number' ? n : '?') + '/' + FLAG_KEYS.length;
    }
    return 'CHƯA CÓ DỮ LIỆU';
  }

  function flagSetToArray(s) {
    if (typeof s !== 'string') return null;
    var t = s.trim();
    if (t === '' || t === 'none') return [];
    return t.split(',').map(function (x) { return x.trim(); }).filter(Boolean).sort();
  }

  /** True when the server reports a flag set different from the client's. */
  function flagMismatch(metrics) {
    if (!metrics) return false;
    var sv = metrics.serverFlagSet;
    if (typeof sv !== 'string' || sv.trim() === '' || sv.trim() === 'null') return false;
    var a = flagSetToArray(metrics.flagSet);
    var b = flagSetToArray(sv);
    if (a === null || b === null) return false;
    return a.join(',') !== b.join(',');
  }

  /** Flag keys whose reported state differs between two normalised metrics. */
  function flagsDiff(m0, m1) {
    if (!m0 || !m1) return [];
    return FLAG_KEYS.filter(function (k) {
      var a = m0.flags[k], b = m1.flags[k];
      return a !== null && b !== null && a !== b;
    });
  }

  // ---- deltas / numbers ----------------------------------------------------
  /** (b1 - b0) / b0 * 100, or null when not computable. */
  function percentDelta(b0, b1) {
    if (typeof b0 !== 'number' || typeof b1 !== 'number') return null;
    if (!isFinite(b0) || !isFinite(b1) || b0 === 0) return null;
    return (b1 - b0) / Math.abs(b0) * 100;
  }

  function formatDelta(pct) {
    if (typeof pct !== 'number' || !isFinite(pct)) return DASH;
    var r = Math.round(pct);
    if (r === 0) return '0%';
    return (r < 0 ? MINUS : '+') + Math.abs(r) + '%';
  }

  function groupThousands(intStr) {
    return intStr.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  }

  function formatInt(n) {
    if (typeof n !== 'number' || !isFinite(n)) return DASH;
    var r = Math.round(n);
    return (r < 0 ? MINUS : '') + groupThousands(String(Math.abs(r)));
  }

  function formatMs(ms) {
    if (typeof ms !== 'number' || !isFinite(ms) || ms < 0) return DASH;
    if (ms < 999.5) return Math.round(ms) + ' ms';
    var s = (Math.round(ms / 100) / 10).toFixed(1).replace('.', ',');
    return s + ' s';
  }

  function formatUsd(v) {
    if (typeof v !== 'number' || !isFinite(v)) return DASH;
    var abs = Math.abs(v);
    var digits = abs !== 0 && abs < 0.01 ? 4 : 2;
    var fixed = abs.toFixed(digits).split('.');
    return (v < 0 ? MINUS : '') + '$' + groupThousands(fixed[0]) + ',' + fixed[1];
  }

  function formatVnd(v) {
    if (typeof v !== 'number' || !isFinite(v)) return DASH;
    return formatInt(v) + ' ₫';
  }

  var USD_TO_VND = 25000;
  function usdToVnd(usd, rate) {
    if (typeof usd !== 'number' || !isFinite(usd)) return null;
    return usd * (typeof rate === 'number' ? rate : USD_TO_VND);
  }

  function formatPercent(p) {
    if (typeof p !== 'number' || !isFinite(p)) return DASH;
    return Math.round(p) + '%';
  }

  /** Share (0..100) of the given turns answered on the device. null if none. */
  function localShare(turns) {
    if (!Array.isArray(turns) || turns.length === 0) return null;
    var local = turns.filter(function (t) { return isObj(t) && t.route === 'local'; }).length;
    return local / turns.length * 100;
  }

  function sumTokens(call) {
    if (!isObj(call)) return null;
    var parts = [call.inputTokens, call.outputTokens, call.thinkingTokens].filter(function (v) {
      return typeof v === 'number' && isFinite(v);
    });
    if (parts.length === 0) return null;
    return parts.reduce(function (a, b) { return a + b; }, 0);
  }

  function ageLabel(ms) {
    if (typeof ms !== 'number' || !isFinite(ms) || ms < 0) return DASH;
    var s = Math.floor(ms / 1000);
    if (s < 2) return 'vừa xong';
    if (s < 60) return s + ' giây trước';
    var m = Math.floor(s / 60);
    if (m < 60) return m + ' phút trước';
    return Math.floor(m / 60) + ' giờ trước';
  }

  // ---- routes --------------------------------------------------------------
  var ROUTES = {
    local:    { label: 'Trên máy', short: 'M', color: 'var(--route-local)' },
    cloud:    { label: 'Đám mây',  short: 'C', color: 'var(--route-cloud)' },
    fallback: { label: 'Dự phòng', short: 'D', color: 'var(--route-fallback)' },
    degraded: { label: 'Suy giảm', short: 'G', color: 'var(--route-degraded)' }
  };
  var ROUTE_ORDER = ['local', 'cloud', 'fallback', 'degraded'];

  function routeLabel(route) {
    return ROUTES[route] ? ROUTES[route].label : (typeof route === 'string' && route ? route : DASH);
  }
  function routeColor(route) {
    return ROUTES[route] ? ROUTES[route].color : 'var(--route-other)';
  }
  function routeShort(route) {
    return ROUTES[route] ? ROUTES[route].short : '?';
  }

  return {
    DASH: DASH, MINUS: MINUS,
    FLAGS: FLAGS, FLAG_KEYS: FLAG_KEYS, ORIGIN_PANES: ORIGIN_PANES, APP_URLS: APP_URLS,
    CHANNEL_NAME: CHANNEL_NAME, METRIC_FIELDS: METRIC_FIELDS,
    ROUTES: ROUTES, ROUTE_ORDER: ROUTE_ORDER,
    normalizeMetrics: normalizeMetrics, isMetricsMessage: isMetricsMessage,
    paneFromOrigin: paneFromOrigin,
    profileTone: profileTone, profileLabel: profileLabel,
    flagMismatch: flagMismatch, flagsDiff: flagsDiff,
    percentDelta: percentDelta, formatDelta: formatDelta,
    formatInt: formatInt, formatMs: formatMs, formatUsd: formatUsd, formatVnd: formatVnd,
    usdToVnd: usdToVnd, formatPercent: formatPercent,
    localShare: localShare, sumTokens: sumTokens, ageLabel: ageLabel,
    routeLabel: routeLabel, routeColor: routeColor, routeShort: routeShort
  };
});
