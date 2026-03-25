import socket
import json
import threading
import time
import platform
import hashlib
from typing import Dict, Optional, Callable
from config import Config

class DiscoveryService:
    """
    LocalSend 风格的网络发现服务
    使用 UDP 多播进行设备发现，端口 53317
    """

    def __init__(self):
        self.multicast_socket: Optional[socket.socket] = None
        self.is_running = False
        self.device_info: Dict = {}
        self.local_ip: str = "0.0.0.0"
        self._discovered_devices: Dict[str, Dict] = {}
        self._on_device_discovered: Optional[Callable] = None
        self._threads: list = []

    def get_local_ip(self) -> str:
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
                import subprocess
                try:
                    result = subprocess.run(['ifconfig'], capture_output=True, text=True)
                    lines = result.stdout.split('\n')
                    for line in lines:
                        if 'inet ' in line and ('192.168.' in line or '10.' in line):
                            parts = line.split()
                            ip = parts[1]
                            break
                except Exception:
                    pass

            return ip
        except Exception:
            return '127.0.0.1'

    def start(self, device_name: str = None) -> bool:
        try:
            self.local_ip = self.get_local_ip()
            self.device_info = Config.get_device_info(
                name=device_name,
                ip=self.local_ip
            )

            print("=" * 50)
            print("启动 LocalSend 风格发现服务")
            print("=" * 50)
            print(f"  设备名称: {self.device_info['alias']}")
            print(f"  设备指纹: {self.device_info['fingerprint'][:8]}...")
            print(f"  设备类型: {self.device_info['deviceType']}")
            print(f"  本机 IP: {self.local_ip}")
            print(f"  WebSocket 端口: {self.device_info['port']}")
            print(f"  多播地址: {Config.MULTICAST_ADDRESS}:{Config.MULTICAST_PORT}")
            print()

            if not self._start_multicast():
                return False

            self.is_running = True

            announce_thread = threading.Thread(target=self._announce_loop, daemon=True)
            announce_thread.start()
            self._threads.append(announce_thread)

            cleanup_thread = threading.Thread(target=self._cleanup_loop, daemon=True)
            cleanup_thread.start()
            self._threads.append(cleanup_thread)

            print("✓ 发现服务启动成功")
            print()
            return True

        except Exception as e:
            print(f"✗ 启动发现服务失败: {e}")
            import traceback
            traceback.print_exc()
            return False

    def _start_multicast(self) -> bool:
        try:
            self.multicast_socket = socket.socket(
                socket.AF_INET,
                socket.SOCK_DGRAM,
                socket.IPPROTO_UDP
            )

            self.multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            if platform.system() != 'Windows':
                try:
                    self.multicast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEPORT, 1)
                except AttributeError:
                    pass

            self.multicast_socket.bind(('', Config.MULTICAST_PORT))

            try:
                group = socket.inet_aton(Config.MULTICAST_ADDRESS)
                mreq = group + socket.inet_aton('0.0.0.0')
                self.multicast_socket.setsockopt(
                    socket.IPPROTO_IP,
                    socket.IP_ADD_MEMBERSHIP,
                    mreq
                )
                self.multicast_socket.setsockopt(
                    socket.IPPROTO_IP,
                    socket.IP_MULTICAST_TTL,
                    Config.MULTICAST_TTL
                )
                print(f"  ✓ 已加入多播组 {Config.MULTICAST_ADDRESS}")
            except Exception as e:
                print(f"  ⚠ 无法加入多播组: {e}")
                print(f"    多播发现可能无法工作，但 HTTP 发现仍可用")

            self.multicast_socket.settimeout(1.0)

            listen_thread = threading.Thread(target=self._listen_loop, daemon=True)
            listen_thread.start()
            self._threads.append(listen_thread)

            print(f"  ✓ 多播监听器已启动 (端口 {Config.MULTICAST_PORT})")
            return True

        except Exception as e:
            print(f"  ✗ 启动多播失败: {e}")
            return False

    def _announce_loop(self):
        while self.is_running:
            try:
                self._send_announce()
                time.sleep(Config.ANNOUNCE_INTERVAL)
            except Exception as e:
                if self.is_running:
                    print(f"  [广播] 错误: {e}")

    def _send_announce(self):
        if not self.multicast_socket:
            return

        try:
            message = json.dumps({
                "announce": True,
                "fingerprint": self.device_info["fingerprint"],
                "alias": self.device_info["alias"],
                "version": self.device_info["version"],
                "deviceModel": self.device_info["deviceModel"],
                "deviceType": self.device_info["deviceType"],
                "port": self.device_info["port"],
                "protocol": self.device_info["protocol"],
                "download": self.device_info["download"],
                "announce": self.device_info["announce"],
            }, ensure_ascii=False).encode('utf-8')

            self.multicast_socket.sendto(
                message,
                (Config.MULTICAST_ADDRESS, Config.MULTICAST_PORT)
            )
        except Exception as e:
            if self.is_running:
                pass

    def _listen_loop(self):
        while self.is_running:
            try:
                data, addr = self.multicast_socket.recvfrom(4096)
                self._handle_message(data, addr)
            except socket.timeout:
                pass
            except Exception as e:
                if self.is_running:
                    pass

    def _handle_message(self, data: bytes, addr: tuple):
        try:
            message = json.loads(data.decode('utf-8'))

            if message.get("announce"):
                fingerprint = message.get("fingerprint")
                if fingerprint and fingerprint != self.device_info["fingerprint"]:
                    device = {
                        "fingerprint": fingerprint,
                        "alias": message.get("alias", "未知设备"),
                        "version": message.get("version", ""),
                        "deviceModel": message.get("deviceModel", ""),
                        "deviceType": message.get("deviceType", "unknown"),
                        "port": message.get("port", Config.WEBSOCKET_PORT),
                        "protocol": message.get("protocol", "ws"),
                        "ip": addr[0],
                        "lastSeen": time.time(),
                    }

                    self._discovered_devices[fingerprint] = device

                    if self._on_device_discovered:
                        self._on_device_discovered(device)

                    print(f"  [发现] {device['alias']} @ {device['ip']}")

        except json.JSONDecodeError:
            pass
        except Exception as e:
            pass

    def _cleanup_loop(self):
        while self.is_running:
            try:
                time.sleep(10)
                current_time = time.time()
                expired = [
                    fp for fp, device in self._discovered_devices.items()
                    if current_time - device.get("lastSeen", 0) > 30
                ]
                for fp in expired:
                    del self._discovered_devices[fp]
            except Exception:
                pass

    def get_discovered_devices(self) -> list:
        return list(self._discovered_devices.values())

    def set_on_device_discovered(self, callback: Callable):
        self._on_device_discovered = callback

    def stop(self):
        self.is_running = False

        if self.multicast_socket:
            try:
                self.multicast_socket.close()
            except Exception:
                pass
            self.multicast_socket = None

        print("发现服务已停止")


_instance: Optional[DiscoveryService] = None

def get_discovery_service() -> DiscoveryService:
    global _instance
    if _instance is None:
        _instance = DiscoveryService()
    return _instance
