import threading
import time
from datetime import datetime
from typing import List, Callable, Optional
from collections import deque

class LogManager:
    _instance = None
    _lock = threading.Lock()
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super().__new__(cls)
                    cls._instance._initialized = False
        return cls._instance
    
    def __init__(self):
        if self._initialized:
            return
        self._initialized = True
        self._logs: deque = deque(maxlen=1000)
        self._callbacks: List[Callable[[str], None]] = []
        self._callback_lock = threading.Lock()
        self._original_print = None
    
    def add_callback(self, callback: Callable[[str], None]):
        with self._callback_lock:
            if callback not in self._callbacks:
                self._callbacks.append(callback)
    
    def remove_callback(self, callback: Callable[[str], None]):
        with self._callback_lock:
            if callback in self._callbacks:
                self._callbacks.remove(callback)
    
    def log(self, message: str, level: str = "INFO"):
        timestamp = datetime.now().strftime("%H:%M:%S")
        formatted = f"[{timestamp}] {message}"
        
        self._logs.append(formatted)
        
        with self._callback_lock:
            for callback in self._callbacks:
                try:
                    callback(formatted)
                except Exception:
                    pass
        
        if self._original_print:
            self._original_print(message)
    
    def get_logs(self) -> List[str]:
        return list(self._logs)
    
    def get_recent_logs(self, count: int = 100) -> List[str]:
        logs = list(self._logs)
        return logs[-count:] if len(logs) > count else logs
    
    def clear(self):
        self._logs.clear()
    
    def install_print_hook(self):
        import builtins
        self._original_print = builtins.print
        
        def hooked_print(*args, **kwargs):
            message = ' '.join(str(arg) for arg in args)
            self.log(message)
        
        builtins.print = hooked_print
    
    def restore_print(self):
        if self._original_print:
            import builtins
            builtins.print = self._original_print
            self._original_print = None

def get_log_manager() -> LogManager:
    return LogManager()
