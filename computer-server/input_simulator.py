import time
import platform
from pynput.keyboard import Controller, Key

class InputSimulator:
    """键盘输入模拟器"""
    
    def __init__(self):
        self.keyboard = Controller()
        self.system = platform.system()
    
    def type_text(self, text: str) -> bool:
        """
        模拟键盘输入文字
        
        Args:
            text: 要输入的文字
            
        Returns:
            bool: 是否输入成功
        """
        try:
            # 添加一个小延迟，确保焦点在正确的窗口
            time.sleep(0.1)
            
            # 使用 pynput 输入文字
            self.keyboard.type(text)
            
            return True
        except Exception as e:
            print(f"输入文字失败: {e}")
            return False
    
    def press_key(self, key_name: str) -> bool:
        """
        按下特定按键
        
        Args:
            key_name: 按键名称 (如 'enter', 'tab', 'space' 等)
            
        Returns:
            bool: 是否成功
        """
        try:
            key_map = {
                'enter': Key.enter,
                'tab': Key.tab,
                'space': Key.space,
                'backspace': Key.backspace,
                'delete': Key.delete,
                'esc': Key.esc,
                'up': Key.up,
                'down': Key.down,
                'left': Key.left,
                'right': Key.right,
            }
            
            if key_name.lower() in key_map:
                self.keyboard.press(key_map[key_name.lower()])
                self.keyboard.release(key_map[key_name.lower()])
                return True
            else:
                print(f"未知的按键: {key_name}")
                return False
        except Exception as e:
            print(f"按键操作失败: {e}")
            return False
    
    def press_hotkey(self, *keys) -> bool:
        """
        按下组合键
        
        Args:
            *keys: 按键名称列表，如 ['ctrl', 'c']
            
        Returns:
            bool: 是否成功
        """
        try:
            key_map = {
                'ctrl': Key.ctrl,
                'alt': Key.alt,
                'shift': Key.shift,
                'cmd': Key.cmd,
                'win': Key.cmd,
            }
            
            key_objects = []
            for key in keys:
                key_lower = key.lower()
                if key_lower in key_map:
                    key_objects.append(key_map[key_lower])
                elif len(key) == 1:
                    key_objects.append(key)
            
            # 按下所有键
            for key in key_objects:
                self.keyboard.press(key)
            
            # 释放所有键 (逆序)
            for key in reversed(key_objects):
                self.keyboard.release(key)
            
            return True
        except Exception as e:
            print(f"组合键操作失败: {e}")
            return False


# 单例实例
_simulator = None

def get_simulator() -> InputSimulator:
    """获取输入模拟器单例"""
    global _simulator
    if _simulator is None:
        _simulator = InputSimulator()
    return _simulator
