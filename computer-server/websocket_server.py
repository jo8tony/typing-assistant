import asyncio
import json
import time
from typing import Set
import websockets
from websockets.server import WebSocketServerProtocol
from config import Config
from input_simulator import get_simulator

class TypingServer:
    """WebSocket 打字服务器"""
    
    def __init__(self):
        self.clients: Set[WebSocketServerProtocol] = set()
        self.last_heartbeat: dict = {}
        self.simulator = get_simulator()
        self.is_running = False
    
    async def register(self, websocket: WebSocketServerProtocol):
        """注册新客户端"""
        # 检查 IP 是否允许连接
        client_ip = websocket.remote_address[0]
        if not Config.is_allowed_ip(client_ip):
            print(f"拒绝连接: {client_ip} (不在允许的网段)")
            await websocket.close(1008, "IP not allowed")
            return
        
        self.clients.add(websocket)
        self.last_heartbeat[websocket] = time.time()
        print(f"新客户端连接: {client_ip}")
        print(f"当前连接数: {len(self.clients)}")
        
        # 发送连接成功确认
        try:
            response = {
                'type': 'connected',
                'message': '连接成功',
                'timestamp': int(time.time() * 1000),
            }
            await websocket.send(json.dumps(response))
        except Exception as e:
            print(f"发送连接确认失败: {e}")
    
    async def unregister(self, websocket: WebSocketServerProtocol):
        """注销客户端"""
        if websocket in self.clients:
            self.clients.remove(websocket)
            if websocket in self.last_heartbeat:
                del self.last_heartbeat[websocket]
            client_ip = websocket.remote_address[0]
            print(f"客户端断开: {client_ip}")
            print(f"当前连接数: {len(self.clients)}")
    
    async def handle_message(self, websocket: WebSocketServerProtocol, message: str):
        """处理客户端消息"""
        try:
            data = json.loads(message)
            msg_type = data.get('type')
            
            if msg_type == 'text':
                # 处理文字输入
                content = data.get('content', '')
                if content:
                    success = self.simulator.type_text(content)
                    response = {
                        'type': 'input_result',
                        'success': success,
                        'message': '输入成功' if success else '输入失败',
                    }
                    await websocket.send(json.dumps(response, ensure_ascii=False))
                    print(f"输入文字: {content[:50]}{'...' if len(content) > 50 else ''}")
                    
            elif msg_type == 'ping':
                # 处理心跳
                self.last_heartbeat[websocket] = time.time()
                response = {
                    'type': 'pong',
                    'timestamp': int(time.time() * 1000),
                }
                await websocket.send(json.dumps(response))
                
            elif msg_type == 'ocr_text':
                # 处理 OCR 选中的文字
                selected_text = data.get('selected_text', '')
                if selected_text:
                    success = self.simulator.type_text(selected_text)
                    response = {
                        'type': 'input_result',
                        'success': success,
                        'message': '输入成功' if success else '输入失败',
                    }
                    await websocket.send(json.dumps(response, ensure_ascii=False))
                    print(f"输入 OCR 文字: {selected_text[:50]}{'...' if len(selected_text) > 50 else ''}")
            else:
                print(f"未知消息类型: {msg_type}")
                
        except json.JSONDecodeError:
            print(f"收到无效的 JSON 消息: {message}")
        except Exception as e:
            print(f"处理消息时出错: {e}")
    
    async def client_handler(self, websocket: WebSocketServerProtocol):
        """客户端连接处理器"""
        await self.register(websocket)
        try:
            async for message in websocket:
                await self.handle_message(websocket, message)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self.unregister(websocket)
    
    async def heartbeat_checker(self):
        """心跳检测协程"""
        while self.is_running:
            await asyncio.sleep(Config.HEARTBEAT_INTERVAL)
            
            current_time = time.time()
            dead_clients = []
            
            for websocket, last_time in self.last_heartbeat.items():
                if current_time - last_time > Config.HEARTBEAT_TIMEOUT:
                    dead_clients.append(websocket)
            
            for websocket in dead_clients:
                print(f"客户端心跳超时，断开连接: {websocket.remote_address[0]}")
                await self.unregister(websocket)
                try:
                    await websocket.close()
                except:
                    pass
    
    async def start(self):
        """启动 WebSocket 服务器"""
        self.is_running = True
        
        # 启动心跳检测
        asyncio.create_task(self.heartbeat_checker())
        
        # 启动 WebSocket 服务器
        async with websockets.serve(
            self.client_handler,
            Config.WEBSOCKET_HOST,
            Config.WEBSOCKET_PORT,
        ):
            print(f"WebSocket 服务器已启动")
            print(f"  地址: ws://{Config.WEBSOCKET_HOST}:{Config.WEBSOCKET_PORT}")
            print(f"等待客户端连接...")
            
            # 保持运行
            while self.is_running:
                await asyncio.sleep(1)
    
    def stop(self):
        """停止服务器"""
        self.is_running = False
        print("WebSocket 服务器已停止")


# 单例实例
_server = None

def get_server() -> TypingServer:
    """获取服务器单例"""
    global _server
    if _server is None:
        _server = TypingServer()
    return _server
