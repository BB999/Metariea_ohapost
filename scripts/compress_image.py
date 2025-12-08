#!/usr/bin/env python3
"""画像を5MB以下に圧縮するスクリプト"""

import os
import sys
from PIL import Image

def compress_image(input_path):
    """画像を圧縮して5MB以下にする"""
    output_path = os.path.splitext(input_path)[0] + '_compressed.jpg'
    final_path = input_path.rsplit('.', 1)[0] + '.jpg'

    MAX_SIZE_BYTES = 5 * 1024 * 1024  # 5MB

    print(f'📥 入力: {input_path}')

    img = Image.open(input_path)
    print(f'📐 元の解像度: {img.size[0]}x{img.size[1]}')

    # RGBAの場合はRGBに変換（JPEGは透過非対応）
    if img.mode in ('RGBA', 'P'):
        img = img.convert('RGB')
        print('🔄 RGBに変換しました')

    # 最大幅/高さを1920に制限
    max_size = 1920
    if img.size[0] > max_size or img.size[1] > max_size:
        img.thumbnail((max_size, max_size), Image.Resampling.LANCZOS)
        print(f'📐 リサイズ後: {img.size[0]}x{img.size[1]}')

    # 品質を段階的に下げて5MB以下になるまで試行
    for quality in [85, 75, 65, 55, 45, 35]:
        img.save(output_path, 'JPEG', quality=quality, optimize=True)
        new_size = os.path.getsize(output_path)
        print(f'🔄 品質{quality}%で圧縮: {new_size} bytes ({new_size/1024/1024:.2f} MB)')

        if new_size <= MAX_SIZE_BYTES:
            print(f'✅ 5MB以下になりました（品質{quality}%）')
            break
    else:
        # それでも5MB超えるなら更にリサイズ
        print('⚠️ 品質35%でも5MB超え、さらにリサイズします...')
        img.thumbnail((1280, 1280), Image.Resampling.LANCZOS)
        img.save(output_path, 'JPEG', quality=50, optimize=True)
        new_size = os.path.getsize(output_path)
        print(f'📐 1280pxにリサイズ: {new_size} bytes ({new_size/1024/1024:.2f} MB)')

    os.replace(output_path, final_path)
    print(f'✅ 圧縮完了: {final_path}')
    return final_path

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: compress_image.py <image_path>')
        sys.exit(1)

    result = compress_image(sys.argv[1])
    print(result)
