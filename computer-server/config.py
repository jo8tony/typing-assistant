import os
import json
import platform
import uuid
from pathlib import Path

class Config:
    """配置管理类"""

    VERSION = "1.0.0"
    PROTOCOL_VERSION = "1.0"

    WEBSOCKET_HOST = "0.0.0.0"
    WEBSOCKET_PORT = 8765

    MULTICAST_ADDRESS = "224.0.0.168"
    MULTICAST_PORT = 53318
    MULTICAST_TTL = 1
    ANNOUNCE_INTERVAL = 2

    HEARTBEAT_INTERVAL = 30
    HEARTBEAT_TIMEOUT = 60

    ALLOWED_NETWORKS = [
        "192.168.",
        "10.",
        "172.16.", "172.17.", "172.18.", "172.19.",
        "172.20.", "172.21.", "172.22.", "172.23.",
        "172.24.", "172.25.", "172.26.", "172.27.",
        "172.28.", "172.29.", "172.30.", "172.31.",
        "127.0.0.1",
    ]

    CONFIG_DIR = Path.home() / ".typing_assistant"
    CONFIG_FILE = CONFIG_DIR / "config.json"

    DEVICE_FINGERPRINT = None
    DEVICE_NAME = None

    @classmethod
    def _generate_fingerprint(cls):
        if cls.DEVICE_FINGERPRINT is None:
            cls.DEVICE_FINGERPRINT = str(uuid.uuid4())
        return cls.DEVICE_FINGERPRINT

    @classmethod
    def get_device_info(cls, name: str = None, ip: str = None) -> dict:
        system = platform.system().lower()
        if system == "darwin":
            device_model = "Mac"
            device_type = "macos"
        elif system == "windows":
            device_model = "Windows PC"
            device_type = "windows"
        elif system == "linux":
            device_model = "Linux PC"
            device_type = "linux"
        else:
            device_model = "Desktop"
            device_type = "desktop"

        device_name = name or cls.DEVICE_NAME or f"打字助手-{platform.node()}"

        return {
            "alias": device_name,
            "version": cls.VERSION,
            "deviceModel": device_model,
            "deviceType": device_type,
            "fingerprint": cls._generate_fingerprint(),
            "port": cls.WEBSOCKET_PORT,
            "protocol": "ws",
            "ip": ip or "0.0.0.0",
            "download": True,
            "announce": True,
        }

    @classmethod
    def load(cls):
        if cls.CONFIG_FILE.exists():
            try:
                with open(cls.CONFIG_FILE, 'r', encoding='utf-8') as f:
                    config_data = json.load(f)
                    for key, value in config_data.items():
                        if hasattr(cls, key) and not key.startswith('_'):
                            setattr(cls, key, value)
            except Exception as e:
                print(f"加载配置文件失败: {e}")

    @classmethod
    def save(cls):
        cls.CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        config_data = {
            'WEBSOCKET_PORT': cls.WEBSOCKET_PORT,
            'HEARTBEAT_INTERVAL': cls.HEARTBEAT_INTERVAL,
            'DEVICE_FINGERPRINT': cls.DEVICE_FINGERPRINT,
            'DEVICE_NAME': cls.DEVICE_NAME,
        }
        try:
            with open(cls.CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(config_data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存配置文件失败: {e}")

    @classmethod
    def is_allowed_ip(cls, ip: str) -> bool:
        for network in cls.ALLOWED_NETWORKS:
            if ip.startswith(network):
                return True
        return False

    @classmethod
    def set_device_name(cls, name: str):
        cls.DEVICE_NAME = name
        cls.save()
