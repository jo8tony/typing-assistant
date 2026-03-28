@echo off
chcp 65001 >nul
echo ========================================
echo   打字助手 Windows 构建脚本
echo ========================================
echo.

echo [1/5] 检查 Python 环境...
python --version
if errorlevel 1 (
    echo 错误: 未找到 Python，请先安装 Python 3.9+
    pause
    exit /b 1
)

echo.
echo [2/5] 安装依赖...
pip install -r requirements.txt
if errorlevel 1 (
    echo 错误: 依赖安装失败
    pause
    exit /b 1
)

echo.
echo [3/5] 转换图标格式...
python convert_icon.py
if errorlevel 1 (
    echo 警告: 图标转换失败，将使用默认图标
)

echo.
echo [4/5] 打包应用程序...
pyinstaller typing_assistant.spec --clean
if errorlevel 1 (
    echo 错误: 打包失败
    pause
    exit /b 1
)

echo.
echo [5/5] 创建安装程序...
if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" (
    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" setup.iss
    echo 安装程序创建完成！
    echo 安装程序位于: dist\打字助手-Setup-1.0.0.exe
) else if exist "C:\Program Files\Inno Setup 6\ISCC.exe" (
    "C:\Program Files\Inno Setup 6\ISCC.exe" setup.iss
    echo 安装程序创建完成！
    echo 安装程序位于: dist\打字助手-Setup-1.0.0.exe
) else (
    echo 警告: 未检测到 Inno Setup 6，跳过安装程序创建
    echo 请从 https://jrsoftware.org/isdl.php 下载安装 Inno Setup
)

echo.
echo ========================================
echo   构建完成！
echo   可执行文件: dist\打字助手.exe
echo ========================================
echo.

pause
