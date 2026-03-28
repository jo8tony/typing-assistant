#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
将 PNG 图标转换为 ICO 格式
用于 Windows 应用程序和安装程序
"""

import os
import sys

def convert_png_to_ico(png_path: str, ico_path: str):
    try:
        from PIL import Image
        
        if not os.path.exists(png_path):
            print(f"PNG 文件不存在: {png_path}")
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
        
        print(f"成功转换: {png_path} -> {ico_path}")
        return True
        
    except ImportError:
        print("错误: 未安装 Pillow，请运行: pip install Pillow")
        return False
    except Exception as e:
        print(f"转换失败: {e}")
        return False


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    png_path = os.path.join(script_dir, 'app_icon.png')
    ico_path = os.path.join(script_dir, 'app_icon.ico')
    
    if convert_png_to_ico(png_path, ico_path):
        print("图标转换完成！")
        sys.exit(0)
    else:
        print("图标转换失败！")
        sys.exit(1)


if __name__ == '__main__':
    main()
