"""
把 v6 图缩到 90% 并居中放到原画布大小（1024×1024），四角留透明 padding，
作为 Android 12 240dp 圆形 viewport 的安全边。

同时输出一个 _preview.png：把 1024×1024 画布放进一个 1080×1920 黑底"手机
预览"，再用 240dp（=720px @ 3x）圆形 viewport mask 切出实际启动页观感。
此文件仅供本地/视觉验证用，不入版本。

用法：
    python scripts/make_splash_asset.py
"""
import math
import sys
from pathlib import Path

import png

SRC = Path("docs/design/assets/xiahub-icon-v6.png")
DST = Path("docs/design/assets/xiahub-icon-v6-splash.png")
PREVIEW = Path("docs/design/assets/xiahub-icon-v6-splash_preview.png")
SCALE = 0.9  # 留 5% × 2 = 10% 总边距
VIEWPORT_PX = 720  # 240dp × 3 = 720px @ xxhdpi，等价于 Android 12 viewport


def bilinear_resize(
    src: bytes, src_w: int, src_h: int, dst_w: int, dst_h: int, channels: int
) -> bytearray:
    """双线性插值缩放。要求 channels ∈ {3, 4}。"""
    dst = bytearray(dst_w * dst_h * channels)
    for y in range(dst_h):
        sy = (y + 0.5) * (src_h / dst_h) - 0.5
        y0 = max(0, int(math.floor(sy)))
        y1 = min(src_h - 1, y0 + 1)
        dy = max(0.0, sy - y0)

        for x in range(dst_w):
            sx = (x + 0.5) * (src_w / dst_w) - 0.5
            x0 = max(0, int(math.floor(sx)))
            x1 = min(src_w - 1, x0 + 1)
            dx = max(0.0, sx - x0)

            src_y0 = y0 * src_w
            src_y1 = y1 * src_w
            dst_y = y * dst_w + x

            for c in range(channels):
                tl = src[(src_y0 + x0) * channels + c]
                tr = src[(src_y0 + x1) * channels + c]
                bl = src[(src_y1 + x0) * channels + c]
                br = src[(src_y1 + x1) * channels + c]
                top = tl * (1 - dx) + tr * dx
                bot = bl * (1 - dx) + br * dx
                val = top * (1 - dy) + bot * dy
                dst[dst_y * channels + c] = int(round(val))
    return dst


def pad_center(
    img: bytes, img_w: int, img_h: int, canvas_w: int, canvas_h: int, channels: int
) -> bytearray:
    """把 img 居中放到 canvas 上，四边空白填透明 (alpha=0)。"""
    canvas = bytearray(canvas_w * canvas_h * channels)
    x_off = (canvas_w - img_w) // 2
    y_off = (canvas_h - img_h) // 2
    row_bytes = img_w * channels
    for y in range(img_h):
        src_start = y * row_bytes
        dst_start = ((y + y_off) * canvas_w + x_off) * channels
        canvas[dst_start : dst_start + row_bytes] = img[src_start : src_start + row_bytes]
    return canvas


def main() -> int:
    if not SRC.exists():
        print(f"ERROR: {SRC} not found", file=sys.stderr)
        return 1

    reader = png.Reader(filename=str(SRC))
    w, h, pixels, meta = reader.read()
    if w != h:
        print(f"ERROR: {SRC} is {w}x{h}, expected square", file=sys.stderr)
        return 1

    # 拍平行为字节流
    flat_src = bytearray()
    for row in pixels:
        flat_src.extend(row)

    src_w = src_h = w
    new_size = round(src_w * SCALE)
    print(f"src={src_w}x{src_h}  scale={SCALE}  new={new_size}  padding=({src_w - new_size})/2 each side")

    # 取 channels
    if "alpha" in meta:
        channels = 4 if meta["alpha"] else 3
    elif "greyscale" in meta and meta["greyscale"]:
        channels = 2 if "alpha" in meta else 1
    else:
        channels = 4 if "alpha" in meta else 3
    print(f"channels={channels}")

    resized = bilinear_resize(flat_src, src_w, src_h, new_size, new_size, channels)
    padded = pad_center(resized, new_size, new_size, src_w, src_h, channels)

    # 写 PNG（保持 alpha 通道）。
    # pypng 坑：`alpha=True` 不显式 `greyscale=False` 会默认按灰度+alpha
    # 走（2 通道），width*2 values/row → ProtocolError。所以 RGB/RGBA 都
    # 显式 `greyscale=False`。
    if channels == 4:
        writer = png.Writer(
            width=src_w,
            height=src_h,
            greyscale=False,
            alpha=True,
            bitdepth=8,
        )
    elif channels == 2:
        writer = png.Writer(
            width=src_w,
            height=src_h,
            greyscale=True,
            alpha=True,
            bitdepth=8,
        )
    elif channels == 3:
        writer = png.Writer(
            width=src_w, height=src_h, greyscale=False, bitdepth=8
        )
    else:  # channels == 1
        writer = png.Writer(
            width=src_w, height=src_h, greyscale=True, bitdepth=8
        )

    # PyPNG 写需要按行迭代
    row_bytes = src_w * channels
    with open(DST, "wb") as f:
        def rows():
            for y in range(src_h):
                yield padded[y * row_bytes : (y + 1) * row_bytes]

        writer.write(f, rows())

    print(f"OK: wrote {DST} ({DST.stat().st_size} bytes)")

    # 生成 viewport 预览：把 1024×1024 居中放进 VIEWPORT_PX×VIEWPORT_PX 画布，
    # 画布外填背景色（#FDD3BC peach，与 native splash 背景一致），外面再画
    # 圆形 viewport 边界，给视觉参考。
    preview_w = VIEWPORT_PX
    preview_h = VIEWPORT_PX
    bg_color = (0xFD, 0xD3, 0xBC, 0xFF)
    preview = bytearray(bg_color * preview_w * preview_h)

    # 把 padded (1024×1024 RGBA) 按比例放到 preview 中央。
    # 让 1024 占满 viewport 宽度（720px），即缩放系数 720/1024 ≈ 0.703。
    # 在画布上 1024 实际渲染 = 720 像素，圆形 viewport (720 半径 360) 内切。
    scale_to_viewport = VIEWPORT_PX / src_w  # 720/1024
    render_w = int(src_w * scale_to_viewport)
    render_h = int(src_h * scale_to_viewport)
    resized_for_preview = bilinear_resize(
        padded, src_w, src_h, render_w, render_h, channels
    )
    # 居中放
    x_off = (preview_w - render_w) // 2
    y_off = (preview_h - render_h) // 2
    render_row_bytes = render_w * channels
    for y in range(render_h):
        src_start = y * render_row_bytes
        dst_start = ((y + y_off) * preview_w + x_off) * channels
        preview[dst_start : dst_start + render_row_bytes] = resized_for_preview[
            src_start : src_start + render_row_bytes
        ]

    # 写 preview
    if channels == 4:
        pvw = png.Writer(
            width=preview_w,
            height=preview_h,
            greyscale=False,
            alpha=True,
            bitdepth=8,
        )
    else:
        pvw = png.Writer(width=preview_w, height=preview_h, bitdepth=8)
    pvw_row_bytes = preview_w * channels
    with open(PREVIEW, "wb") as f:
        def pvw_rows():
            for y in range(preview_h):
                yield preview[y * pvw_row_bytes : (y + 1) * pvw_row_bytes]

        pvw.write(f, pvw_rows())
    print(f"OK: wrote {PREVIEW} ({PREVIEW.stat().st_size} bytes) — preview, NOT shipped")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())