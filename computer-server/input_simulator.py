import time
import platform
import subprocess
import sys
import json
import os
import ctypes
from ctypes import wintypes

INPUT_MODE_CLIPBOARD = "clipboard"
INPUT_MODE_KEYBOARD = "keyboard"
INPUT_MODE_SENDKEYS = "sendkeys"
INPUT_MODE_SENDINPUT = "sendinput"
INPUT_MODE_KEYBD_EVENT = "keybd_event"
INPUT_MODE_CLIPBOARD_SENDKEYS = "clipboard_sendkeys"
INPUT_MODE_CLIPBOARD_DELAYED = "clipboard_delayed"
INPUT_MODE_UNICODE = "unicode"

INPUT_MODES = [
    (INPUT_MODE_CLIPBOARD, "剪贴板粘贴 (pynput/pyautogui)"),
    (INPUT_MODE_KEYBOARD, "模拟键盘输入 (pynput)"),
    (INPUT_MODE_SENDKEYS, "SendKeys (PowerShell)"),
    (INPUT_MODE_SENDINPUT, "SendInput (Win32 API)"),
    (INPUT_MODE_KEYBD_EVENT, "keybd_event (Win32 API)"),
    (INPUT_MODE_CLIPBOARD_SENDKEYS, "剪贴板 + SendKeys"),
    (INPUT_MODE_CLIPBOARD_DELAYED, "剪贴板粘贴 (延迟版)"),
    (INPUT_MODE_UNICODE, "Unicode 字符输入"),
]

class InputSimulator:
    """键盘输入模拟器"""
    
    def __init__(self):
        self.system = platform.system()
        self.keyboard = None
        
        # 输入模式: clipboard (剪贴板粘贴) 或 keyboard (模拟键盘)
        self.input_mode = INPUT_MODE_CLIPBOARD
        self._load_input_mode()
        
        # 尝试导入 pynput
        try:
            from pynput.keyboard import Controller
            self.keyboard = Controller()
            print("使用 pynput 作为输入后端")
        except ImportError:
            print("警告: pynput 未安装，尝试使用 pyautogui")
            self.keyboard = None
        
        # 尝试导入 pyautogui 作为备选
        self.pyautogui = None
        try:
            import pyautogui
            self.pyautogui = pyautogui
            # 设置安全模式
            self.pyautogui.FAILSAFE = True
            print("pyautogui 已加载作为备选方案")
        except ImportError:
            print("警告: pyautogui 未安装")
        
        # 尝试导入 pyperclip 用于剪贴板操作
        self.pyperclip = None
        try:
            import pyperclip
            self.pyperclip = pyperclip
            print("pyperclip 已加载用于剪贴板操作")
        except ImportError:
            print("警告: pyperclip 未安装，将使用 PowerShell 操作剪贴板")
        
        # Windows 下隐藏子进程窗口的配置
        self._startupinfo = None
        if self.system == "Windows":
            self._startupinfo = subprocess.STARTUPINFO()
            self._startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            self._startupinfo.wShowWindow = subprocess.SW_HIDE
        
        # 保存原始剪贴板内容
        self._original_clipboard = None
    
    def _get_config_path(self) -> str:
        """获取配置文件路径"""
        if self.system == "Windows":
            config_dir = os.path.join(os.environ.get('APPDATA', ''), '.typing_assistant')
        else:
            config_dir = os.path.expanduser('~/.typing_assistant')
        
        os.makedirs(config_dir, exist_ok=True)
        return os.path.join(config_dir, 'input_config.json')
    
    def _load_input_mode(self):
        """加载输入模式配置"""
        try:
            config_path = self._get_config_path()
            if os.path.exists(config_path):
                with open(config_path, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.input_mode = config.get('input_mode', INPUT_MODE_CLIPBOARD)
                    print(f"加载输入模式配置: {self.input_mode}")
        except Exception as e:
            print(f"加载输入模式配置失败: {e}")
            self.input_mode = INPUT_MODE_CLIPBOARD
    
    def _save_input_mode(self):
        """保存输入模式配置"""
        try:
            config_path = self._get_config_path()
            with open(config_path, 'w', encoding='utf-8') as f:
                json.dump({'input_mode': self.input_mode}, f)
            print(f"保存输入模式配置: {self.input_mode}")
        except Exception as e:
            print(f"保存输入模式配置失败: {e}")
    
    def set_input_mode(self, mode: str):
        """设置输入模式"""
        valid_modes = [m[0] for m in INPUT_MODES]
        if mode in valid_modes:
            self.input_mode = mode
            self._save_input_mode()
            print(f"输入模式已切换为: {self.get_input_mode_display()}")
        else:
            print(f"无效的输入模式: {mode}")
    
    def get_input_mode(self) -> str:
        """获取当前输入模式"""
        return self.input_mode
    
    def get_input_mode_display(self) -> str:
        """获取输入模式显示名称"""
        for mode_id, mode_name in INPUT_MODES:
            if mode_id == self.input_mode:
                return mode_name
        return "未知模式"
    
    def get_all_modes(self):
        """获取所有可用的输入模式"""
        return INPUT_MODES
    
    def type_text(self, text: str) -> bool:
        """
        模拟键盘输入文字
        
        Args:
            text: 要输入的文字
            
        Returns:
            bool: 是否输入成功
        """
        try:
            if not text:
                print("输入文字为空，跳过")
                return False
            
            print(f"准备输入文字 (模式: {self.get_input_mode_display()}): {text[:30]}{'...' if len(text) > 30 else ''}")
            
            time.sleep(0.3)
            
            if self.system == "Windows":
                return self._type_text_windows_mode(text)
            
            if self.keyboard:
                try:
                    self.keyboard.type(text)
                    print("使用 pynput 输入成功")
                    return True
                except Exception as e:
                    print(f"pynput 输入失败: {e}")
            
            if self.pyautogui:
                try:
                    self.pyautogui.typewrite(text, interval=0.01)
                    print("使用 pyautogui 输入成功")
                    return True
                except Exception as e:
                    print(f"pyautogui 输入失败: {e}")
            
            if self.system == "Darwin":
                return self._type_text_macos(text)
            elif self.system == "Linux":
                return self._type_text_linux(text)
            
            print("没有可用的输入方法")
            return False
            
        except Exception as e:
            print(f"输入文字失败: {e}")
            import traceback
            traceback.print_exc()
            return False
    
    def _type_text_windows_mode(self, text: str) -> bool:
        """Windows 系统根据模式选择输入方式"""
        mode = self.input_mode
        
        if mode == INPUT_MODE_CLIPBOARD:
            return self._paste_via_clipboard_windows(text)
        
        elif mode == INPUT_MODE_KEYBOARD:
            if self.keyboard:
                try:
                    self.keyboard.type(text)
                    print("使用模拟键盘输入成功 (pynput)")
                    return True
                except Exception as e:
                    print(f"pynput 输入失败: {e}")
            return False
        
        elif mode == INPUT_MODE_SENDKEYS:
            return self._type_via_sendkeys(text)
        
        elif mode == INPUT_MODE_SENDINPUT:
            return self._type_via_sendinput(text)
        
        elif mode == INPUT_MODE_KEYBD_EVENT:
            return self._type_via_keybd_event(text)
        
        elif mode == INPUT_MODE_CLIPBOARD_SENDKEYS:
            return self._paste_via_sendkeys(text)
        
        elif mode == INPUT_MODE_CLIPBOARD_DELAYED:
            return self._paste_via_clipboard_delayed(text)
        
        elif mode == INPUT_MODE_UNICODE:
            return self._type_via_unicode(text)
        
        else:
            print(f"未知输入模式: {mode}")
            return False
    
    def _type_via_sendkeys(self, text: str) -> bool:
        """使用 PowerShell SendKeys 输入文字"""
        try:
            escaped_text = text.replace('"', '`"').replace('{', '{{}').replace('}', '{}}')
            script = f'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("{escaped_text}")'
            result = subprocess.run(
                ['powershell', '-Command', script],
                capture_output=True,
                text=True,
                timeout=10,
                startupinfo=self._startupinfo,
                creationflags=subprocess.CREATE_NO_WINDOW if self.system == "Windows" else 0
            )
            if result.returncode == 0:
                print("使用 SendKeys 输入成功")
                return True
            else:
                print(f"SendKeys 错误: {result.stderr}")
                return False
        except Exception as e:
            print(f"SendKeys 输入失败: {e}")
            return False
    
    def _type_via_sendinput(self, text: str) -> bool:
        """使用 Win32 SendInput API 输入文字"""
        try:
            user32 = ctypes.windll.user32
            
            KEYEVENTF_UNICODE = 0x0004
            KEYEVENTF_KEYUP = 0x0002
            
            INPUT_KEYBOARD = 1
            
            class KEYBDINPUT(ctypes.Structure):
                _fields_ = [
                    ("wVk", wintypes.WORD),
                    ("wScan", wintypes.WORD),
                    ("dwFlags", wintypes.DWORD),
                    ("time", wintypes.DWORD),
                    ("dwExtraInfo", ctypes.POINTER(ctypes.c_ulong)),
                ]
            
            class INPUT(ctypes.Structure):
                _fields_ = [
                    ("type", wintypes.DWORD),
                    ("ki", KEYBDINPUT),
                    ("padding", ctypes.c_ubyte * 8),
                ]
            
            for char in text:
                char_code = ord(char)
                
                inp = INPUT()
                inp.type = INPUT_KEYBOARD
                inp.ki.wVk = 0
                inp.ki.wScan = char_code
                inp.ki.dwFlags = KEYEVENTF_UNICODE
                inp.ki.time = 0
                inp.ki.dwExtraInfo = None
                
                user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(inp))
                
                inp.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
                user32.SendInput(1, ctypes.byref(inp), ctypes.sizeof(inp))
                
                time.sleep(0.001)
            
            print("使用 SendInput 输入成功")
            return True
        except Exception as e:
            print(f"SendInput 输入失败: {e}")
            return False
    
    def _type_via_keybd_event(self, text: str) -> bool:
        """使用 Win32 keybd_event API 输入文字"""
        try:
            user32 = ctypes.windll.user32
            
            KEYEVENTF_UNICODE = 0x0004
            KEYEVENTF_KEYUP = 0x0002
            
            for char in text:
                char_code = ord(char)
                
                user32.keybd_event(0, char_code, KEYEVENTF_UNICODE, 0)
                user32.keybd_event(0, char_code, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, 0)
                
                time.sleep(0.001)
            
            print("使用 keybd_event 输入成功")
            return True
        except Exception as e:
            print(f"keybd_event 输入失败: {e}")
            return False
    
    def _paste_via_sendkeys(self, text: str) -> bool:
        """剪贴板 + SendKeys 粘贴"""
        try:
            if self.pyperclip:
                self.pyperclip.copy(text)
            else:
                escaped_text = text.replace("'", "''")
                set_clipboard_script = f"Set-Clipboard -Value '{escaped_text}'"
                subprocess.run(
                    ['powershell', '-Command', set_clipboard_script],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    startupinfo=self._startupinfo,
                    creationflags=subprocess.CREATE_NO_WINDOW if self.system == "Windows" else 0
                )
            
            time.sleep(0.1)
            
            script = 'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("^v")'
            result = subprocess.run(
                ['powershell', '-Command', script],
                capture_output=True,
                text=True,
                timeout=10,
                startupinfo=self._startupinfo,
                creationflags=subprocess.CREATE_NO_WINDOW if self.system == "Windows" else 0
            )
            
            if result.returncode == 0:
                print("使用剪贴板 + SendKeys 粘贴成功")
                return True
            else:
                print(f"SendKeys 粘贴错误: {result.stderr}")
                return False
        except Exception as e:
            print(f"剪贴板 + SendKeys 粘贴失败: {e}")
            return False
    
    def _paste_via_clipboard_delayed(self, text: str) -> bool:
        """剪贴板粘贴 (延迟版，适用于某些特殊控件)"""
        try:
            if self.pyperclip:
                self.pyperclip.copy(text)
            else:
                escaped_text = text.replace("'", "''")
                set_clipboard_script = f"Set-Clipboard -Value '{escaped_text}'"
                subprocess.run(
                    ['powershell', '-Command', set_clipboard_script],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    startupinfo=self._startupinfo,
                    creationflags=subprocess.CREATE_NO_WINDOW if self.system == "Windows" else 0
                )
            
            time.sleep(0.3)
            
            if self.keyboard:
                from pynput.keyboard import Key
                self.keyboard.press(Key.ctrl)
                time.sleep(0.05)
                self.keyboard.press('v')
                time.sleep(0.1)
                self.keyboard.release('v')
                time.sleep(0.05)
                self.keyboard.release(Key.ctrl)
                print("使用延迟剪贴板粘贴成功")
                return True
            
            if self.pyautogui:
                time.sleep(0.1)
                self.pyautogui.hotkey('ctrl', 'v')
                print("使用延迟剪贴板粘贴成功 (pyautogui)")
                return True
            
            return False
        except Exception as e:
            print(f"延迟剪贴板粘贴失败: {e}")
            return False
    
    def _type_via_unicode(self, text: str) -> bool:
        """使用 Unicode 字符输入 (Alt+Numpad 方式)"""
        try:
            user32 = ctypes.windll.user32
            
            VK_MENU = 0x12
            KEYEVENTF_KEYUP = 0x0002
            
            for char in text:
                char_code = ord(char)
                
                user32.keybd_event(VK_MENU, 0, 0, 0)
                
                num_str = str(char_code)
                for digit in num_str:
                    vk_code = 0x60 + int(digit)
                    user32.keybd_event(vk_code, 0, 0, 0)
                    user32.keybd_event(vk_code, 0, KEYEVENTF_KEYUP, 0)
                    time.sleep(0.01)
                
                user32.keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, 0)
                time.sleep(0.02)
            
            print("使用 Unicode 输入成功")
            return True
        except Exception as e:
            print(f"Unicode 输入失败: {e}")
            return False
    
    def _paste_via_clipboard_windows(self, text: str) -> bool:
        """
        Windows 系统使用剪贴板粘贴方式输入文字
        
        Args:
            text: 要输入的文字
            
        Returns:
            bool: 是否输入成功
        """
        try:
            # 保存当前剪贴板内容
            self._original_clipboard = None
            if self.pyperclip:
                try:
                    self._original_clipboard = self.pyperclip.paste()
                except Exception:
                    pass
            
            # 将文字复制到剪贴板
            if self.pyperclip:
                try:
                    self.pyperclip.copy(text)
                except Exception as e:
                    print(f"pyperclip 设置剪贴板失败: {e}")
                    return False
            else:
                # 使用 PowerShell 作为备选（隐藏窗口）
                escaped_text = text.replace("'", "''")
                set_clipboard_script = f"Set-Clipboard -Value '{escaped_text}'"
                result = subprocess.run(
                    ['powershell', '-Command', set_clipboard_script],
                    capture_output=True,
                    text=True,
                    timeout=5,
                    startupinfo=self._startupinfo,
                    creationflags=subprocess.CREATE_NO_WINDOW if self.system == "Windows" else 0
                )
                
                if result.returncode != 0:
                    print(f"设置剪贴板失败: {result.stderr}")
                    return False
            
            # 等待剪贴板更新
            time.sleep(0.1)
            
            # 模拟 Ctrl+V 粘贴
            if self.keyboard:
                try:
                    from pynput.keyboard import Key
                    self.keyboard.press(Key.ctrl)
                    self.keyboard.press('v')
                    time.sleep(0.05)
                    self.keyboard.release('v')
                    self.keyboard.release(Key.ctrl)
                    print("剪贴板粘贴成功")
                    return True
                except Exception as e:
                    print(f"剪贴板粘贴失败: {e}")
            
            if self.pyautogui:
                try:
                    self.pyautogui.hotkey('ctrl', 'v')
                    print("使用剪贴板粘贴成功 (pyautogui)")
                    return True
                except Exception as e:
                    print(f"pyautogui 粘贴失败: {e}")
            
            print("无法执行粘贴操作")
            return False
                
        except Exception as e:
            print(f"剪贴板粘贴失败: {e}")
            return False
        finally:
            # 尝试恢复原始剪贴板内容（延迟恢复，避免影响粘贴操作）
            if self._original_clipboard is not None:
                try:
                    time.sleep(0.2)
                    if self.pyperclip:
                        self.pyperclip.copy(self._original_clipboard)
                except Exception:
                    pass
    
    def _type_text_macos(self, text: str) -> bool:
        """使用 AppleScript 在 macOS 上输入文字"""
        try:
            # 使用 osascript 输入文字
            escaped_text = text.replace('"', '\\"').replace('\\', '\\\\')
            script = f'tell application "System Events" to keystroke "{escaped_text}"'
            result = subprocess.run(
                ['osascript', '-e', script],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                print("使用 AppleScript 输入成功")
                return True
            else:
                print(f"AppleScript 错误: {result.stderr}")
                return False
        except Exception as e:
            print(f"macOS 输入失败: {e}")
            return False
    
    def _type_text_linux(self, text: str) -> bool:
        """使用 xdotool 在 Linux 上输入文字"""
        try:
            result = subprocess.run(
                ['xdotool', 'type', text],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                print("使用 xdotool 输入成功")
                return True
            else:
                print(f"xdotool 错误: {result.stderr}")
                return False
        except FileNotFoundError:
            print("xdotool 未安装，请运行: sudo apt-get install xdotool")
            return False
        except Exception as e:
            print(f"Linux 输入失败: {e}")
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
            # 使用 pynput
            if self.keyboard:
                from pynput.keyboard import Key
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
            
            # 使用 pyautogui 作为备选
            if self.pyautogui:
                key_map = {
                    'enter': 'return',
                    'tab': 'tab',
                    'space': 'space',
                    'backspace': 'backspace',
                    'delete': 'delete',
                    'esc': 'esc',
                    'up': 'up',
                    'down': 'down',
                    'left': 'left',
                    'right': 'right',
                }
                if key_name.lower() in key_map:
                    self.pyautogui.press(key_map[key_name.lower()])
                    return True
            
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
            if self.pyautogui:
                self.pyautogui.hotkey(*keys)
                return True
            
            if self.keyboard:
                from pynput.keyboard import Key
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
            
            return False
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


# 测试代码
if __name__ == "__main__":
    print("测试输入模拟器...")
    print("请在 3 秒内点击一个文本输入框...")
    time.sleep(3)
    
    sim = get_simulator()
    result = sim.type_text("Hello 世界！测试输入。")
    print(f"测试结果: {'成功' if result else '失败'}")
