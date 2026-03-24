from zeroconf import Zeroconf, ServiceListener, ServiceBrowser
import time

class TestListener(ServiceListener):
    def add_service(self, zc, type, name):
        print(f"发现服务：{name} (类型：{type})")
        info = zc.get_service_info(type, name)
        if info:
            print(f"  服务器：{info.server}")
            print(f"  地址：{info.addresses}")
            print(f"  端口：{info.port}")
            print(f"  属性：{info.properties}")
        else:
            print(f"  无法获取服务信息")
    
    def remove_service(self, zc, type, name):
        print(f"移除服务：{name}")
    
    def update_service(self, zc, type, name):
        print(f"更新服务：{name}")

# 创建 zeroconf 实例
zeroconf = Zeroconf()

# 创建浏览器
browser = ServiceBrowser(zeroconf, "_typing._tcp.local.", TestListener())

print("开始浏览 _typing._tcp.local. 服务...")
print("等待 15 秒...")

time.sleep(15)

zeroconf.close()
print("完成")
