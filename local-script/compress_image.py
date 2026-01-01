#!/usr/bin/env python3
"""
画像圧縮スクリプト
Usage: python3 compress_image.py <入力ファイル> <出力ファイル> [最大幅] [品質]
"""

import sys
from PIL import Image


def compress_image(input_path, output_path, max_width=1920, quality=85):
    """画像を圧縮してJPEGで保存"""
    try:
        with Image.open(input_path) as img:
            # RGBAの場合はRGBに変換
            if img.mode in ('RGBA', 'P'):
                img = img.convert('RGB')

            # リサイズ（アスペクト比維持）
            if img.width > max_width:
                ratio = max_width / img.width
                new_height = int(img.height * ratio)
                img = img.resize((max_width, new_height), Image.Resampling.LANCZOS)
                print(f"📐 リサイズ: {img.width}x{img.height}")

            # JPEG保存
            img.save(output_path, 'JPEG', quality=quality, optimize=True)

            import os
            original_size = os.path.getsize(input_path)
            new_size = os.path.getsize(output_path)
            print(f"✅ 圧縮完了: {original_size:,} bytes → {new_size:,} bytes")
            print(f"   圧縮率: {(1 - new_size/original_size)*100:.1f}%")

            return True

    except Exception as e:
        print(f"❌ 圧縮エラー: {e}")
        return False


def main():
    if len(sys.argv) < 3:
        print("Usage: python3 compress_image.py <入力ファイル> <出力ファイル> [最大幅] [品質]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]
    max_width = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
    quality = int(sys.argv[4]) if len(sys.argv) > 4 else 85

    success = compress_image(input_path, output_path, max_width, quality)
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()
