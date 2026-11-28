"""Generate the two synthetic sample receipts used by the AI Lab demo.

Usage: python tool/ai_lab/make_sample_receipts.py

Writes assets/ai_lab/receipt_normal.png and assets/ai_lab/receipt_repeat.png.
Everything on them is invented (no personal data) and the arithmetic is exact:
line amount = qty x price, subtotal = sum of lines, VAT 8% and total add up.
"""
from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 900, 1400
MARGIN = 60
ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "assets" / "ai_lab"

FONT_CANDIDATES = [
    ("C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/arialbd.ttf"),
    ("C:/Windows/Fonts/segoeui.ttf", "C:/Windows/Fonts/segoeuib.ttf"),
    (
        str(ROOT / "assets" / "fonts" / "BeVietnamPro-400.ttf"),
        str(ROOT / "assets" / "fonts" / "BeVietnamPro-700.ttf"),
    ),
    (
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    ),
]


def load_fonts() -> tuple[str, str]:
    for regular, bold in FONT_CANDIDATES:
        if os.path.exists(regular) and os.path.exists(bold):
            return regular, bold
    sys.exit("Không tìm thấy font có dấu tiếng Việt.")


@dataclass(frozen=True)
class Item:
    name: str
    qty: int
    price: int

    @property
    def amount(self) -> int:
        return self.qty * self.price


@dataclass(frozen=True)
class Receipt:
    filename: str
    store: str
    address: str
    phone: str
    date: str
    number: str
    cashier: str
    items: list[Item]


RECEIPTS = [
    Receipt(
        filename="receipt_normal.png",
        store="SIÊU THỊ MINI AN BÌNH",
        address="12 Đường Lê Lợi, Quận 1, TP. Hồ Chí Minh",
        phone="028 3822 0000",
        date="25/11/2026 18:42",
        number="HD-004217",
        cashier="Thu ngân: Quầy 02",
        items=[
            Item("Sữa tươi không đường 1L", 2, 32000),
            Item("Trứng gà (vỉ 10 quả)", 1, 38000),
            Item("Gạo thơm ST25 (túi 5kg)", 1, 125000),
            Item("Dầu ăn đậu nành 1L", 1, 52000),
            Item("Mì gói hảo hảo", 3, 4500),
            Item("Nước rửa chén 750ml", 1, 28000),
        ],
    ),
    Receipt(
        filename="receipt_repeat.png",
        store="CỬA HÀNG TIỆN LỢI HOA MAI",
        address="45 Phố Trần Hưng Đạo, Quận Hoàn Kiếm, Hà Nội",
        phone="024 3933 1111",
        date="26/11/2026 09:15",
        number="HM-018830",
        cashier="Thu ngân: Quầy 01",
        items=[
            Item("Cà phê hòa tan hộp 20 gói", 1, 85000),
            Item("Bánh quy bơ 200g", 2, 24500),
            Item("Nước suối 500ml", 6, 6000),
            Item("Sữa chua uống men sống", 4, 8500),
            Item("Kẹo cao su bạc hà", 2, 12000),
            Item("Khăn giấy rút (gói lớn)", 1, 45000),
            Item("Túi đựng hàng", 1, 1000),
        ],
    ),
]


def money(value: int) -> str:
    return f"{value:,}".replace(",", ".")


def totals(receipt: Receipt) -> tuple[int, int, int]:
    subtotal = sum(item.amount for item in receipt.items)
    assert subtotal * 8 % 100 == 0, "VAT 8% must be a whole number of đồng"
    vat = subtotal * 8 // 100
    return subtotal, vat, subtotal + vat


def render(receipt: Receipt, regular: str, bold: str) -> Image.Image:
    image = Image.new("L", (WIDTH, HEIGHT), 255)
    draw = ImageDraw.Draw(image)
    f = lambda path, size: ImageFont.truetype(path, size)  # noqa: E731
    title, body, small, big = f(bold, 40), f(regular, 26), f(regular, 24), f(bold, 36)
    body_bold = f(bold, 26)

    right = WIDTH - MARGIN
    y = 60

    def centered(text: str, font: ImageFont.FreeTypeFont, gap: int) -> None:
        nonlocal y
        width = draw.textlength(text, font=font)
        assert width <= WIDTH - 2 * MARGIN, f"quá rộng: {text}"
        draw.text(((WIDTH - width) / 2, y), text, font=font, fill=0)
        y += gap

    def rule(char_gap: int = 10) -> None:
        nonlocal y
        x = MARGIN
        while x < right:
            draw.line([(x, y), (min(x + 14, right), y)], fill=0, width=2)
            x += 24
        y += char_gap + 14

    def row(left: str, value: str, font: ImageFont.FreeTypeFont, gap: int = 44) -> None:
        nonlocal y
        draw.text((MARGIN, y), left, font=font, fill=0)
        draw.text((right - draw.textlength(value, font=font), y), value, font=font, fill=0)
        y += gap

    centered(receipt.store, title, 56)
    centered(receipt.address, small, 36)
    centered(f"Điện thoại: {receipt.phone}", small, 60)
    centered("HÓA ĐƠN BÁN HÀNG", big, 60)
    row("Số:", receipt.number, body, 40)
    row("Ngày:", receipt.date, body, 40)
    draw.text((MARGIN, y), receipt.cashier, font=body, fill=0)
    y += 50
    rule()

    # Column anchors (right-aligned numbers). The item name gets one line.
    qty_right, price_right, amount_right = 500, 665, right
    name_max = qty_right - 60 - MARGIN
    draw.text((MARGIN, y), "Tên hàng", font=body_bold, fill=0)
    for label, anchor in (("SL", qty_right), ("Đơn giá", price_right), ("Thành tiền", amount_right)):
        draw.text((anchor - draw.textlength(label, font=body_bold), y), label, font=body_bold, fill=0)
    y += 44
    rule(4)

    for item in receipt.items:
        assert draw.textlength(item.name, font=body) <= name_max, f"tên quá dài: {item.name}"
        draw.text((MARGIN, y), item.name, font=body, fill=0)
        for value, anchor in (
            (str(item.qty), qty_right),
            (money(item.price), price_right),
            (money(item.amount), amount_right),
        ):
            draw.text((anchor - draw.textlength(value, font=body), y), value, font=body, fill=0)
        y += 58
    rule()

    subtotal, vat, total = totals(receipt)
    row("Cộng tiền hàng", money(subtotal), body)
    row("Thuế GTGT (8%)", money(vat), body, 56)
    rule(2)
    row("TỔNG THANH TOÁN", money(total), big, 62)
    row("Tiền mặt", money(total), body, 44)
    y += 20
    rule()
    centered("Cảm ơn quý khách. Hẹn gặp lại!", body, 40)
    centered("Hàng đã mua vui lòng giữ hóa đơn khi đổi trả", small, 40)
    assert y < HEIGHT - 40, f"nội dung tràn khung: y={y}"
    return image


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    regular, bold = load_fonts()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for receipt in RECEIPTS:
        path = OUT_DIR / receipt.filename
        render(receipt, regular, bold).save(path, optimize=True)
        subtotal, vat, total = totals(receipt)
        print(f"{path.name}: tạm tính {money(subtotal)}, VAT {money(vat)}, tổng {money(total)}")


if __name__ == "__main__":
    main()
