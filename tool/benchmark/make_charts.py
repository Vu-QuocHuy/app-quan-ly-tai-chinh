"""Vẽ biểu đồ cho báo cáo/slide tối ưu AI (T3.7). Nhãn tiếng Việt, font DejaVu Sans.

Hàm vẽ trả về Figure và lưu PNG vào out_path.
  plot_token_stack(out)            cột chồng token B0 vs B1 (số của TV1, 30 ảnh)
  plot_latency_box(b0, b1, out)    box plot độ trễ (ms) + vạch timeout; cần dữ liệu thô
  plot_chat_calls(summary, out)    M6 theo profile, từ summarize_chat.summarize
  plot_chat_flow(out)              sơ đồ thiết kế luồng chat (không phải số đo)

CLI (khi TV1 cung cấp độ trễ từng ảnh, JSON mảng số ms):
  python make_charts.py --latency-b0 b0.json --latency-b1 b1.json [--out latency_box_b0_b1.png]
  python make_charts.py --all-static [--out-dir ../../docs/ai-optimization/figures]
"""

import argparse
import json
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.patches import FancyBboxPatch  # noqa: E402

plt.rcParams["font.family"] = "DejaVu Sans"
plt.rcParams["axes.unicode_minus"] = True

COLOR_B0 = "#C0392B"
COLOR_B1 = "#1F7A4D"
COLOR_INPUT = "#9DB4C7"
COLOR_THINK = "#E8A33D"
COLOR_OUTPUT = "#2F6F9F"
COLOR_TEXT = "#222222"

# Số liệu TV1: "Tổng hợp cuối cùng — 30/30 ảnh" (docs/TV1_OPTIMIZATION_REPORT.md).
# input = tổng − thinking − output.
TOKENS_B0 = {"input": 3305 - 1025 - 186, "thinking": 1025, "output": 186}
TOKENS_B1 = {"input": 2286 - 0 - 191, "thinking": 0, "output": 191}


def _vi(value: float, digits: int = 1) -> str:
    return f"{value:.{digits}f}".replace(".", ",")


def _thousands(value: float) -> str:
    return f"{value:,.0f}".replace(",", ".")


def _save(fig, out_path) -> None:
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150, bbox_inches="tight", facecolor="white")


def plot_token_stack(out_path):
    fig, ax = plt.subplots(figsize=(8, 6.5))
    labels = ["B0 – GỐC", "B1 – TỐI ƯU"]
    data = (TOKENS_B0, TOKENS_B1)
    parts = (
        ("input", "đầu vào", COLOR_INPUT),
        ("thinking", "suy luận", COLOR_THINK),
        ("output", "đầu ra", COLOR_OUTPUT),
    )
    bottoms = [0, 0]
    for key, name, color in parts:
        values = [d[key] for d in data]
        ax.bar(labels, values, bottom=bottoms, color=color, width=0.5,
               label=f"Token {name}")
        for i, v in enumerate(values):
            if v >= 300:  # đoạn đủ dày thì ghi trong cột
                ax.text(i, bottoms[i] + v / 2, f"{name} {_thousands(v)}", ha="center",
                        va="center", fontsize=10, color=COLOR_TEXT)
            elif v > 0:  # đoạn mỏng thì ghi bên phải cột
                ax.text(i + 0.28, bottoms[i] + v / 2, f"{name} {_thousands(v)}", ha="left",
                        va="center", fontsize=10, color=COLOR_TEXT)
        bottoms = [b + v for b, v in zip(bottoms, values)]
    ax.text(1.28, 1000, "suy luận 0", ha="left", va="center", fontsize=10, color="#9A5B00",
            fontweight="bold")
    for i, total in enumerate(bottoms):
        ax.text(i, total + 70, f"Tổng {_thousands(total)}", ha="center", fontsize=12,
                fontweight="bold")
    ax.annotate("−30,8% tổng token", xy=(1, bottoms[1] + 420), xytext=(0.5, bottoms[0] + 420),
                ha="center", va="center", fontsize=13, fontweight="bold", color=COLOR_B1,
                arrowprops=dict(arrowstyle="->", color=COLOR_B1, lw=2))
    ax.set_ylim(0, bottoms[0] + 800)
    ax.set_xlim(-0.6, 1.9)
    ax.set_ylabel("Token trung bình mỗi hóa đơn")
    ax.set_title("Cơ cấu token OCR hóa đơn: B0 so với B1\n"
                 "(trung bình 30 ảnh hóa đơn, nguồn: báo cáo TV1)", fontsize=12)
    ax.legend(loc="upper right", frameon=False)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    _save(fig, out_path)
    return fig


def plot_latency_box(b0_ms, b1_ms, out_path, timeout_ms=30000):
    b0, b1 = list(b0_ms), list(b1_ms)
    if not b0 or not b1:
        raise ValueError("danh sách độ trễ B0/B1 không được rỗng")
    fig, ax = plt.subplots(figsize=(7, 6))
    box = ax.boxplot([b0, b1], tick_labels=["B0 – GỐC", "B1 – TỐI ƯU"], patch_artist=True,
                     widths=0.5, medianprops=dict(color="black", lw=2))
    for patch, color in zip(box["boxes"], (COLOR_B0, COLOR_B1)):
        patch.set_facecolor(color)
        patch.set_alpha(0.55)
    ax.axhline(timeout_ms, color="red", lw=2, linestyle="--")
    ax.text(0.55, timeout_ms, f" Timeout {_vi(timeout_ms / 1000, 0)} s", color="red",
            ha="left", va="bottom", fontsize=11, fontweight="bold")
    ax.set_ylim(0, max(max(b0), max(b1), timeout_ms) * 1.1)
    ax.set_ylabel("Độ trễ API mỗi hóa đơn (ms)")
    ax.set_title(f"Độ trễ OCR: B0 so với B1 (n = {len(b0)} / {len(b1)} ảnh)", fontsize=12)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    _save(fig, out_path)
    return fig


def plot_chat_calls(summary, out_path):
    if not summary:
        raise ValueError("summary rỗng")
    profiles = list(summary)
    values = [summary[p]["m6_avg_llm_calls"] or 0 for p in profiles]
    fig, ax = plt.subplots(figsize=(max(6, 1.8 * len(profiles) + 2), 5.5))
    bars = ax.bar(profiles, values, color=COLOR_OUTPUT, width=0.55)
    for bar, v in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, v, _vi(v, 2), ha="center", va="bottom",
                fontsize=11, fontweight="bold")
    ax.set_ylim(0, max(values + [1]) * 1.2)
    ax.set_xlabel("Cấu hình cờ")
    ax.set_ylabel("Số lượt gọi LLM trung bình mỗi câu hỏi (M6)")
    ax.set_title("Số lượt gọi LLM mỗi câu hỏi chat theo cấu hình cờ", fontsize=12)
    ax.spines[["top", "right"]].set_visible(False)
    fig.tight_layout()
    _save(fig, out_path)
    return fig


def _box(ax, x, y, w, h, text, color="#F4F6F8", edge="#555555", fontsize=10):
    ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.02,rounding_size=0.15",
                                fc=color, ec=edge, lw=1.5))
    ax.text(x + w / 2, y + h / 2, text, ha="center", va="center", fontsize=fontsize,
            color=COLOR_TEXT)


def _arrow(ax, x0, y0, x1, y1, color="#555555"):
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0),
                arrowprops=dict(arrowstyle="->", color=color, lw=1.8))


def plot_chat_flow(out_path):
    fig, ax = plt.subplots(figsize=(12, 7))
    ax.set_xlim(0, 12)
    ax.set_ylim(0, 7)
    ax.axis("off")
    ax.text(6, 6.8, "Luồng xử lý câu hỏi tra cứu trong chat: B0 so với B1", ha="center",
            fontsize=14, fontweight="bold")

    # B0: 3 lượt gọi
    ax.text(0.1, 6.15, "B0 – GỐC: 3 lượt gọi LLM", fontsize=12, fontweight="bold",
            color=COLOR_B0)
    y = 5.2
    _box(ax, 0.1, y - 0.55, 1.5, 1.1, "Người dùng\nhỏi")
    _box(ax, 2.2, y - 0.55, 2.3, 1.1, "Lượt 1\nassistant_command", "#F8DAD6", COLOR_B0)
    _box(ax, 5.0, y - 0.55, 2.4, 1.1, "Lượt 2\nchat (gọi công cụ\ntra SQLite)", "#F8DAD6",
         COLOR_B0)
    _box(ax, 7.9, y - 0.55, 2.2, 1.1, "Lượt 3\nchat (soạn\ncâu trả lời)", "#F8DAD6", COLOR_B0)
    _box(ax, 10.5, y - 0.55, 1.4, 1.1, "Câu trả lời\nhiện ra")
    for a, b in ((1.6, 2.2), (4.5, 5.0), (7.4, 7.9), (10.1, 10.5)):
        _arrow(ax, a, y, b, y)

    ax.plot([0.1, 11.9], [4.1, 4.1], color="#BBBBBB", lw=1, linestyle=":")

    # B1
    ax.text(0.1, 3.8, "B1 – TỐI ƯU: 0 hoặc 1 lượt gọi LLM", fontsize=12, fontweight="bold",
            color=COLOR_B1)

    y1 = 2.55
    ax.text(2.2, y1 + 0.75, "Nhánh A: tra cứu có đáp án sẵn (local_router)", fontsize=9.5,
            color=COLOR_B1)
    _box(ax, 0.1, y1 - 0.5, 1.5, 1.0, "Người dùng\nhỏi")
    _box(ax, 2.2, y1 - 0.5, 3.0, 1.0, "Bộ định tuyến luật +\ntruy vấn SQLite trên máy",
         "#D5EBDD", COLOR_B1)
    _box(ax, 6.0, y1 - 0.5, 1.5, 1.0, "Câu trả lời\nhiện ra")
    _arrow(ax, 1.6, y1, 2.2, y1)
    _arrow(ax, 5.2, y1, 6.0, y1)
    ax.text(8.0, y1, "0 lượt gọi LLM", fontsize=12, fontweight="bold", color=COLOR_B1,
            va="center")

    y2 = 0.95
    ax.text(2.2, y2 + 0.75, "Nhánh B: cần suy luận, gộp lượt (merge_calls)", fontsize=9.5,
            color=COLOR_B1)
    _box(ax, 0.1, y2 - 0.5, 1.5, 1.0, "Người dùng\nhỏi")
    _box(ax, 2.2, y2 - 0.5, 3.0, 1.0, "Dữ liệu cần dùng được\nnạp sẵn vào prompt", "#D5EBDD",
         COLOR_B1)
    _box(ax, 6.0, y2 - 0.5, 1.7, 1.0, "1 lượt chat\n(đám mây)", "#D5EBDD", COLOR_B1)
    _box(ax, 8.2, y2 - 0.5, 1.5, 1.0, "Câu trả lời\nhiện ra")
    _arrow(ax, 1.6, y2, 2.2, y2)
    _arrow(ax, 5.2, y2, 6.0, y2)
    _arrow(ax, 7.7, y2, 8.2, y2)
    ax.text(10.0, y2, "1 lượt gọi LLM", fontsize=12, fontweight="bold", color=COLOR_B1,
            va="center")

    ax.text(6, -0.15, "Hình minh họa luồng gọi: theo thiết kế, chưa phải số đo", ha="center",
            fontsize=11, style="italic", color="#555555")
    fig.tight_layout()
    _save(fig, out_path)
    return fig


def _load_json_list(path: str) -> list[float]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, list):
        raise ValueError(f"{path}: cần một mảng JSON các số (ms)")
    return data


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--latency-b0", help="JSON mảng độ trễ ms của B0")
    parser.add_argument("--latency-b1", help="JSON mảng độ trễ ms của B1")
    parser.add_argument("--out", default="latency_box_b0_b1.png", help="PNG cho box plot")
    parser.add_argument("--all-static", action="store_true",
                        help="vẽ token_stack_b0_b1.png và chat_flow_design.png")
    parser.add_argument("--out-dir", default="figures")
    args = parser.parse_args(argv)
    did = False
    if args.all_static:
        out_dir = Path(args.out_dir)
        plot_token_stack(out_dir / "token_stack_b0_b1.png")
        plot_chat_flow(out_dir / "chat_flow_design.png")
        did = True
    if args.latency_b0 or args.latency_b1:
        if not (args.latency_b0 and args.latency_b1):
            parser.error("cần cả --latency-b0 và --latency-b1")
        plot_latency_box(_load_json_list(args.latency_b0), _load_json_list(args.latency_b1),
                         args.out)
        did = True
    if not did:
        parser.print_help()
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
