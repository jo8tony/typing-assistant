#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨设备打字助手 - 电脑端服务
专为不熟悉电脑打字的中年人设计
使用 LocalSend 风格的服务发现机制
"""

import asyncio
import signal
import sys
import os
import platform

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from config import Config
from websocket_server import get_server
from discovery_service import get_discovery_service

running = True

def signal_handler(signum, frame):
    global running
    print("\n收到退出信号，正在关闭服务...")
    running = False

async def main():
    global running

    print()
    print("╔════════════════════════════════════════════════════╗")
    print("║        跨设备打字助手 - 电脑端服务                 ║")
    print("║        LocalSend 风格服务发现                      ║")
    print("╚════════════════════════════════════════════════════╝")
    print()

    Config.load()
    Config.save()

    server = get_server()
    discovery = get_discovery_service()

    hostname = platform.node()
    server_name = f"打字助手-{hostname}"

    if not discovery.start(server_name):
        print("警告：发现服务启动失败，手机可能无法自动发现电脑")
        print("请手动输入电脑 IP 地址进行连接")
        print()

    print("正在启动 WebSocket 服务器...")
    print()

    try:
        await server.start()
    except KeyboardInterrupt:
        pass
    finally:
        server.stop()
        discovery.stop()
        print()
        print("服务已完全关闭")

def run_with_tray():
    try:
        import pystray
        from PIL import Image, ImageDraw

        def create_image():
            width = 64
            height = 64
            image = Image.new('RGB', (width, height), color='white')
            dc = ImageDraw.Draw(image)
            dc.rectangle([0, 0, width, height], fill='#4CAF50')
            dc.text((width//2-10, height//2-10), 'T', fill='white')
            return image

        def on_exit(icon, item):
            icon.stop()
            global running
            running = False
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

        def run_async():
            asyncio.run(main())

        import threading
        thread = threading.Thread(target=run_async, daemon=True)
        thread.start()

        icon.run()

    except ImportError:
        print("未安装 pystray，以命令行模式运行")
        asyncio.run(main())

if __name__ == '__main__':
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    if len(sys.argv) > 1 and sys.argv[1] == '--tray':
        run_with_tray()
    else:
        try:
            asyncio.run(main())
        except KeyboardInterrupt:
            print("\n服务已停止")
