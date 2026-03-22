import socket
import platform
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
            # 创建一个 UDP 套接字来获取本地 IP
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.settimeout(0)
            try:
                # 连接到一个外部地址（不会真正发送数据）
                s.connect(('8.8.8.8', 80))
                ip = s.getsockname()[0]
            except Exception:
                ip = '127.0.0.1'
            finally:
                s.close()
            return ip
        except Exception as e:
            print(f"获取本地 IP 失败: {e}")
            return '127.0.0.1'
    
    def start(self) -> bool:
        """
        启动 mDNS 服务广播
        
        Returns:
            bool: 是否启动成功
        """
        try:
            local_ip = self.get_local_ip()
            
            # 创建 Zeroconf 实例
            self.zeroconf = Zeroconf()
            
            # 创建服务信息
            self.service_info = ServiceInfo(
                type_=Config.MDNS_SERVICE_TYPE,
                name=f"{Config.MDNS_SERVICE_NAME}.{Config.MDNS_SERVICE_TYPE}",
                addresses=[socket.inet_aton(local_ip)],
                port=Config.WEBSOCKET_PORT,
                properties={
                    'version': '1.0',
                    'platform': platform.system().lower(),
                },
                server=f"{platform.node()}.local.",
            )
            
            # 注册服务
            self.zeroconf.register_service(self.service_info)
            self.is_running = True
            
            print(f"mDNS 服务已启动")
            print(f"  服务名称: {Config.MDNS_SERVICE_NAME}")
            print(f"  服务类型: {Config.MDNS_SERVICE_TYPE}")
            print(f"  IP 地址: {local_ip}")
            print(f"  端口: {Config.WEBSOCKET_PORT}")
            
            return True
            
        except Exception as e:
            print(f"启动 mDNS 服务失败: {e}")
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
