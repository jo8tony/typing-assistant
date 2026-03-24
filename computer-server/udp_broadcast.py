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
            # 方法 1：使用 UDP 连接获取真实 IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0)
            try:
                # 连接到一个公网地址，获取实际使用的网络接口 IP
                s.connect(('8.8.8.8', 80))
                ip = s.getsockname()[0]
            except Exception:
                ip = '127.0.0.1'
            finally:
                s.close()
            
            # 排除 198.18.x.x (macOS NAT 网关)
            if ip.startswith('198.18.'):
                print(f"检测到 macOS NAT 地址 {ip}，尝试获取真实 IP...")
                # 方法 2：遍历所有网络接口
                import subprocess
                try:
                    result = subprocess.run(['ifconfig'], capture_output=True, text=True)
                    lines = result.stdout.split('\n')
                    for i, line in enumerate(lines):
                        if 'inet ' in line and '192.168.' in line:
                            parts = line.split()
                            ip = parts[1]
                            print(f"找到真实 IP: {ip}")
                            break
                except Exception as e:
                    print(f"获取网络接口失败：{e}")
            
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
            
            # 创建两个 UDP socket：一个用于发送广播，一个用于接收查询
            self.broadcast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            self.broadcast_socket.settimeout(1.0)
            
            # 接收 socket 绑定到端口
            self.receive_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.receive_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.receive_socket.bind(('', self.BROADCAST_PORT))
            self.receive_socket.settimeout(1.0)
            
            self.is_running = True
            
            # 启动广播线程
            broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
            broadcast_thread.start()
            print(f"  广播线程已启动")
            
            # 启动响应线程
            response_thread = threading.Thread(target=self._response_loop, daemon=True)
            response_thread.start()
            print(f"  响应线程已启动")
            
            print(f"UDP 广播服务已启动")
            return True
            
        except Exception as e:
            print(f"启动 UDP 广播服务失败：{e}")
            import traceback
            traceback.print_exc()
            return False
    
    def _broadcast_loop(self):
        """定期广播服务器信息"""
        print(f"  [广播线程] 开始定期广播...")
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
                
                print(f"  [广播] 已发送广播：{self.server_info['name']} @ {self.server_info['ip']}")
                
                # 每 2 秒广播一次
                time.sleep(2)
            except Exception as e:
                if self.is_running:
                    print(f"  [广播] 失败：{e}")
    
    def _response_loop(self):
        """监听并响应查询请求"""
        print(f"  [响应线程] 开始监听查询...")
        while self.is_running:
            try:
                data, addr = self.receive_socket.recvfrom(1024)
                message = json.loads(data.decode('utf-8'))
                
                print(f"  [响应] 收到查询请求：{addr[0]}:{addr[1]}")
                
                if message.get('type') == 'query':
                    # 响应查询
                    response = json.dumps({
                        'type': 'response',
                        'data': self.server_info
                    }).encode('utf-8')
                    
                    # 单播响应给查询者
                    self.broadcast_socket.sendto(response, addr)
                    print(f"  [响应] 已发送响应到 {addr[0]}:{addr[1]}")
                    
            except socket.timeout:
                pass
            except Exception as e:
                if self.is_running:
                    print(f"  [响应] 处理失败：{e}")
    
    def stop(self):
        """停止 UDP 广播服务"""
        self.is_running = False
        if self.broadcast_socket:
            try:
                self.broadcast_socket.close()
            except Exception as e:
                print(f"关闭广播 socket 失败：{e}")
            finally:
                self.broadcast_socket = None
        
        if self.receive_socket:
            try:
                self.receive_socket.close()
            except Exception as e:
                print(f"关闭接收 socket 失败：{e}")
            finally:
                self.receive_socket = None
        
        print("UDP 广播服务已停止")


# 单例实例
_udp_broadcast_service = None

def get_udp_broadcast_service() -> UdpBroadcastService:
    """获取 UDP 广播服务单例"""
    global _udp_broadcast_service
    if _udp_broadcast_service is None:
        _udp_broadcast_service = UdpBroadcastService()
    return _udp_broadcast_service
