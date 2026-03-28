#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨设备打字助手 - Windows GUI版本
系统托盘应用程序
"""

import sys
import os
import asyncio
import threading
import platform
import queue

if platform.system() == 'Windows':
    import ctypes
    try:
        ctypes.windll.shcore.SetProcessDpiAwareness(1)
    except Exception:
        pass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import pystray
from PIL import Image
import tkinter as tk
from tkinter import ttk, messagebox

from config import Config
from websocket_server import get_server
from discovery_service import get_discovery_service
from log_manager import get_log_manager
from names import get_random_name


class TrayApplication:
    def __init__(self):
        self.icon = None
        self.running = True
        self.server_name = None
        self.root = None
        self.log_window = None
        self.log_text = None
        self.rename_dialog = None
        self.exit_dialog_open = False
        self.log_manager = get_log_manager()
        self.action_queue = queue.Queue()
    
    def _setup_tk_root(self):
        self.root = tk.Tk()
        self.root.withdraw()
        self.root.title("打字助手")
    
    def _load_icon(self) -> Image.Image:
        try:
            if getattr(sys, 'frozen', False):
                base_path = sys._MEIPASS
            else:
                base_path = os.path.dirname(os.path.abspath(__file__))
            
            icon_path = os.path.join(base_path, 'icon.png')
            
            if os.path.exists(icon_path):
                icon = Image.open(icon_path)
                icon = icon.convert('RGBA')
                icon = icon.resize((64, 64), Image.Resampling.LANCZOS)
                return icon
            else:
                print(f"图标文件不存在: {icon_path}")
                return self._create_default_icon()
        except Exception as e:
            print(f"加载图标失败: {e}")
            return self._create_default_icon()
    
    def _create_default_icon(self) -> Image.Image:
        from PIL import ImageDraw
        icon = Image.new('RGBA', (64, 64), (76, 175, 80, 255))
        dc = ImageDraw.Draw(icon)
        dc.ellipse([8, 8, 56, 56], fill=(255, 255, 255, 255))
        dc.text((22, 20), "T", fill=(76, 175, 80, 255))
        return icon
    
    def _get_menu(self) -> pystray.Menu:
        return pystray.Menu(
            pystray.MenuItem(
                lambda text: f"【{self.server_name or '打字助手'}】",
                lambda: None,
                default=True
            ),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("日志", self._queue_show_log),
            pystray.MenuItem("重命名", self._queue_show_rename),
            pystray.Menu.SEPARATOR,
            pystray.MenuItem("退出", self._queue_exit),
        )
    
    def _queue_show_log(self, icon=None, item=None):
        self.action_queue.put('show_log')
    
    def _queue_show_rename(self, icon=None, item=None):
        self.action_queue.put('show_rename')
    
    def _queue_exit(self, icon=None, item=None):
        self.action_queue.put('exit')
    
    def _process_actions(self):
        try:
            while True:
                try:
                    action = self.action_queue.get_nowait()
                    if action == 'show_log':
                        self._show_log_window()
                    elif action == 'show_rename':
                        self._show_rename_dialog()
                    elif action == 'exit':
                        self._do_exit()
                except queue.Empty:
                    break
        except Exception as e:
            print(f"处理动作错误: {e}")
        
        if self.running:
            self.root.after(50, self._process_actions)
    
    def _show_log_window(self):
        if self.log_window is not None:
            try:
                if self.log_window.winfo_exists():
                    self.log_window.lift()
                    self.log_window.focus_force()
                    return
            except tk.TclError:
                self.log_window = None
                self.log_text = None
        
        self.log_window = tk.Toplevel(self.root)
        self.log_window.title("运行日志")
        self.log_window.geometry("700x500")
        self.log_window.minsize(500, 300)
        
        main_frame = ttk.Frame(self.log_window, padding="10")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        toolbar = ttk.Frame(main_frame)
        toolbar.pack(fill=tk.X, pady=(0, 10))
        
        ttk.Label(toolbar, text="服务运行日志", font=('Microsoft YaHei UI', 12, 'bold')).pack(side=tk.LEFT)
        
        ttk.Button(toolbar, text="清空日志", command=self._clear_logs).pack(side=tk.RIGHT, padx=5)
        ttk.Button(toolbar, text="刷新", command=self._load_logs).pack(side=tk.RIGHT, padx=5)
        
        text_frame = ttk.Frame(main_frame)
        text_frame.pack(fill=tk.BOTH, expand=True)
        
        self.log_text = tk.Text(
            text_frame,
            wrap=tk.WORD,
            font=('Consolas', 10),
            bg='#1e1e1e',
            fg='#d4d4d4',
            padx=10,
            pady=10
        )
        
        scrollbar = ttk.Scrollbar(text_frame, orient=tk.VERTICAL, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scrollbar.set)
        
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        self.log_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        
        self._load_logs()
        self.log_manager.add_callback(self._append_log)
        
        def on_close():
            self.log_manager.remove_callback(self._append_log)
            try:
                self.log_window.destroy()
            except Exception:
                pass
            self.log_window = None
            self.log_text = None
        
        self.log_window.protocol("WM_DELETE_WINDOW", on_close)
        self.log_window.focus_force()
    
    def _load_logs(self):
        if self.log_text is None:
            return
        try:
            self.log_text.configure(state='normal')
            self.log_text.delete('1.0', tk.END)
            logs = self.log_manager.get_logs()
            for log in logs:
                self.log_text.insert(tk.END, log + '\n')
            self.log_text.see(tk.END)
            self.log_text.configure(state='disabled')
        except tk.TclError:
            pass
    
    def _append_log(self, log_message: str):
        if self.log_text is None or self.log_window is None:
            return
        try:
            if not self.log_window.winfo_exists():
                return
        except tk.TclError:
            return
        
        def append():
            if self.log_text is None:
                return
            try:
                self.log_text.configure(state='normal')
                self.log_text.insert(tk.END, log_message + '\n')
                self.log_text.see(tk.END)
                self.log_text.configure(state='disabled')
            except tk.TclError:
                pass
        
        try:
            self.log_window.after(0, append)
        except Exception:
            pass
    
    def _clear_logs(self):
        self.log_manager.clear()
        if self.log_text is not None:
            try:
                self.log_text.configure(state='normal')
                self.log_text.delete('1.0', tk.END)
                self.log_text.configure(state='disabled')
            except tk.TclError:
                pass
    
    def _show_rename_dialog(self):
        if self.rename_dialog is not None:
            try:
                if self.rename_dialog.winfo_exists():
                    self.rename_dialog.lift()
                    self.rename_dialog.focus_force()
                    return
            except tk.TclError:
                self.rename_dialog = None
        
        self.rename_dialog = tk.Toplevel(self.root)
        self.rename_dialog.title("重命名服务")
        self.rename_dialog.geometry("400x150")
        self.rename_dialog.resizable(False, False)
        
        self.rename_dialog.update_idletasks()
        screen_width = self.rename_dialog.winfo_screenwidth()
        screen_height = self.rename_dialog.winfo_screenheight()
        x = (screen_width - 400) // 2
        y = (screen_height - 150) // 2
        self.rename_dialog.geometry(f"400x150+{x}+{y}")
        
        main_frame = ttk.Frame(self.rename_dialog, padding="20")
        main_frame.pack(fill=tk.BOTH, expand=True)
        
        ttk.Label(main_frame, text="请输入新的服务名称:", font=('Microsoft YaHei UI', 10)).pack(anchor=tk.W)
        
        name_var = tk.StringVar(value=self.server_name or "")
        entry = ttk.Entry(main_frame, textvariable=name_var, font=('Microsoft YaHei UI', 11))
        entry.pack(fill=tk.X, pady=10)
        entry.select_range(0, tk.END)
        entry.focus_set()
        
        button_frame = ttk.Frame(main_frame)
        button_frame.pack(fill=tk.X, pady=(10, 0))
        
        def on_confirm():
            new_name = name_var.get().strip()
            if new_name:
                self._on_rename(new_name)
                try:
                    self.rename_dialog.destroy()
                except Exception:
                    pass
                self.rename_dialog = None
            else:
                messagebox.showwarning("提示", "名称不能为空", parent=self.rename_dialog)
        
        def on_cancel():
            try:
                self.rename_dialog.destroy()
            except Exception:
                pass
            self.rename_dialog = None
        
        ttk.Button(button_frame, text="确定", command=on_confirm, width=10).pack(side=tk.RIGHT, padx=5)
        ttk.Button(button_frame, text="取消", command=on_cancel, width=10).pack(side=tk.RIGHT, padx=5)
        
        entry.bind('<Return>', lambda e: on_confirm())
        entry.bind('<Escape>', lambda e: on_cancel())
        
        self.rename_dialog.protocol("WM_DELETE_WINDOW", on_cancel)
        self.rename_dialog.grab_set()
        self.rename_dialog.focus_force()
    
    def _on_rename(self, new_name: str):
        self.server_name = new_name
        Config.set_device_name(new_name)
        
        discovery = get_discovery_service()
        if discovery and discovery.is_running:
            discovery.device_info['alias'] = new_name
        
        print(f"服务名称已更新为: {new_name}")
    
    def _do_exit(self):
        if self.exit_dialog_open:
            return
        
        self.exit_dialog_open = True
        
        try:
            result = messagebox.askyesno(
                "确认退出",
                "确定要退出打字助手吗？\n退出后手机将无法连接。",
                parent=self.root
            )
            
            if result:
                self.running = False
                
                server = get_server()
                discovery = get_discovery_service()
                server.stop()
                discovery.stop()
                
                if self.icon:
                    self.icon.stop()
                
                self.root.quit()
        finally:
            self.exit_dialog_open = False
    
    def _run_async_server(self):
        async def run():
            Config.load()
            
            if Config.DEVICE_NAME:
                self.server_name = Config.DEVICE_NAME
            else:
                self.server_name = get_random_name()
                Config.set_device_name(self.server_name)
            
            server = get_server()
            discovery = get_discovery_service()
            
            if not discovery.start(self.server_name):
                print("警告：发现服务启动失败，手机可能无法自动发现电脑")
            
            try:
                await server.start()
            except Exception as e:
                print(f"服务器错误: {e}")
            finally:
                server.stop()
                discovery.stop()
        
        asyncio.run(run())
    
    def run(self):
        self.log_manager.install_print_hook()
        
        server_thread = threading.Thread(target=self._run_async_server, daemon=True)
        server_thread.start()
        
        icon_image = self._load_icon()
        
        self.icon = pystray.Icon(
            'typing_assistant',
            icon_image,
            '打字助手 - 运行中',
            self._get_menu()
        )
        
        def update_tooltip():
            import time
            while self.running:
                try:
                    if self.icon and self.server_name:
                        status = f"{self.server_name} - 运行中"
                        self.icon.title = status
                except Exception:
                    pass
                time.sleep(2)
        
        tooltip_thread = threading.Thread(target=update_tooltip, daemon=True)
        tooltip_thread.start()
        
        tray_thread = threading.Thread(
            target=lambda: self.icon.run(),
            daemon=True
        )
        tray_thread.start()
        
        import time
        time.sleep(0.5)
        
        self._setup_tk_root()
        
        self.root.after(50, self._process_actions)
        
        try:
            self.root.mainloop()
        except Exception as e:
            print(f"Tkinter错误: {e}")
        finally:
            self.running = False
            self.log_manager.restore_print()


def main():
    if platform.system() != 'Windows':
        print("此GUI版本仅支持Windows系统")
        print("请使用 python main.py 运行命令行版本")
        sys.exit(1)
    
    app = TrayApplication()
    app.run()


if __name__ == '__main__':
    main()
