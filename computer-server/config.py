import os
import json
import platform
from pathlib import Path

class Config:
    """配置管理类"""

    # 服务器配置
    WEBSOCKET_HOST = "0.0.0.0"
    WEBSOCKET_PORT = 8765

    # LocalSend 风格网络发现配置
    MULTICAST_ADDRESS = "224.0.0.167"
    MULTICAST_PORT = 41317
    MULTICAST_TTL = 1
    DISCOVERY_HTTP_PORT = 41317

    # API 版本
    API_VERSION = "v2"

    # 心跳配置
    HEARTBEAT_INTERVAL = 30  # 秒
    HEARTBEAT_TIMEOUT = 60   # 秒
    
    # 安全配置
    ALLOWED_NETWORKS = [
        "192.168.",
        "10.",
        "172.16.", "172.17.", "172.18.", "172.19.",
        "172.20.", "172.21.", "172.22.", "172.23.",
        "172.24.", "172.25.", "172.26.", "172.27.",
        "172.28.", "172.29.", "172.30.", "172.31.",
        "127.0.0.1",  # 本地回环，用于测试
    ]
    
    # 配置文件路径
    CONFIG_DIR = Path.home() / ".typing_assistant"
    CONFIG_FILE = CONFIG_DIR / "config.json"
    
    @classmethod
    def load(cls):
        """从文件加载配置"""
        if cls.CONFIG_FILE.exists():
            try:
                with open(cls.CONFIG_FILE, 'r', encoding='utf-8') as f:
                    config_data = json.load(f)
                    for key, value in config_data.items():
                        if hasattr(cls, key):
                            setattr(cls, key, value)
            except Exception as e:
                print(f"加载配置文件失败: {e}")
    
    @classmethod
    def save(cls):
        """保存配置到文件"""
        cls.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        config_data = {
            'WEBSOCKET_PORT': cls.WEBSOCKET_PORT,
            'HEARTBEAT_INTERVAL': cls.HEARTBEAT_INTERVAL,
        }
        try:
            with open(cls.CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(config_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存配置文件失败: {e}")
    
    @classmethod
    def is_allowed_ip(cls, ip: str) -> bool:
        """检查 IP 是否允许连接"""
        for network in cls.ALLOWED_NETWORKS:
            if ip.startswith(network):
                return True
        return False
