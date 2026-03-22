# GitHub 推送和构建指南

由于当前环境无法直接推送到 GitHub，请按照以下步骤操作：

---

## 方案一：使用 GitHub Token（推荐）

### 步骤 1: 创建 GitHub Token

1. 访问 https://github.com/settings/tokens
2. 点击 "Generate new token (classic)"
3. 选择权限：
   - ✅ repo (完整仓库访问)
4. 点击 "Generate token"
5. **复制生成的 Token**（只显示一次）

### 步骤 2: 使用 Token 推送

```bash
cd /Users/liaopeng/Desktop/projs/print

# 配置使用 Token
# 将 YOUR_TOKEN 替换为你生成的 Token
git remote set-url origin https://YOUR_TOKEN@github.com/jo8tony/typing-assistant.git

# 推送代码
git push -u origin main
```

### 步骤 3: 触发 GitHub Actions 构建

推送成功后，GitHub Actions 会自动开始构建 APK。

---

## 方案二：使用 SSH 密钥

### 步骤 1: 生成 SSH 密钥

```bash
# 生成新的 SSH 密钥
ssh-keygen -t ed25519 -C "your_email@example.com" -f ~/.ssh/github_key

# 添加密钥到 SSH 代理
ssh-add ~/.ssh/github_key
```

### 步骤 2: 添加公钥到 GitHub

1. 复制公钥内容：
```bash
cat ~/.ssh/github_key.pub
```

2. 访问 https://github.com/settings/keys
3. 点击 "New SSH key"
4. 粘贴公钥内容
5. 点击 "Add SSH key"

### 步骤 3: 配置 Git 使用 SSH

```bash
cd /Users/liaopeng/Desktop/projs/print

# 修改远程 URL 为 SSH
git remote set-url origin git@github.com:jo8tony/typing-assistant.git

# 推送代码
git push -u origin main
```

---

## 方案三：手动上传（最简单）

如果命令行推送有问题，可以直接在 GitHub 网页上传：

### 步骤 1: 压缩项目

```bash
cd /Users/liaopeng/Desktop/projs/print

# 删除不需要的文件
rm -rf .git .DS_Store mobile_app/build mobile_app/.dart_tool

# 压缩项目
zip -r typing-assistant-source.zip .
```

### 步骤 2: 在 GitHub 网页上传

1. 访问 https://github.com/jo8tony/typing-assistant
2. 点击 "Add file" → "Upload files"
3. 上传压缩包中的所有文件
4. 点击 "Commit changes"

---

## 方案四：使用 GitHub Desktop

1. 下载 GitHub Desktop: https://desktop.github.com/
2. 登录你的 GitHub 账号
3. 添加本地仓库：`/Users/liaopeng/Desktop/projs/print`
4. 提交并推送更改

---

## 构建 APK

代码推送到 GitHub 后，GitHub Actions 会自动构建 APK。

### 查看构建状态

1. 访问 https://github.com/jo8tony/typing-assistant/actions
2. 查看 "Build APK" 工作流的运行状态
3. 等待构建完成（约 5-10 分钟）

### 下载 APK

构建成功后：

1. 进入 Actions 页面
2. 点击最新的工作流运行
3. 在 "Artifacts" 部分下载 "typing-assistant-apk"
4. 解压下载的文件，得到 `app-release.apk`

---

## 安装 APK

将下载的 APK 安装到手机：

```bash
# 使用 ADB
adb install app-release.apk

# 或手动安装：
# 1. 传输 APK 到手机
# 2. 点击安装
# 3. 允许安装未知来源应用
```

---

## 快速操作清单

### 推荐流程（方案一）：

1. ✅ 访问 https://github.com/settings/tokens 创建 Token
2. ✅ 复制 Token
3. ✅ 在终端执行：
   ```bash
   cd /Users/liaopeng/Desktop/projs/print
   git remote set-url origin https://YOUR_TOKEN@github.com/jo8tony/typing-assistant.git
   git push -u origin main
   ```
4. ✅ 访问 https://github.com/jo8tony/typing-assistant/actions 查看构建
5. ✅ 下载 APK 并安装

---

## 故障排除

### 1. Token 推送失败

检查 Token 权限：
- 确保勾选了 `repo` 权限
- 确保 Token 没有过期

### 2. 构建失败

查看 Actions 日志：
1. 进入 Actions 页面
2. 点击失败的工作流
3. 查看错误信息
4. 根据错误修复代码

### 3. 网络问题

如果 GitHub 访问慢，可以尝试：
- 使用代理
- 使用 GitHub 镜像
- 稍后再试

---

## 需要帮助？

如果遇到问题，请提供：
1. 错误信息截图
2. 你使用的方案
3. 执行到哪一步出错
