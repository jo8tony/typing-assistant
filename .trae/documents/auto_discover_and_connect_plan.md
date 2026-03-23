# 自动发现与自动连接功能实现计划

## 需求概述
实现手机端 App 自动搜索局域网中所有后端服务供用户选择，如果局域网中只有一个服务端，则自动连接这个服务端。

## 当前状态分析

### 已有功能
1. **mDNS 服务发现** (`discovery_service.dart`): 已实现基于 mDNS 的局域网服务发现
2. **WebSocket 连接** (`websocket_service.dart`): 已实现 WebSocket 连接管理
3. **自动连接逻辑** (`home_screen.dart`): 已有简单的自动连接逻辑，但不够完善
4. **连接对话框** (`home_screen.dart`): 支持手动输入 IP 连接

### 现有问题
1. 当前自动连接逻辑只连接第一个发现的服务，没有展示选择列表
2. 没有区分"只有一个服务自动连接"和"多个服务让用户选择"的场景
3. 连接对话框没有展示已发现的服务列表

## 实现方案

### 阶段一：增强服务发现与自动连接逻辑

#### 1.1 修改 `home_screen.dart` 中的 `_initDiscovery()` 方法
**位置**: `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart` (第 126-148 行)

**修改内容**:
- 增加发现服务计数逻辑
- 如果只有一个服务，自动连接
- 如果有多个服务，弹出选择对话框
- 如果没有服务，保持当前状态（显示手动连接提示）

#### 1.2 新增自动连接状态管理
**位置**: `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart`

**新增状态变量**:
```dart
bool _hasAutoConnected = false;  // 标记是否已经尝试过自动连接
bool _isShowingServerList = false;  // 标记是否正在显示服务器列表
```

### 阶段二：新增服务选择对话框

#### 2.1 创建服务选择对话框方法 `_showServerSelectionDialog()`
**位置**: `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart`

**功能**:
- 显示发现的电脑列表
- 每个电脑显示：名称、IP、平台图标
- 支持点击选择连接
- 支持下拉刷新重新搜索
- 支持手动输入 IP 选项

**UI 设计**:
```
┌─────────────────────────────┐
│  选择电脑          [关闭]    │
├─────────────────────────────┤
│  发现了 2 台电脑：            │
│                             │
│  ┌─────────────────────┐   │
│  │ 💻 电脑1            │   │
│  │    192.168.1.100   │   │
│  │    [连接]           │   │
│  └─────────────────────┘   │
│                             │
│  ┌─────────────────────┐   │
│  │ 💻 电脑2            │   │
│  │    192.168.1.101   │   │
│  │    [连接]           │   │
│  └─────────────────────┘   │
│                             │
│  ─────────────────────     │
│  [+] 手动输入 IP 地址       │
└─────────────────────────────┘
```

### 阶段三：增强连接对话框

#### 3.1 修改 `_showConnectionDialog()` 方法
**位置**: `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart` (第 424 行开始)

**新增内容**:
- 在对话框中显示已发现的服务列表
- 如果没有手动输入 IP，优先显示发现的服务
- 保持原有手动输入功能

### 阶段四：添加连接提示UI

#### 4.1 在主界面添加发现状态提示
**位置**: `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart` 的 `build` 方法

**新增内容**:
- 在未连接状态下，显示"正在搜索局域网中的电脑..."
- 发现服务后显示"发现 X 台电脑"
- 自动连接成功后隐藏提示

## 详细实现步骤

### 步骤 1: 修改 `_initDiscovery()` 方法
```dart
Future<void> _initDiscovery() async {
  await _discoveryService.startDiscovery();

  // 监听发现的电脑
  _discoveryService.computersStream.listen((computers) {
    if (!mounted) return;
    
    final wsService = context.read<WebSocketService>();
    
    // 如果已经连接或正在连接，不处理
    if (wsService.connectionModel.isConnected || 
        wsService.connectionModel.isConnecting) {
      return;
    }
    
    // 如果已经自动连接过，不再处理
    if (_hasAutoConnected) return;
    
    if (computers.isEmpty) {
      // 没有发现服务，不处理
      return;
    }
    
    // 标记已经尝试过自动连接
    _hasAutoConnected = true;
    
    if (computers.length == 1) {
      // 只有一个服务，自动连接
      debugPrint('发现唯一服务，自动连接: ${computers.first.ip}');
      wsService.connect(computers.first, autoReconnect: true);
      _showSnackBar('已自动连接到 ${computers.first.name}', isError: false);
    } else {
      // 多个服务，显示选择对话框
      debugPrint('发现多个服务，显示选择对话框: ${computers.length} 个');
      _showServerSelectionDialog(computers);
    }
  });
}
```

### 步骤 2: 新增 `_showServerSelectionDialog()` 方法
```dart
void _showServerSelectionDialog(List<DiscoveredComputer> computers) {
  if (_isShowingServerList) return;  // 避免重复显示
  _isShowingServerList = true;
  
  showDialog(
    context: context,
    barrierDismissible: false,  // 必须选择或关闭
    builder: (context) => AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('选择电脑')),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _isShowingServerList = false;
              Navigator.pop(context);
            },
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('发现了 ${computers.length} 台电脑：'),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: computers.length,
                itemBuilder: (context, index) {
                  final computer = computers[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        computer.platform == 'macos' 
                            ? Icons.apple 
                            : Icons.computer,
                      ),
                      title: Text(computer.name),
                      subtitle: Text(computer.ip),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          _isShowingServerList = false;
                          Navigator.pop(context);
                          
                          final wsService = context.read<WebSocketService>();
                          final success = await wsService.connect(
                            computer, 
                            autoReconnect: true,
                          );
                          
                          if (success && mounted) {
                            _showSnackBar(
                              '已连接到 ${computer.name}', 
                              isError: false,
                            );
                          } else if (mounted) {
                            final errorMsg = wsService.connectionModel.errorMessage;
                            _showSnackBar(errorMsg.isNotEmpty ? errorMsg : '连接失败');
                          }
                        },
                        child: const Text('连接'),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('手动输入 IP 地址'),
              onTap: () {
                _isShowingServerList = false;
                Navigator.pop(context);
                _showConnectionDialog();
              },
            ),
          ],
        ),
      ),
    ),
  ).then((_) {
    _isShowingServerList = false;
  });
}
```

### 步骤 3: 在连接对话框中添加发现的服务列表
在 `_showConnectionDialog()` 的 `content` 部分，在 IP 输入框上方添加：
```dart
// 显示已发现的服务列表
StreamBuilder<List<DiscoveredComputer>>(
  stream: _discoveryService.computersStream,
  initialData: _discoveryService.discoveredComputers,
  builder: (context, snapshot) {
    final computers = snapshot.data ?? [];
    if (computers.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '发现的电脑',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...computers.map((computer) => ListTile(
          dense: true,
          leading: const Icon(Icons.computer),
          title: Text(computer.name),
          subtitle: Text(computer.ip),
          trailing: TextButton(
            onPressed: () {
              ipController.text = computer.ip;
              setDialogState(() {});
            },
            child: const Text('使用'),
          ),
        )),
        const Divider(),
      ],
    );
  },
),
```

### 步骤 4: 添加发现状态提示
在 `build` 方法的 body 中，输入框上方添加：
```dart
// 在未连接状态下显示发现状态
Consumer<WebSocketService>(
  builder: (context, wsService, child) {
    if (wsService.connectionModel.isConnected) {
      return const SizedBox.shrink();
    }
    
    return StreamBuilder<List<DiscoveredComputer>>(
      stream: _discoveryService.computersStream,
      initialData: _discoveryService.discoveredComputers,
      builder: (context, snapshot) {
        final computers = snapshot.data ?? [];
        
        if (computers.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '正在搜索局域网中的电脑...',
                    style: TextStyle(color: Colors.blue),
                  ),
                ),
              ],
            ),
          );
        }
        
        return Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '发现 ${computers.length} 台电脑',
                  style: const TextStyle(color: Colors.green),
                ),
              ),
              if (computers.length > 1)
                TextButton(
                  onPressed: () => _showServerSelectionDialog(computers),
                  child: const Text('选择'),
                ),
            ],
          ),
        );
      },
    );
  },
),
```

## 文件修改清单

| 文件路径 | 修改类型 | 修改内容 |
|---------|---------|---------|
| `/Users/liaopeng/Desktop/projs/print/mobile_app/lib/screens/home_screen.dart` | 修改 | 1. 添加 `_hasAutoConnected` 和 `_isShowingServerList` 状态变量<br>2. 修改 `_initDiscovery()` 方法<br>3. 新增 `_showServerSelectionDialog()` 方法<br>4. 在 `_showConnectionDialog()` 中添加发现的服务列表<br>5. 在 `build()` 中添加发现状态提示UI |

## 用户体验流程

### 场景 1: 局域网中只有一个服务端
1. App 启动
2. 开始搜索服务
3. 发现 1 个服务
4. **自动连接**，显示"已自动连接到 XXX"
5. 用户可以直接开始使用

### 场景 2: 局域网中有多个服务端
1. App 启动
2. 开始搜索服务
3. 发现多个服务
4. **弹出选择对话框**，显示所有发现的电脑
5. 用户点击选择要连接的电脑
6. 连接成功后关闭对话框

### 场景 3: 没有搜索到服务
1. App 启动
2. 开始搜索服务
3. 显示"正在搜索局域网中的电脑..."
4. 用户可以点击"连接设置"手动输入 IP

### 场景 4: 用户想切换连接
1. 点击"连接设置"
2. 对话框中显示已发现的服务列表
3. 用户可以选择其他服务或手动输入 IP

## 测试要点

1. **单服务自动连接**: 确保只有一个服务时自动连接
2. **多服务选择**: 确保多个服务时显示选择对话框
3. **无服务提示**: 确保没有服务时显示搜索提示
4. **手动输入**: 确保手动输入 IP 功能仍然可用
5. **重复连接**: 确保不会重复显示选择对话框
6. **连接失败**: 确保连接失败时显示错误信息
7. **服务变化**: 确保服务列表实时更新
