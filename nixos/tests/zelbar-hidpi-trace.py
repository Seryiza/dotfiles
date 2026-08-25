#!/usr/bin/env python3
"""Assert Zelbar's Wayland trace keeps logical and physical scale in sync."""

from __future__ import annotations

import re
import sys
from pathlib import Path

from PIL import Image, ImageChops


CONFIGURE = re.compile(r"zwlr_layer_surface_v1#\d+\.configure\(\d+, (\d+), (\d+)\)")
BACKGROUND = (0x11, 0x22, 0x33, 0xFF)
BORDER = (0xFF, 0x00, 0x00, 0xFF)


def find_line(lines: list[str], pattern: re.Pattern[str], start: int = 0) -> tuple[int, re.Match[str]]:
    for index in range(start, len(lines)):
        match = pattern.search(lines[index])
        if match:
            return index, match
    raise AssertionError(f"missing trace pattern after line {start}: {pattern.pattern}")


def assert_transaction(
    lines: list[str], start: int, scale: int, width: int, height: int
) -> int:
    create_pattern = re.compile(
        rf"wl_shm_pool#\d+\.create_buffer\(new id wl_buffer#(\d+), 0, {width}, {height}, {width * 4}, 0\)"
    )
    create_index, create = find_line(lines, create_pattern, start)
    buffer_id = create.group(1)
    set_index, _ = find_line(
        lines, re.compile(rf"wl_surface#\d+\.set_buffer_scale\({scale}\)"), create_index + 1
    )
    attach_index, _ = find_line(
        lines,
        re.compile(rf"wl_surface#\d+\.attach\(wl_buffer#{buffer_id}, 0, 0\)"),
        set_index + 1,
    )
    damage_index, _ = find_line(
        lines,
        re.compile(rf"wl_surface#\d+\.damage_buffer\(0, 0, {width}, {height}\)"),
        attach_index + 1,
    )
    commit_index, _ = find_line(
        lines, re.compile(r"wl_surface#\d+\.commit\(\)"), damage_index + 1
    )
    return commit_index


def assert_logical_height(lines: list[str]) -> list[tuple[int, int]]:
    sizes = [(int(match.group(1)), int(match.group(2))) for line in lines if (match := CONFIGURE.search(line))]
    if not sizes:
        raise AssertionError("trace has no layer-surface configure")
    if any(height != 20 for _, height in sizes):
        raise AssertionError(f"layer geometry stopped being 20 logical pixels: {sizes}")
    return sizes


def inspect_pixels(path: str, scale: int) -> tuple[Image.Image, int]:
    image = Image.open(path).convert("RGBA")
    if image.size != (800, 600):
        raise AssertionError(f"unexpected screenshot dimensions for {path}: {image.size}")

    bar_height = 20 * scale
    sample_x = 200
    for y in range(scale):
        if image.getpixel((sample_x, y)) != BORDER:
            raise AssertionError(f"top border is not {scale} physical pixels in {path}")
    if image.getpixel((sample_x, scale + 1)) != BACKGROUND:
        raise AssertionError(f"bar background is not rendered at scale {scale} in {path}")
    for y in range(bar_height - scale, bar_height):
        if image.getpixel((sample_x, y)) != BORDER:
            raise AssertionError(f"bottom border is not {scale} physical pixels in {path}")

    text_pixels = []
    for y in range(scale, bar_height - scale):
        for x in range(0, 120):
            red, green, blue, _ = image.getpixel((x, y))
            if red + green + blue > 600:
                text_pixels.append((x, y))
    if not text_pixels:
        raise AssertionError(f"no foreground glyph pixels found in {path}")
    glyph_height = max(y for _, y in text_pixels) - min(y for _, y in text_pixels) + 1
    return image, glyph_height


def assert_pixel_scaling(paths: list[str]) -> None:
    before, scale2, after = paths
    image1_before, glyph1_before = inspect_pixels(before, 1)
    _, glyph2 = inspect_pixels(scale2, 2)
    image1_after, glyph1_after = inspect_pixels(after, 1)

    if not (glyph1_before * 1.6 <= glyph2 <= glyph1_before * 2.4):
        raise AssertionError(
            f"glyph raster height did not scale physically: {glyph1_before} -> {glyph2}"
        )
    if glyph1_before != glyph1_after:
        raise AssertionError(
            f"scale 2->1 retained stale glyph metrics: {glyph1_before} -> {glyph1_after}"
        )
    before_bar = image1_before.crop((0, 0, 800, 20))
    after_bar = image1_after.crop((0, 0, 800, 20))
    if ImageChops.difference(before_bar, after_bar).getbbox() is not None:
        raise AssertionError("scale 1 bar pixels changed after a 1->2->1 transition")
    print(
        "PASS pixels: border/background 1x->2x->1x; "
        f"glyph height {glyph1_before}->{glyph2}->{glyph1_after}"
    )


def main() -> None:
    mode = sys.argv[1]
    if mode == "pixels":
        assert_pixel_scaling(sys.argv[2:])
        return

    trace_path = sys.argv[2]
    lines = Path(trace_path).read_text().splitlines()
    sizes = assert_logical_height(lines)

    if mode == "initial-1":
        if (800, 20) not in sizes:
            raise AssertionError(f"missing 800x20 logical configure: {sizes}")
        assert_transaction(lines, 0, 1, 800, 20)
    elif mode == "initial-2":
        if (400, 20) not in sizes:
            raise AssertionError(f"missing 400x20 logical configure: {sizes}")
        assert_transaction(lines, 0, 2, 800, 40)
    elif mode == "transition":
        scale2_index, _ = find_line(lines, re.compile(r"wl_output#\d+\.scale\(2\)"))
        scale2_commit = assert_transaction(lines, scale2_index + 1, 2, 800, 40)
        scale1_index, _ = find_line(
            lines, re.compile(r"wl_output#\d+\.scale\(1\)"), scale2_commit + 1
        )
        assert_transaction(lines, scale1_index + 1, 1, 800, 20)
        if (400, 20) not in sizes or (800, 20) not in sizes:
            raise AssertionError(f"missing transition logical configures: {sizes}")
    else:
        raise AssertionError(f"unknown mode: {mode}")

    print(f"PASS {mode}: logical configures={sizes}")


if __name__ == "__main__":
    main()
