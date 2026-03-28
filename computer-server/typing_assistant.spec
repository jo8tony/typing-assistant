# -*- mode: python ; coding: utf-8 -*-
"""
PyInstaller 打包配置
用于将打字助手打包为 Windows 可执行文件
"""

import os
import sys

block_cipher = None

current_dir = os.path.dirname(os.path.abspath(SPEC))

a = Analysis(
    ['gui_main.py'],
    pathex=[current_dir],
    binaries=[],
    datas=[
        ('app_icon.png', '.'),
    ],
    hiddenimports=[
        'pystray._win32',
        'PIL._tkinter_finder',
        'pynput.keyboard._win32',
        'pynput.mouse._win32',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        'tkinter.test',
        'unittest',
        'pydoc',
        'doctest',
        'difflib',
    ],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='打字助手',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon=None,
)
