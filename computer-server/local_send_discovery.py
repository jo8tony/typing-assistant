import socket
import json
import threading
import time
import platform
import uuid
import ssl
from config import Config

class LocalSendDiscoveryService:
    """
    LocalSend 风格的网络发现服务
    使用 UDP 多播进行设备发现
    """

    def __init__(self):
        self.multicast_socket = None
        self.http_server = None
        self.is_running = False
        self.server_id = str(uuid.uuid4())[:8]
        self._registered_devices = {}
        self.server_info = {
            'id': self.server_id,
            'name': '',
            'ip': '',
            'port': Config.WEBSOCKET_PORT,
            'platform': platform.system().lower(),
            'version': '1.0',
            'deviceType': 'desktop',
            'apiVersion': Config.API_VERSION,
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

            if ip.startswith('198.18.'):
                print(f"检测到 macOS NAT 地址 {ip}，尝试获取真实 IP...")
                import subprocess
                try:
                    result = subprocess.run(['ifconfig'], capture_output=True, text=True)
                    lines = result.stdout.split('\n')
                    for line in lines:
                        if 'inet ' in line and '192.168.' in line:
                            parts = line.split()
                            ip = parts[1]
                            break
                except Exception:
                    pass

            return ip
        except Exception:
            return '127.0.0.1'

    def start(self, server_name: str) -> bool:
        """
        启动 LocalSend 风格的发现服务

        Args:
            server_name: 服务器名称

        Returns:
            bool: 是否启动成功
        """
        try:
            local_ip = self.get_local_ip()
            self.server_info.update({
                'name': server_name,
                'ip': local_ip,
                'port': Config.WEBSOCKET_PORT,
                'platform': platform.system().lower(),
            })

            print(f"正在启动 LocalSend 风格发现服务...")
            print(f"  服务器 ID: {self.server_id}")
            print(f"  服务器名称: {server_name}")
            print(f"  服务器 IP: {local_ip}")
            print(f"  多播地址: {Config.MULTICAST_ADDRESS}:{Config.MULTICAST_PORT}")

            if not self._start_multicast_listener():
                return False

            if not self._start_http_server():
                return False

            self.is_running = True

            broadcast_thread = threading.Thread(target=self._broadcast_loop, daemon=True)
            broadcast_thread.start()
            print(f"  ✓ 广播线程已启动")

            cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
            cleanup_thread.start()
            print(f"  ✓ 清理线程已启动")

            print(f"✓ LocalSend 风格发现服务已启动")
            return True

        except Exception as e:
            print(f"✗ 启动发现服务失败：{e}")
            import traceback
            traceback.print_exc()
            return False

    def _start_multicast_listener(self) -> bool:
        """启动 UDP 多播监听器"""
        try:
            self.multicast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            if platform.system() != 'Windows':
                self.multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)

            if hasattr(socket, 'SO_REUSE_PORT'):
                self.multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSE_PORT, 1)

            self.multicast_socket.bind(('', Config.MULTICAST_PORT))
            self.multicast_socket.settimeout(1.0)

            try:
                group = socket.inet_aton(Config.MULTICAST_ADDRESS)
                mreq = group + socket.inet_aton('0.0.0.0')
                self.multicast_socket.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
                self.multicast_socket.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, Config.MULTICAST_TTL)
            except Exception as e:
                print(f"  警告：无法加入多播组: {e}，可能无法接收多播消息")

            listen_thread = threading.Thread(target=self._multicast_listen_loop, daemon=True)
            listen_thread.start()
            print(f"  ✓ 多播监听器已启动")
            return True

        except Exception as e:
            print(f"✗ 启动多播监听器失败：{e}")
            return False

    def _start_http_server(self) -> bool:
        """启动 HTTP 注册服务器"""
        try:
            http_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            http_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            http_socket.bind(('0.0.0.0', Config.DISCOVERY_HTTP_PORT))
            http_socket.listen(5)
            http_socket.settimeout(1.0)

            self.http_server = http_socket
            http_thread = threading.Thread(target=self._http_server_loop, daemon=True)
            http_thread.start()
            print(f"  ✓ HTTP 注册服务器已启动 (端口 {Config.DISCOVERY_HTTP_PORT})")
            return True

        except Exception as e:
            print(f"✗ 启动 HTTP 注册服务器失败：{e}")
            return False

    def _broadcast_loop(self):
        """定期广播服务器信息"""
        print(f"  [广播] 开始定期广播...")
        broadcast_count = 0
        while self.is_running:
            try:
                message = json.dumps({
                    'type': 'announce',
                    'device': self.server_info,
                    'timestamp': int(time.time() * 1000),
                }).encode('utf-8')

                self.multicast_socket.sendto(
                    message,
                    (Config.MULTICAST_ADDRESS, Config.MULTICAST_PORT)
                )

                broadcast_count += 1
                if broadcast_count % 10 == 0:
                    print(f"  [广播] #{broadcast_count} 已发送：{self.server_info['name']} @ {self.server_info['ip']}")

                time.sleep(2)

            except Exception as e:
                if self.is_running:
                    print(f"  [广播] ✗ 失败：{e}")

    def _multicast_listen_loop(self):
        """监听多播消息"""
        print(f"  [多播监听] 开始监听...")
        while self.is_running:
            try:
                data, addr = self.multicast_socket.recvfrom(4096)
                self._handle_multicast_message(data, addr)
            except socket.timeout:
                pass
            except Exception as e:
                if self.is_running:
                    pass

    def _handle_multicast_message(self, data: bytes, addr):
        """处理收到的多播消息"""
        try:
            message = json.loads(data.decode('utf-8'))
            msg_type = message.get('type')

            if msg_type == 'announce':
                device = message.get('device')
                if device and device.get('id') != self.server_id:
                    device_ip = device.get('ip', addr[0])
                    print(f"  [多播] 发现设备: {device.get('name')} @ {device_ip}")
                    self._registered_devices[device.get('id')] = {
                        **device,
                        'ip': device_ip,
                        'lastSeen': time.time(),
                    }

            elif msg_type == 'probe':
                response = json.dumps({
                    'type': 'announce',
                    'device': self.server_info,
                    'timestamp': int(time.time() * 1000),
                }).encode('utf-8')
                self.multicast_socket.sendto(response, addr)
                print(f"  [多播] 响应探测请求 from {addr[0]}")

        except Exception as e:
            pass

    def _http_server_loop(self):
        """HTTP 服务器循环"""
        print(f"  [HTTP] 开始监听注册请求...")
        while self.is_running:
            try:
                client_socket, client_addr = self.http_server.accept()
                threading.Thread(
                    target=self._handle_http_request,
                    args=(client_socket, client_addr),
                    daemon=True
                ).start()
            except socket.timeout:
                pass
            except Exception as e:
                if self.is_running:
                    pass

    def _handle_http_request(self, client_socket, client_addr):
        """处理 HTTP 注册请求"""
        try:
            request = client_socket.recv(4096).decode('utf-8')
            lines = request.split('\r\n')

            if not lines:
                client_socket.close()
                return

            request_line = lines[0]
            parts = request_line.split(' ')

            if len(parts) < 2:
                client_socket.close()
                return

            method, path = parts[0], parts[1]

            if method == 'POST' and path == f'/api/{Config.API_VERSION}/register':
                content_length = 0
                for line in lines[1:]:
                    if line.startswith('Content-Length:'):
                        content_length = int(line.split(':')[1].strip())
                        break

                if content_length > 0:
                    body = b''
                    while len(body) < content_length:
                        chunk = client_socket.recv(content_length - len(body))
                        if not chunk:
                            break
                        body += chunk

                    try:
                        data = json.loads(body.decode('utf-8'))
                        device = data.get('device', {})

                        if device:
                            device_id = device.get('id')
                            device_ip = data.get('ip', client_addr[0])
                            print(f"  [HTTP] 设备注册: {device.get('name')} @ {device_ip}")

                            self._registered_devices[device_id] = {
                                **device,
                                'ip': device_ip,
                                'lastSeen': time.time(),
                            }

                            response = json.dumps({
                                'type': 'register',
                                'status': 'success',
                                'device': self.server_info,
                            })
                            client_socket.sendall(
                                f"HTTP/1.1 200 OK\r\n"
                                f"Content-Type: application/json\r\n"
                                f"Content-Length: {len(response)}\r\n"
                                f"Connection: close\r\n"
                                f"\r\n"
                                f"{response}".encode('utf-8')
                            )
                        else:
                            client_socket.sendall(
                                b"HTTP/1.1 400 Bad Request\r\n\r\n"
                            )
                    except json.JSONDecodeError:
                        client_socket.sendall(
                            b"HTTP/1.1 400 Bad Request\r\n\r\n"
                        )
                else:
                    client_socket.sendall(
                        b"HTTP/1.1 400 Bad Request\r\n\r\n"
                    )

            elif method == 'GET' and path == f'/api/{Config.API_VERSION}/info':
                response = json.dumps({
                    'type': 'info',
                    'device': self.server_info,
                })
                client_socket.sendall(
                    f"HTTP/1.1 200 OK\r\n"
                    f"Content-Type: application/json\r\n"
                    f"Content-Length: {len(response)}\r\n"
                    f"Connection: close\r\n"
                    f"\r\n"
                    f"{response}".encode('utf-8')
                )
            else:
                client_socket.sendall(
                    b"HTTP/1.1 404 Not Found\r\n\r\n"
                )

        except Exception as e:
            pass
        finally:
            try:
                client_socket.close()
            except Exception:
                pass

    def _cleanup_loop(self):
        """定期清理过期的设备注册信息"""
        while self.is_running:
            try:
                time.sleep(10)
                current_time = time.time()
                expired_ids = [
                    device_id
                    for device_id, device in self._registered_devices.items()
                    if current_time - device.get('lastSeen', 0) > 30
                ]
                for device_id in expired_ids:
                    del self._registered_devices[device_id]
                    print(f"  [清理] 移除过期设备: {device_id}")
            except Exception:
                pass

    def get_registered_devices(self):
        """获取已注册的设备列表"""
        return list(self._registered_devices.values())

    def stop(self):
        """停止发现服务"""
        self.is_running = False

        if self.multicast_socket:
            try:
                self.multicast_socket.close()
            except Exception:
                pass
            self.multicast_socket = None

        if self.http_server:
            try:
                self.http_server.close()
            except Exception:
                pass
            self.http_server = None

        print("LocalSend 风格发现服务已停止")


_single_instance = None

def get_local_send_discovery_service() -> LocalSendDiscoveryService:
    """获取 LocalSend 发现服务单例"""
    global _single_instance
    if _single_instance is None:
        _single_instance = LocalSendDiscoveryService()
    return _single_instance