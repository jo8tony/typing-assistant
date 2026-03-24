#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨设备打字助手 - 电脑端服务
专为不熟悉电脑打字的中年人设计
"""

import asyncio
import signal
import sys
import os

# 添加当前目录到路径
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import Config
from websocket_server import get_server
from discovery_service import get_discovery_service
from udp_broadcast import get_udp_broadcast_service
import platform

# 全局标志，用于优雅退出
running = True

def signal_handler(signum, frame):
    """信号处理函数"""
    global running
    print("\n收到退出信号，正在关闭服务...")
    running = False

async def main():
    """主函数"""
    global running
    
    # 打印欢迎信息
    print("=" * 50)
    print("   跨设备打字助手 - 电脑端服务")
    print("   专为不熟悉电脑打字的中年人设计")
    print("=" * 50)
    print()
    
    # 加载配置
    Config.load()
    
    # 获取服务实例
    server = get_server()
    discovery = get_discovery_service()
    udp_broadcast = get_udp_broadcast_service()
    
    # 生成服务器名称
    hostname = platform.node()
    server_name = f"打字助手-{hostname}"
    
    # 启动 mDNS 发现服务
    if not discovery.start():
        print("警告：mDNS 服务启动失败，手机可能无法自动发现电脑")
        print("请手动输入电脑 IP 地址进行连接")
    
    # 启动 UDP 广播服务
    if not udp_broadcast.start(server_name):
        print("警告：UDP 广播服务启动失败")
    
    print()
    
    # 启动 WebSocket 服务器
    try:
        await server.start()
    except KeyboardInterrupt:
        pass
    finally:
        # 清理资源
        server.stop()
        discovery.stop()
        udp_broadcast.stop()
        print("服务已完全关闭")

def run_with_tray():
    """带系统托盘的运行模式 (可选)"""
    try:
        import pystray
        from PIL import Image, ImageDraw
        
        # 创建托盘图标
        def create_image():
            width = 64
            height = 64
            image = Image.new('RGB', (width, height), color='white')
            dc = ImageDraw.Draw(image)
            dc.rectangle([0, 0, width, height], fill='#4CAF50')
            dc.text((width//2-10, height//2-10), 'T', fill='white')
            return image
        
        # 托盘菜单
        def on_exit(icon, item):
            icon.stop()
            global running
            running = False
            # 停止服务
            server = get_server()
            discovery = get_discovery_service()
            server.stop()
            discovery.stop()
            sys.exit(0)
        
        menu = pystray.Menu(
            pystray.MenuItem('退出', on_exit)
        )
        
        icon = pystray.Icon(
            'typing_assistant',
            create_image(),
            '打字助手',
            menu
        )
        
        # 在后台运行 asyncio
        def run_async():
            asyncio.run(main())
        
        import threading
        thread = threading.Thread(target=run_async, daemon=True)
        thread.start()
        
        # 运行托盘图标
        icon.run()
        
    except ImportError:
        print("未安装 pystray，以命令行模式运行")
        asyncio.run(main())

if __name__ == '__main__':
    # 注册信号处理
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # 检查命令行参数
    if len(sys.argv) > 1 and sys.argv[1] == '--tray':
        run_with_tray()
    else:
        try:
            asyncio.run(main())
        except KeyboardInterrupt:
            print("\n服务已停止")
