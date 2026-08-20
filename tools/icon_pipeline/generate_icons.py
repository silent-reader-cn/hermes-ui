#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Icon generation pipeline for Hermex Flutter client.
Generates all platform icons from a single source: assets/branding/hermes-agent-icon-1024.png
Target platforms: Android, Windows, macOS.
"""

from __future__ import annotations

import os
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, List, Tuple

try:
    from PIL import Image
except ImportError:
    print("[ERROR] Pillow is required. Please run: pip install pillow", file=sys.stderr)
    sys.exit(1)


# Path definitions relative to repository root
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SOURCE_ICON_PATH = REPO_ROOT / "assets" / "branding" / "hermes-agent-icon-1024.png"

# Android destination paths
ANDROID_RES_DIR = REPO_ROOT / "android" / "app" / "src" / "main" / "res"
ANDROID_LEGACY_SIZES: Dict[str, int] = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

# Android adaptive icon configurations
ANDROID_ADAPTIVE_DIR = ANDROID_RES_DIR / "mipmap-anydpi-v26"
ANDROID_DRAWABLE_DIR = ANDROID_RES_DIR / "drawable"
ANDROID_VALUES_DIR = ANDROID_RES_DIR / "values"
ADAPTIVE_CANVAS_SIZE = 432  # xxxhdpi 108dp viewport (108 * 4)
ADAPTIVE_SAFE_RATIO = 72.0 / 108.0  # 66.67% safe zone ratio (72dp inner circle)

# Windows destination paths
WINDOWS_RESOURCES_DIR = REPO_ROOT / "windows" / "runner" / "resources"
WINDOWS_ICO_SIZES: List[Tuple[int, int]] = [
    (16, 16),
    (24, 24),
    (32, 32),
    (48, 48),
    (64, 64),
    (128, 128),
    (256, 256),
]

# macOS destination paths
MACOS_ICONSET_DIR = REPO_ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
MACOS_SIZES: Dict[str, int] = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}


def load_source_image(source_path: Path) -> Image.Image:
    """Load and validate the single source icon."""
    if not source_path.exists():
        raise FileNotFoundError(f"Source icon not found at {source_path}")

    img = Image.open(source_path).convert("RGBA")
    if img.size != (1024, 1024):
        print(f"[WARN] Source image size is {img.size}, expected (1024, 1024)")
    return img


def generate_android_legacy_icons(source_img: Image.Image) -> List[Path]:
    """Generate Android legacy mipmap launcher icons."""
    generated: List[Path] = []
    for dir_name, size in ANDROID_LEGACY_SIZES.items():
        out_dir = ANDROID_RES_DIR / dir_name
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "ic_launcher.png"

        resized = source_img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(out_file, format="PNG", optimize=True)
        generated.append(out_file)
    return generated


def generate_android_adaptive_icons(source_img: Image.Image) -> List[Path]:
    """
    Generate Android adaptive icon resources:
    - values/ic_launcher_background.xml (solid white background #FFFFFF)
    - drawable/ic_launcher_foreground.png (scaled to fit within 72dp safe zone)
    - mipmap-anydpi-v26/ic_launcher.xml (references background and foreground)
    """
    generated: List[Path] = []

    # 1. Background color resource
    ANDROID_VALUES_DIR.mkdir(parents=True, exist_ok=True)
    bg_xml_file = ANDROID_VALUES_DIR / "ic_launcher_background.xml"
    bg_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<resources>\n'
        '    <color name="ic_launcher_background">#FFFFFF</color>\n'
        '</resources>\n'
    )
    bg_xml_file.write_text(bg_xml_content, encoding="utf-8")
    generated.append(bg_xml_file)

    # 2. Foreground drawable (scaled to safe zone)
    ANDROID_DRAWABLE_DIR.mkdir(parents=True, exist_ok=True)
    fg_file = ANDROID_DRAWABLE_DIR / "ic_launcher_foreground.png"

    scaled_dim = int(round(ADAPTIVE_CANVAS_SIZE * ADAPTIVE_SAFE_RATIO))  # 288px
    offset = (ADAPTIVE_CANVAS_SIZE - scaled_dim) // 2  # 72px

    scaled_source = source_img.resize((scaled_dim, scaled_dim), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (ADAPTIVE_CANVAS_SIZE, ADAPTIVE_CANVAS_SIZE), (0, 0, 0, 0))
    canvas.paste(scaled_source, (offset, offset), scaled_source)
    canvas.save(fg_file, format="PNG", optimize=True)
    generated.append(fg_file)

    # 3. Adaptive icon definition XML
    ANDROID_ADAPTIVE_DIR.mkdir(parents=True, exist_ok=True)
    adaptive_xml_file = ANDROID_ADAPTIVE_DIR / "ic_launcher.xml"
    adaptive_xml_content = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground"/>\n'
        '</adaptive-icon>\n'
    )
    adaptive_xml_file.write_text(adaptive_xml_content, encoding="utf-8")
    generated.append(adaptive_xml_file)

    return generated


def generate_windows_icon(source_img: Image.Image) -> List[Path]:
    """
    Generate Windows multi-size .ico icon with sizes 16, 24, 32, 48, 64, 128, 256.
    Ensures small sizes (16, 32) are crisp and opaque for tray / taskbar usage.
    """
    generated: List[Path] = []
    WINDOWS_RESOURCES_DIR.mkdir(parents=True, exist_ok=True)
    ico_file = WINDOWS_RESOURCES_DIR / "app_icon.ico"

    source_img.save(
        ico_file,
        format="ICO",
        sizes=WINDOWS_ICO_SIZES,
    )
    generated.append(ico_file)
    return generated


def generate_macos_icons(source_img: Image.Image) -> List[Path]:
    """Generate macOS xcassets icons if the directory exists."""
    generated: List[Path] = []
    if not MACOS_ICONSET_DIR.exists():
        return generated

    for filename, size in MACOS_SIZES.items():
        out_file = MACOS_ICONSET_DIR / filename
        resized = source_img.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(out_file, format="PNG", optimize=True)
        generated.append(out_file)

    return generated


def verify_generated_artifacts() -> bool:
    """Verify all expected icon artifacts exist, are non-empty, and match dimensions."""
    print("\n--- Verifying Generated Artifacts ---")
    all_ok = True

    # 1. Verify Android legacy icons
    for dir_name, expected_size in ANDROID_LEGACY_SIZES.items():
        path = ANDROID_RES_DIR / dir_name / "ic_launcher.png"
        if not path.exists():
            print(f"[FAIL] Missing Android icon: {path.relative_to(REPO_ROOT)}")
            all_ok = False
            continue
        try:
            with Image.open(path) as img:
                if img.size != (expected_size, expected_size):
                    print(f"[FAIL] {path.name} in {dir_name}: expected {expected_size}x{expected_size}, got {img.size}")
                    all_ok = False
                else:
                    file_size = path.stat().st_size
                    print(f"[PASS] Android legacy: {dir_name}/ic_launcher.png ({expected_size}x{expected_size}, {file_size} bytes)")
        except Exception as e:
            print(f"[FAIL] Error reading {path}: {e}")
            all_ok = False

    # 2. Verify Android adaptive icons
    bg_xml = ANDROID_VALUES_DIR / "ic_launcher_background.xml"
    if bg_xml.exists() and bg_xml.stat().st_size > 0:
        ET.parse(bg_xml)
        print(f"[PASS] Android adaptive background XML: {bg_xml.relative_to(REPO_ROOT)} ({bg_xml.stat().st_size} bytes)")
    else:
        print(f"[FAIL] Missing or empty {bg_xml}")
        all_ok = False

    adaptive_xml = ANDROID_ADAPTIVE_DIR / "ic_launcher.xml"
    if adaptive_xml.exists() and adaptive_xml.stat().st_size > 0:
        ET.parse(adaptive_xml)
        print(f"[PASS] Android adaptive launcher XML: {adaptive_xml.relative_to(REPO_ROOT)} ({adaptive_xml.stat().st_size} bytes)")
    else:
        print(f"[FAIL] Missing or empty {adaptive_xml}")
        all_ok = False

    fg_png = ANDROID_DRAWABLE_DIR / "ic_launcher_foreground.png"
    if fg_png.exists():
        with Image.open(fg_png) as img:
            if img.size == (ADAPTIVE_CANVAS_SIZE, ADAPTIVE_CANVAS_SIZE):
                print(f"[PASS] Android adaptive foreground: {fg_png.relative_to(REPO_ROOT)} ({img.size[0]}x{img.size[1]}, {fg_png.stat().st_size} bytes)")
            else:
                print(f"[FAIL] Adaptive foreground size mismatch: expected {ADAPTIVE_CANVAS_SIZE}x{ADAPTIVE_CANVAS_SIZE}, got {img.size}")
                all_ok = False
    else:
        print(f"[FAIL] Missing {fg_png}")
        all_ok = False

    # 3. Verify Windows ICO
    win_ico = WINDOWS_RESOURCES_DIR / "app_icon.ico"
    if win_ico.exists() and win_ico.stat().st_size > 0:
        with open(win_ico, "rb") as f:
            data = f.read()
        reserved, ico_type, count = struct.unpack("<HHH", data[:6])
        if ico_type == 1 and count >= len(WINDOWS_ICO_SIZES):
            frame_sizes = []
            for i in range(count):
                entry = data[6 + i * 16 : 6 + (i + 1) * 16]
                w, h = entry[0], entry[1]
                w = 256 if w == 0 else w
                h = 256 if h == 0 else h
                frame_sizes.append((w, h))
            print(f"[PASS] Windows ICO: {win_ico.relative_to(REPO_ROOT)} ({count} frames: {frame_sizes}, {len(data)} bytes)")
        else:
            print(f"[FAIL] Invalid ICO header or frame count in {win_ico}")
            all_ok = False
    else:
        print(f"[FAIL] Missing or empty {win_ico}")
        all_ok = False

    # 4. Verify macOS icons
    if MACOS_ICONSET_DIR.exists():
        for filename, expected_size in MACOS_SIZES.items():
            path = MACOS_ICONSET_DIR / filename
            if not path.exists():
                print(f"[FAIL] Missing macOS icon: {filename}")
                all_ok = False
                continue
            with Image.open(path) as img:
                if img.size != (expected_size, expected_size):
                    print(f"[FAIL] macOS {filename}: expected {expected_size}x{expected_size}, got {img.size}")
                    all_ok = False
                else:
                    print(f"[PASS] macOS: {filename} ({expected_size}x{expected_size}, {path.stat().st_size} bytes)")

    return all_ok


def main() -> None:
    """Main execution entry point."""
    print("==================================================")
    print(" Hermex Flutter Icon Generation Pipeline")
    print("==================================================")
    print(f"Pillow Version : {getattr(Image, '__version__', 'unknown')}")
    print(f"Repository Root: {REPO_ROOT}")
    print(f"Source Asset   : {SOURCE_ICON_PATH.relative_to(REPO_ROOT)}")

    source_img = load_source_image(SOURCE_ICON_PATH)
    print(f"Source Image Loaded: {source_img.size} mode={source_img.mode}")

    print("\n1. Generating Android Legacy Icons...")
    android_legacy = generate_android_legacy_icons(source_img)
    for p in android_legacy:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n2. Generating Android Adaptive Icons...")
    android_adaptive = generate_android_adaptive_icons(source_img)
    for p in android_adaptive:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n3. Generating Windows ICO...")
    windows_ico = generate_windows_icon(source_img)
    for p in windows_ico:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    print("\n4. Generating macOS AppIcon Set...")
    macos_icons = generate_macos_icons(source_img)
    for p in macos_icons:
        print(f"   -> {p.relative_to(REPO_ROOT)}")

    ok = verify_generated_artifacts()
    if not ok:
        print("\n[ERROR] Verification failed!", file=sys.stderr)
        sys.exit(1)

    print("\n[SUCCESS] All platform icon assets generated and verified successfully!")


if __name__ == "__main__":
    main()
