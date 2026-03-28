#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 PNG 图标转换为 ICO 格式
用于 Windows 应用程序和安装程序
"""

import os
import sys
import io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

def convert_png_to_ico(png_path: str, ico_path: str):
    try:
        from PIL import Image
        
        if not os.path.exists(png_path):
            print(f"PNG file not found: {png_path}")
            return False
        
        img = Image.open(png_path)
        
        if img.mode != 'RGBA':
            img = img.convert('RGBA')
        
        sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
        
        icons = []
        for size in sizes:
            resized = img.resize(size, Image.Resampling.LANCZOS)
            icons.append(resized)
        
        img.save(
            ico_path,
            format='ICO',
            sizes=[(i.width, i.height) for i in icons],
            append_images=icons[1:]
        )
        
        print(f"Success: {png_path} -> {ico_path}")
        return True
        
    except ImportError:
        print("Error: Pillow not installed, run: pip install Pillow")
        return False
    except Exception as e:
        print(f"Failed: {e}")
        return False


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    png_path = os.path.join(script_dir, 'app_icon.png')
    ico_path = os.path.join(script_dir, 'app_icon.ico')
    
    if convert_png_to_ico(png_path, ico_path):
        print("Icon conversion complete!")
        sys.exit(0)
    else:
        print("Icon conversion failed!")
        sys.exit(1)


if __name__ == '__main__':
    main()
