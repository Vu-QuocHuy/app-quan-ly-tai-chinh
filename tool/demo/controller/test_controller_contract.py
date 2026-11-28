"""Keeps the AI Lab web pages (controller + metrics), lib.js, the protocol doc
and the Dart sources in step.

Run: python -I tool/demo/controller/test_controller_contract.py
"""
import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


INDEX = read(HERE / "index.html")
METRICS = read(HERE / "metrics.html")
LIB = read(HERE / "lib.js")
MOCK = read(HERE / "mock.js")
CSS = read(HERE / "theme.css")
DART = read(ROOT / "lib" / "features" / "ai_lab" / "data" / "ai_lab_bridge.dart")
FLAGS_DART = read(ROOT / "lib" / "core" / "config" / "feature_flags.dart")
PROTOCOL = read(ROOT / "docs" / "ai-optimization" / "ailab-protocol.md")
PS1 = read(ROOT / "tool" / "run_dual_instances.ps1")
BAT = read(ROOT / "tool" / "run_dual_instances.bat")
PACKAGE = json.loads(read(ROOT / "package.json"))

# `flags` and `hello` are parsed by the Dart side being written separately:
# do not assert against Dart parser internals for them.
OLD_COMMANDS = {"ask", "fault", "importAsset", "tamper", "reset"}
PROTOCOL_COMMANDS = OLD_COMMANDS | {"flags", "hello"}


def posted_commands(html: str) -> set:
    a = set(re.findall(r"\bsend\(\s*'([A-Za-z]+)'", html))
    b = set(re.findall(r"\bsendPane\(\s*[^,()]+,\s*'([A-Za-z]+)'", html))
    return a | b


def lib_flags():
    """[(key, group, name, where)] in the order declared in lib.js."""
    block = LIB[LIB.index("var FLAGS = ["):LIB.index("var FLAG_KEYS")]
    return re.findall(
        r"\{\s*key:\s*'([^']+)',\s*group:\s*'([^']+)',\s*name:\s*'([^']+)',\s*where:\s*'([^']+)'\s*\}",
        block,
    )


def protocol_flags():
    section = PROTOCOL[PROTOCOL.index("## 4."):PROTOCOL.index("## 5.")]
    return re.findall(
        r"^\|\s*`(ai\.[a-z0-9_.]+)`\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*([^|]+?)\s*\|\s*$",
        section,
        re.M,
    )


def protocol_metric_keys():
    section = PROTOCOL[PROTOCOL.index("## 2."):PROTOCOL.index("## 3.")]
    block = section[section.index("```json"):]
    block = block[: block.index("```", 8)]
    # plain identifiers only: flag keys contain dots, "..." is an ellipsis
    return set(re.findall(r'"([A-Za-z][A-Za-z0-9]*)"\s*:', block))


def lib_metric_fields():
    block = LIB[LIB.index("var METRIC_FIELDS"):LIB.index("var MAX_TURNS")]
    groups = {}
    for name, body in re.findall(r"(\w+):\s*\[([^\]]*)\]", block):
        groups[name] = set(re.findall(r"'([^']+)'", body))
    return groups


class ControllerContract(unittest.TestCase):
    # ---------------------------------------------------------------- commands
    def test_controller_posts_exactly_the_protocol_commands(self):
        self.assertEqual(posted_commands(INDEX), PROTOCOL_COMMANDS)

    def test_protocol_doc_lists_the_same_commands(self):
        section = PROTOCOL[PROTOCOL.index("## 1."):PROTOCOL.index("## 2.")]
        documented = set(re.findall(r"^\|\s*\**`([A-Za-z]+)`", section, re.M))
        self.assertEqual(documented - {"cmd"}, PROTOCOL_COMMANDS)

    def test_dart_parser_handles_the_original_commands(self):
        handled = set(re.findall(r"case '([A-Za-z]+)':", DART))
        self.assertTrue(OLD_COMMANDS <= handled, handled)

    def test_message_envelope_uses_protocol_version_1(self):
        self.assertRegex(INDEX, r"\{\s*ailab:\s*1\s*,\s*cmd:")
        self.assertRegex(INDEX, r"\{\s*ailab:\s*1\s*,\s*pane:\s*pane\s*,\s*metrics:\s*raw\s*,\s*receivedAt:")

    def test_controller_origin_is_allowed_by_dart(self):
        self.assertIn("http://localhost:8090", DART)

    def test_hello_is_sent_on_load_and_every_5_seconds(self):
        self.assertIn("addEventListener('load'", INDEX)
        self.assertRegex(INDEX, r">=\s*5000")
        self.assertRegex(INDEX, r"function hello\(pane\)\s*\{\s*sendPane\(pane,\s*'hello'\)")

    # ------------------------------------------------------- iframes / origins
    def test_iframe_urls_use_ports_8080_and_8081(self):
        srcs = re.findall(r"<iframe[^>]*\ssrc=\"([^\"]+)\"", INDEX)
        self.assertEqual(srcs, ["http://localhost:8080/", "http://localhost:8081/"])
        origins = re.findall(r"origin:\s*'([^']+)'", INDEX)
        self.assertEqual(origins, ["http://localhost:8080", "http://localhost:8081"])

    def test_iframe_titles(self):
        self.assertIn('title="B0 – GỐC"', INDEX)
        self.assertIn('title="B1 – TỐI ƯU"', INDEX)

    def test_incoming_origin_map_is_only_the_two_app_ports(self):
        block = LIB[LIB.index("var ORIGIN_PANES"):LIB.index("var APP_URLS")]
        mapping = dict(re.findall(r"'(http://[^']+)':\s*'(b[01])'", block))
        self.assertEqual(
            mapping,
            {
                "http://localhost:8080": "b0",
                "http://127.0.0.1:8080": "b0",
                "http://localhost:8081": "b1",
                "http://127.0.0.1:8081": "b1",
            },
        )
        self.assertIn("L.paneFromOrigin(ev.origin)", INDEX)
        self.assertIn("ev.source !== FRAMES[pane].el.contentWindow", INDEX)

    def test_no_other_ports_or_hosts_are_hardcoded(self):
        for name, text in (("index", INDEX), ("metrics", METRICS), ("lib", LIB), ("mock", MOCK)):
            ports = set(re.findall(r"(?:localhost|127\.0\.0\.1):(\d+)", text))
            self.assertLessEqual(ports, {"8080", "8081", "8090"}, name)
            for url in re.findall(r"https?://[^\s'\"<>)]+", text):
                self.assertRegex(url, r"^http://(localhost|127\.0\.0\.1):80(80|81|90)\b", f"{name}: {url}")

    def test_pages_are_offline_only(self):
        for name, text in (("index", INDEX), ("metrics", METRICS)):
            srcs = re.findall(r"<(?:script|link)[^>]+(?:src|href)=\"([^\"]+)\"", text)
            for s in srcs:
                self.assertNotRegex(s, r"^(https?:)?//", f"{name}: external {s}")
            self.assertNotRegex(text, r"\b(fetch|XMLHttpRequest|WebSocket|EventSource)\s*\(")

    # ------------------------------------------------------------ flags table
    def test_lib_flags_match_dart_enum_order_and_keys(self):
        enum_block = FLAGS_DART[FLAGS_DART.index("enum AiOptimizationFlag"):FLAGS_DART.index("const AiOptimizationFlag(")]
        dart_keys = re.findall(r"\w+\('(ai\.[a-z0-9_.]+)'\)", enum_block)
        self.assertEqual(len(dart_keys), 10)
        self.assertEqual([f[0] for f in lib_flags()], dart_keys)

    def test_lib_flags_match_protocol_table(self):
        self.assertEqual(len(protocol_flags()), 10)
        self.assertEqual(lib_flags(), protocol_flags())

    def test_pages_render_flags_from_lib_not_hardcoded(self):
        for name, text in (("index", INDEX), ("metrics", METRICS)):
            self.assertIn("L.FLAGS", text, name)
            self.assertNotRegex(text, r"['\"]ai\.[a-z]+\.[a-z0-9_]+['\"]", name)
        known = {f[0] for f in lib_flags()}
        self.assertFalse(set(re.findall(r"ai\.[a-z]+\.[a-z0-9_]+", MOCK)) - known)

    def test_where_hints_are_machine_or_server(self):
        self.assertEqual({f[3] for f in lib_flags()}, {"máy", "server"})

    def test_bulk_buttons_use_protocol_profiles(self):
        values = set(re.findall(r'class="small bulk-btn" data-pane="b[01]" data-value="([^"]+)"', INDEX))
        self.assertEqual(values, {"b0", "b1"})
        self.assertIn("Tắt hết", INDEX)
        self.assertIn("Bật hết", INDEX)
        self.assertIn("Sao chép cấu hình B1 → B0", INDEX)

    def test_switches_show_reported_state_only(self):
        # the click handler must not flip aria-checked itself
        handler = INDEX[INDEX.index("tbody.addEventListener('click'"):INDEX.index("function renderSwitches")]
        self.assertNotIn("aria-checked", handler.replace("setAttribute('aria-busy'", ""))
        self.assertIn("sendPane(pane, 'flags', change)", handler)

    # ------------------------------------------------------- metrics contract
    def test_lib_metric_fields_are_exactly_the_protocol_fields(self):
        groups = lib_metric_fields()
        union = set().union(*groups.values())
        proto = protocol_metric_keys()
        self.assertEqual(union, proto)
        self.assertEqual(groups["totals"], {"llmCalls", "tokens", "savedLlmCalls", "costUsd", "savedUsd", "savedOcrCalls"})
        self.assertEqual(groups["lastExtract"], {"inputTokens", "thinkingTokens", "outputTokens", "durationMs", "provider"})

    def test_fields_read_by_pages_exist_in_protocol(self):
        g = lib_metric_fields()
        checks = (
            (r"\b(?:m|m0|m1)\.(\w+)", g["top"] | {"calls"}),
            (r"\b(?:tot|totals)\.(\w+)", g["totals"]),
            (r"\bm\.totals\.(\w+)", g["totals"]),
            (r"\bex\.(\w+)", g["lastExtract"]),
            (r"\b(?:t|last)\.(\w+)", g["turn"]),
            (r"\bcall\.(\w+)", g["call"]),
        )
        for name, text in (("index", INDEX), ("metrics", METRICS)):
            for pattern, allowed in checks:
                found = set(re.findall(pattern, text))
                # JS built-ins used on the same names
                found -= {"map", "filter", "slice", "length", "forEach", "reverse"}
                self.assertLessEqual(found, allowed, f"{name}: {pattern} -> {found - allowed}")

    def test_totals_read_via_strings_are_protocol_fields(self):
        keys = set(re.findall(r"(?:tot|totals)\(\s*m[01]?\s*,\s*'(\w+)'\)", METRICS))
        keys |= set(re.findall(r"tot\(m[01],\s*'(\w+)'\)", METRICS))
        self.assertTrue(keys)
        self.assertLessEqual(keys, lib_metric_fields()["totals"])

    def test_mock_snapshot_uses_protocol_fields_only(self):
        block = MOCK[MOCK.index("function snapshot"):MOCK.index("/** Mimics")]
        used = set(re.findall(r"\b([A-Za-z]+):\s", block))
        allowed = protocol_metric_keys() | {"b0", "b1"}
        self.assertLessEqual(used, allowed, used - allowed)

    def test_events_are_metrics_with_protocol_version(self):
        self.assertIn("data.ailab === 1 && data.event === 'metrics'", LIB)
        self.assertIn("MAX_TURNS = 20", LIB)
        self.assertIn("MAX_CALLS = 30", LIB)

    # ----------------------------------------------------- channel / metrics page
    def test_channel_name_matches_protocol(self):
        self.assertIn('BroadcastChannel("finmi-ailab")', PROTOCOL)
        self.assertIn("CHANNEL_NAME = 'finmi-ailab'", LIB)
        self.assertIn("new BroadcastChannel(L.CHANNEL_NAME)", INDEX)
        self.assertIn("new BroadcastChannel(L.CHANNEL_NAME)", METRICS)

    def test_controller_answers_snapshot_requests(self):
        self.assertIn("d.request === 'snapshot'", INDEX)

    def test_metrics_page_is_read_only(self):
        self.assertNotIn("cmd", METRICS)
        self.assertNotIn("contentWindow", METRICS)
        self.assertNotIn("<iframe", METRICS)
        self.assertNotRegex(METRICS, r"window\.(?:parent|top|opener)")
        for call in re.findall(r"(\w+)\.postMessage\(", METRICS):
            self.assertEqual(call, "channel")
        posts = re.findall(r"channel\.postMessage\(([^;]*)\)", METRICS)
        self.assertEqual(posts, ["{ ailab: 1, request: 'snapshot' }"])
        self.assertNotIn("sendPane", METRICS)

    def test_metrics_page_requests_snapshot_on_open(self):
        self.assertRegex(METRICS, r"function openChannel\(\)[\s\S]{0,700}?requestSnapshot\(\)")

    def test_controller_links_to_metrics_page(self):
        self.assertRegex(INDEX, r'<a[^>]+href="metrics\.html"[^>]+target="finmi-metrics"')
        self.assertIn("Mở trang số liệu", INDEX)
        self.assertTrue((HERE / "metrics.html").exists())

    # ------------------------------------------------------------------- mock
    def test_mock_is_gated_by_query_parameter(self):
        for name, text in (("index", INDEX), ("metrics", METRICS)):
            self.assertNotRegex(text, r"<script[^>]+src=\"mock\.js\"", name)
            self.assertRegex(text, r"/\[\?&\]mock=1\(&\|\$\)/\.test\(location\.search\)", name)
            self.assertIn("s.src = 'mock.js'", text)
            # the loader sits inside startMock(), only called from the gated branch
            self.assertEqual(len(re.findall(r"startMock\(\)", text)), 2, name)
        self.assertIn("DỮ LIỆU GIẢ LẬP – CHỈ ĐỂ THỬ GIAO DIỆN", MOCK)
        self.assertIn("showBanner()", INDEX)
        self.assertIn("showBanner()", METRICS)

    def test_mock_mode_never_relays_to_the_real_channel(self):
        self.assertIn("if (mock || typeof BroadcastChannel === 'undefined') return;", INDEX)
        self.assertIn("if (!channel) return;", INDEX)

    # ------------------------------------------------------------ misc content
    def test_vietnamese_ui_strings(self):
        for s in ("LỆCH CỜ", "Tắt hết", "Bật hết", "Reset", "Gửi cho", "Cả hai", "Chỉ B0", "Chỉ B1",
                  "Lỗi giả lập", "Bóp méo tổng hóa đơn (lỗi mô phỏng)", "Hóa đơn mẫu 1", "Hóa đơn mẫu 2"):
            self.assertIn(s, INDEX)
        for s in ("Chưa nhận dữ liệu từ", "B1 so với B0", "Ảnh trùng chặn được"):
            self.assertIn(s, METRICS)
        self.assertIn("lang=\"vi\"", INDEX)
        self.assertIn("lang=\"vi\"", METRICS)

    def test_accessibility_and_theming_hooks(self):
        self.assertIn('role="status" aria-live="polite"', INDEX)
        self.assertIn("role=\"switch\"", INDEX.replace("'role', 'switch'", 'role="switch"'))
        self.assertIn("prefers-color-scheme: dark", CSS)
        self.assertIn("focus-visible", CSS)
        for text in (INDEX, METRICS):
            self.assertIn('rel="stylesheet" href="theme.css"', text)

    def test_preset_questions_and_assets(self):
        for q in (
            "Tháng này tôi chi bao nhiêu?",
            "Tại sao tháng này tôi chi nhiều?",
            "Hôm nay ăn trưa hết 35k",
        ):
            self.assertIn(f'data-question="{q}"', INDEX)
        for a in ("receipt_normal.png", "receipt_repeat.png"):
            self.assertIn(f'data-asset="assets/ai_lab/{a}"', INDEX)

    def test_asset_values_pass_the_dart_prefix_rule(self):
        for a in re.findall(r'data-asset="([^"]+)"', INDEX):
            self.assertTrue(a.startswith("assets/ai_lab/"))
            self.assertNotIn("..", a)
            self.assertNotIn("\\", a)

    def test_fault_values_are_allowed_by_dart(self):
        values = set(re.findall(r'name="fault" value="([^"]*)"', INDEX))
        self.assertEqual(values, {"", "429", "500", "timeout"})
        self.assertIn("{'429', '500', 'timeout'}", DART)

    def test_questions_fit_the_dart_length_limit(self):
        for q in re.findall(r'data-question="([^"]+)"', INDEX):
            self.assertLessEqual(len(q), 500)

    # --------------------------------------------------------------- launchers
    def test_launchers_serve_controller_on_8090_and_print_metrics_url(self):
        for name, text in (("ps1", PS1), ("bat", BAT)):
            self.assertIn("http.server", text, name)
            self.assertIn("8090", text, name)
            self.assertIn("demo", text, name)
            self.assertIn("http://localhost:8090/", text, name)
            self.assertIn("http://localhost:8090/metrics.html", text, name)
        self.assertIn("[switch]$Metrics", PS1)
        self.assertIn('"%~1"=="metrics"', BAT)

    def test_package_scripts(self):
        scripts = PACKAGE["scripts"]
        self.assertIn("8090", scripts["start-controller"])
        self.assertIn("tool/demo/controller", scripts["start-controller"])
        self.assertIn("http://localhost:8090/metrics.html", scripts["start-metrics"])
        self.assertIn("lib.test.js", scripts["test-demo-web"])

    @unittest.skipUnless(shutil.which("powershell"), "powershell not available")
    def test_ps1_parses(self):
        cmd = "[scriptblock]::Create((Get-Content -Raw '%s')) | Out-Null" % (ROOT / "tool" / "run_dual_instances.ps1")
        r = subprocess.run(["powershell", "-NoProfile", "-Command", cmd], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)


if __name__ == "__main__":
    unittest.main()
