import socket
import json
import threading
import time
from config import Config

class UdpBroadcastService:
    """UDP 广播发现服务"""
    
    BROADCAST_PORT = 8766  # 使用与 WebSocket 不同的端口
    BROADCAST_ADDRESS = '<broadcast>'
    
    def __init__(self):
        self.broadcast_socket = None
        self.is_running = False
        self.server_info = {
            'name': '',
            'ip': '',
            'port': Config.WEBSOCKET_PORT,
            'platform': '',
            'version': '1.0'
        }
    
    def get_local_ip(self) -> str:
        """获取本机局域网 IP 地址"""
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0)
            try:
                s.connect(('8.8.8.8', 80))
                ip = s.getsockname()[0]
            except Exception:
                ip = '127.0.0.1'
            finally:
                s.close()
            return ip
        except Exception as e:
            print(f"获取本地 IP 失败：{e}")
            return '127.0.0.1'
    
    def start(self, server_name: str) -> bool:
        """
        启动 UDP 广播服务
        
        Args:
            server_name: 服务器名称
            
        Returns:
            bool: 是否启动成功
        """
        try:
            local_ip = self.get_local_ip()
            import platform
            self.server_info = {
                'name': server_name,
                'ip': local_ip,
                'port': Config.WEBSOCKET_PORT,
                'platform': platform.system().lower(),
                'version': '1.0'
            }
            
            print(f"正在启动 UDP 广播服务...")
            print(f"  广播地址：{self.BROADCAST_ADDRESS}:{self.BROADCAST_PORT}")
            print(f"  服务器信息：{self.server_info}")
            
            # 创建 UDP socket
            self.broadcast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            
            # 绑定到端口用于接收查询
            self.broadcast_socket.bind(('', self.BROADCAST_PORT))
            self.broadcast_socket.settimeout(1.0)
            
            self.is_running = True
            
            # 启动广播线程
            broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
            broadcast_thread.start()
            
            # 启动响应线程
            response_thread = threading.Thread(target=self._response_loop, daemon=True)
            response_thread.start()
            
            print(f"UDP 广播服务已启动")
            return True
            
        except Exception as e:
            print(f"启动 UDP 广播服务失败：{e}")
            import traceback
            traceback.print_exc()
            return False
    
    def _broadcast_loop(self):
        """定期广播服务器信息"""
        while self.is_running:
            try:
                message = json.dumps({
                    'type': 'discovery',
                    'data': self.server_info
                }).encode('utf-8')
                
                self.broadcast_socket.sendto(
                    message,
                    (self.BROADCAST_ADDRESS, self.BROADCAST_PORT)
                )
                
                # 每 2 秒广播一次
                time.sleep(2)
            except Exception as e:
                if self.is_running:
                    print(f"广播失败：{e}")
    
    def _response_loop(self):
        """监听并响应查询请求"""
        while self.is_running:
            try:
                data, addr = self.broadcast_socket.recvfrom(1024)
                message = json.loads(data.decode('utf-8'))
                
                if message.get('type') == 'query':
                    print(f"收到查询请求：{addr}")
                    # 响应查询
                    response = json.dumps({
                        'type': 'response',
                        'data': self.server_info
                    }).encode('utf-8')
                    
                    # 单播响应给查询者
                    self.broadcast_socket.sendto(response, addr)
                    
            except socket.timeout:
                pass
            except Exception as e:
                if self.is_running:
                    print(f"处理查询失败：{e}")
    
    def stop(self):
        """停止 UDP 广播服务"""
        self.is_running = False
        if self.broadcast_socket:
            try:
                self.broadcast_socket.close()
            except Exception as e:
                print(f"关闭 UDP socket 失败：{e}")
            finally:
                self.broadcast_socket = None
                print("UDP 广播服务已停止")


# 单例实例
_udp_broadcast_service = None

def get_udp_broadcast_service() -> UdpBroadcastService:
    """获取 UDP 广播服务单例"""
    global _udp_broadcast_service
    if _udp_broadcast_service is None:
        _udp_broadcast_service = UdpBroadcastService()
    return _udp_broadcast_service
