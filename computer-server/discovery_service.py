import socket
import platform
import traceback
from zeroconf import Zeroconf, ServiceInfo
from config import Config

class DiscoveryService:
    """mDNS 局域网发现服务"""
    
    def __init__(self):
        self.zeroconf = None
        self.service_info = None
        self.is_running = False
    
    def get_local_ip(self) -> str:
        """获取本机局域网 IP 地址"""
        try:
            # 方法 1：使用 UDP 连接获取真实 IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0)
            try:
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
    
    def _sanitize_name(self, name: str) -> str:
        """清理服务名称，移除 mDNS 不允许的字符"""
        import re
        sanitized = re.sub(r'[^a-zA-Z0-9\-]', '-', name)
        sanitized = re.sub(r'-+', '-', sanitized)
        sanitized = sanitized.strip('-')
        if not sanitized:
            sanitized = 'typing-assistant'
        return sanitized
    
    def start(self) -> bool:
        """
        启动 mDNS 服务广播
        
        Returns:
            bool: 是否启动成功
        """
        try:
            local_ip = self.get_local_ip()
            print(f"本机 IP: {local_ip}")
            
            hostname = platform.node()
            sanitized_name = self._sanitize_name(hostname)
            service_name = f"打字助手-{sanitized_name}"
            
            print(f"正在启动 mDNS 服务...")
            print(f"  主机名: {hostname}")
            print(f"  服务名称: {service_name}")
            print(f"  服务类型: {Config.MDNS_SERVICE_TYPE}")
            
            self.zeroconf = Zeroconf()
            
            self.service_info = ServiceInfo(
                type_=Config.MDNS_SERVICE_TYPE,
                name=f"{service_name}.{Config.MDNS_SERVICE_TYPE}",
                addresses=[socket.inet_aton(local_ip)],
                port=Config.WEBSOCKET_PORT,
                properties={
                    'version': '1.0',
                    'platform': platform.system().lower(),
                },
                server=f"{sanitized_name}.local.",
            )
            
            self.zeroconf.register_service(self.service_info)
            self.is_running = True
            
            print(f"mDNS 服务已启动成功")
            print(f"  IP 地址: {local_ip}")
            print(f"  端口: {Config.WEBSOCKET_PORT}")
            
            return True
            
        except OSError as e:
            print(f"启动 mDNS 服务失败 (网络错误): {e}")
            print(f"  错误类型: {type(e).__name__}")
            if "10054" in str(e) or "ConnectionResetError" in str(type(e)):
                print("  可能原因: Windows 防火墙阻止了 mDNS 多播端口 (5353/UDP)")
                print("  解决方法: 请在 Windows 防火墙中允许 Python 通过防火墙")
            traceback.print_exc()
            return False
        except Exception as e:
            print(f"启动 mDNS 服务失败: {e}")
            print(f"  错误类型: {type(e).__name__}")
            traceback.print_exc()
            return False
    
    def stop(self):
        """停止 mDNS 服务"""
        if self.zeroconf and self.service_info:
            try:
                self.zeroconf.unregister_service(self.service_info)
                self.zeroconf.close()
                print("mDNS 服务已停止")
            except Exception as e:
                print(f"停止 mDNS 服务时出错: {e}")
            finally:
                self.is_running = False
                self.zeroconf = None
                self.service_info = None


# 单例实例
_discovery_service = None

def get_discovery_service() -> DiscoveryService:
    """获取发现服务单例"""
    global _discovery_service
    if _discovery_service is None:
        _discovery_service = DiscoveryService()
    return _discovery_service
