import time
import platform
import subprocess
import sys

class InputSimulator:
    """键盘输入模拟器"""
    
    def __init__(self):
        self.system = platform.system()
        self.keyboard = None
        
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
        
        # 保存原始剪贴板内容
        self._original_clipboard = None
    
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
            
            print(f"准备输入文字: {text[:30]}{'...' if len(text) > 30 else ''}")
            
            # 添加一个小延迟，让用户有时间切换到目标窗口
            time.sleep(0.3)
            
            # Windows 系统优先使用剪贴板粘贴方式
            if self.system == "Windows":
                if self._paste_via_clipboard_windows(text):
                    return True
                print("剪贴板粘贴失败，尝试其他方式")
            
            # 方法1: 使用 pynput
            if self.keyboard:
                try:
                    self.keyboard.type(text)
                    print("使用 pynput 输入成功")
                    return True
                except Exception as e:
                    print(f"pynput 输入失败: {e}，尝试备选方案")
            
            # 方法2: 使用 pyautogui
            if self.pyautogui:
                try:
                    self.pyautogui.typewrite(text, interval=0.01)
                    print("使用 pyautogui 输入成功")
                    return True
                except Exception as e:
                    print(f"pyautogui 输入失败: {e}")
            
            # 方法3: 使用系统命令 (macOS 使用 osascript)
            if self.system == "Darwin":  # macOS
                return self._type_text_macos(text)
            elif self.system == "Linux":
                return self._type_text_linux(text)
            elif self.system == "Windows":
                return self._type_text_windows(text)
            
            print("没有可用的输入方法")
            return False
            
        except Exception as e:
            print(f"输入文字失败: {e}")
            import traceback
            traceback.print_exc()
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
            try:
                result = subprocess.run(
                    ['powershell', '-Command', 'Get-Clipboard'],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    self._original_clipboard = result.stdout
            except Exception:
                self._original_clipboard = None
            
            # 将文字复制到剪贴板
            escaped_text = text.replace("'", "''")
            set_clipboard_script = f"Set-Clipboard -Value '{escaped_text}'"
            result = subprocess.run(
                ['powershell', '-Command', set_clipboard_script],
                capture_output=True,
                text=True,
                timeout=5
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
                    print("使用剪贴板粘贴成功 (pynput)")
                    return True
                except Exception as e:
                    print(f"pynput 粘贴失败: {e}")
            
            if self.pyautogui:
                try:
                    self.pyautogui.hotkey('ctrl', 'v')
                    print("使用剪贴板粘贴成功 (pyautogui)")
                    return True
                except Exception as e:
                    print(f"pyautogui 粘贴失败: {e}")
            
            # 使用 PowerShell SendKeys 作为最后的备选
            script = 'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("^v")'
            result = subprocess.run(
                ['powershell', '-Command', script],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print("使用剪贴板粘贴成功 (PowerShell)")
                return True
            else:
                print(f"PowerShell 粘贴失败: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"剪贴板粘贴失败: {e}")
            return False
        finally:
            # 尝试恢复原始剪贴板内容（延迟恢复，避免影响粘贴操作）
            if self._original_clipboard is not None:
                try:
                    time.sleep(0.2)
                    escaped_original = self._original_clipboard.replace("'", "''")
                    restore_script = f"Set-Clipboard -Value '{escaped_original}'"
                    subprocess.run(
                        ['powershell', '-Command', restore_script],
                        capture_output=True,
                        text=True,
                        timeout=5
                    )
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
    
    def _type_text_windows(self, text: str) -> bool:
        """使用 PowerShell 在 Windows 上输入文字"""
        try:
            # 使用 PowerShell 的 SendKeys
            escaped_text = text.replace('"', '`"').replace('{', '{{}').replace('}', '{}}')
            script = f'Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait("{escaped_text}")'
            result = subprocess.run(
                ['powershell', '-Command', script],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                print("使用 PowerShell SendKeys 输入成功")
                return True
            else:
                print(f"PowerShell 错误: {result.stderr}")
                return False
        except Exception as e:
            print(f"Windows 输入失败: {e}")
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
