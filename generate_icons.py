#!/usr/bin/env python3
"""
生成 App 图标资源
基于 character_1.png 生成各种尺寸的图标
"""

from PIL import Image
import os

# Android 图标尺寸
ANDROID_ICON_SIZES = {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}

# 启动画面尺寸
SPLASH_SIZES = {
    'drawable-mdpi': (320, 480),
    'drawable-hdpi': (480, 800),
    'drawable-xhdpi': (720, 1280),
    'drawable-xxhdpi': (1080, 1920),
    'drawable-xxxhdpi': (1440, 2560),
}

def generate_android_icons(source_image_path, output_dir):
    """生成 Android 应用图标"""
    
    # 打开源图片
    img = Image.open(source_image_path)
    
    # 转换为 RGBA 模式（支持透明）
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # 裁剪为正方形（从中心）
    width, height = img.size
    size = min(width, height)
    left = (width - size) // 2
    top = (height - size) // 2
    right = left + size
    bottom = top + size
    img = img.crop((left, top, right, bottom))
    
    # 生成各种尺寸的图标
    for folder, icon_size in ANDROID_ICON_SIZES.items():
        folder_path = os.path.join(output_dir, 'android', 'app', 'src', 'main', 'res', folder)
        os.makedirs(folder_path, exist_ok=True)
        
        # 调整大小
        resized = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        
        # 保存
        output_path = os.path.join(folder_path, 'ic_launcher.png')
        resized.save(output_path, 'PNG')
        print(f"✓ 生成: {output_path}")
        
        # 生成圆形图标（Android 8.0+）
        if icon_size >= 72:
            circular = create_circular_icon(resized, icon_size)
            output_path_round = os.path.join(folder_path, 'ic_launcher_round.png')
            circular.save(output_path_round, 'PNG')
            print(f"✓ 生成: {output_path_round}")

def create_circular_icon(img, size):
    """创建圆形图标"""
    # 创建圆形遮罩
    mask = Image.new('L', (size, size), 0)
    from PIL import ImageDraw
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, size, size), fill=255)
    
    # 应用遮罩
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(img, (0, 0))
    output.putalpha(mask)
    
    return output

def generate_splash_screens(source_image_path, output_dir):
    """生成启动画面"""
    
    img = Image.open(source_image_path)
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    for folder, (width, height) in SPLASH_SIZES.items():
        folder_path = os.path.join(output_dir, 'android', 'app', 'src', 'main', 'res', folder)
        os.makedirs(folder_path, exist_ok=True)
        
        # 创建白色背景
        background = Image.new('RGB', (width, height), (255, 255, 255))
        
        # 计算图标大小（屏幕宽度的 40%）
        icon_size = int(width * 0.4)
        resized = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        
        # 居中放置
        x = (width - icon_size) // 2
        y = (height - icon_size) // 2
        
        # 粘贴图标
        background.paste(resized, (x, y), resized)
        
        # 保存
        output_path = os.path.join(folder_path, 'launch_background.png')
        background.save(output_path, 'PNG')
        print(f"✓ 生成: {output_path}")

def generate_store_graphics(source_image_path, output_dir):
    """生成应用商店图形"""
    
    img = Image.open(source_image_path)
    if img.mode != 'RGBA':
        img = img.convert('RGBA')
    
    # Google Play 商店图标 (512x512)
    play_icon = img.resize((512, 512), Image.Resampling.LANCZOS)
    play_icon_path = os.path.join(output_dir, 'store_graphics', 'play_store_icon.png')
    os.makedirs(os.path.dirname(play_icon_path), exist_ok=True)
    play_icon.save(play_icon_path, 'PNG')
    print(f"✓ 生成: {play_icon_path}")
    
    # 功能图形 (1024x500)
    feature_graphic = Image.new('RGB', (1024, 500), (255, 255, 255))
    icon_size = 400
    resized = img.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
    x = (1024 - icon_size) // 2
    y = (500 - icon_size) // 2
    feature_graphic.paste(resized, (x, y), resized)
    feature_path = os.path.join(output_dir, 'store_graphics', 'feature_graphic.png')
    feature_graphic.save(feature_path, 'PNG')
    print(f"✓ 生成: {feature_path}")

def main():
    """主函数"""
    
    # 路径配置
    script_dir = os.path.dirname(os.path.abspath(__file__))
    source_image = os.path.join(script_dir, 'mobile_app', 'assets', 'images', 'character_1.png')
    output_dir = script_dir
    
    print("=" * 50)
    print("  生成 App 图标资源")
    print("=" * 50)
    print()
    
    if not os.path.exists(source_image):
        print(f"✗ 错误: 找不到源图片 {source_image}")
        return
    
    print(f"源图片: {source_image}")
    print()
    
    # 生成图标
    print("生成 Android 应用图标...")
    generate_android_icons(source_image, output_dir)
    print()
    
    print("生成启动画面...")
    generate_splash_screens(source_image, output_dir)
    print()
    
    print("生成应用商店图形...")
    generate_store_graphics(source_image, output_dir)
    print()
    
    print("=" * 50)
    print("  完成！")
    print("=" * 50)
    print()
    print("生成的文件:")
    print("  - Android 图标: android/app/src/main/res/mipmap-*/")
    print("  - 启动画面: android/app/src/main/res/drawable-*/")
    print("  - 商店图形: store_graphics/")

if __name__ == '__main__':
    main()
