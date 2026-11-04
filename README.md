# StatusNav

一个独立实现的 macOS 原生状态栏工具，把电池、网络和音量放进一个动态图标。

- 外环：电池电量，充电显示绿色、低电量显示橙色。
- 中心：Wi-Fi、有线网络或离线状态，充电时显示闪电。
- 底部：四个音量指示点，静音时熄灭。
- 点击图标：查看电池与网络状态、调整音量、静音、切换音频输出设备。
- 右键图标：偏好设置与退出。支持百分比显示、状态颜色、图标大小以及 Dock 实时图标。
- 面板使用原生透明浮层：macOS 26+ 使用 Liquid Glass，更早系统使用毛玻璃；窗口跟随内容高度，屏幕空间不足时可滚动。

## 运行与构建

需要 macOS 13+、Swift 6 / Xcode 16+。当前在 Apple Silicon、macOS 26 SDK 环境开发；其他系统版本尚未实机验证。

```bash
swift run StatusNav
```

生成本机架构的 App（本地 ad-hoc 签名）：

```bash
bash scripts/build-app.sh
open dist/StatusNav.app
```

本地构建未经过 Developer ID 签名或 Apple 公证，适合本机运行，不作为正式分发包。

```bash
swift test
```

## 实现

SwiftUI 提供面板与设置；AppKit 管理菜单栏和 Dock；IOKit 读取电池；Network 与 CoreWLAN 读取连接状态；CoreAudio 读取与控制音频设备。电池和音频使用系统事件，15 秒低频轮询兜底。没有第三方依赖。

`Sources/StatusNavCore` 包含可测试的状态模型；`Sources/StatusNav` 包含系统适配、UI 和图标绘制。

## 当前边界

- 不申请定位权限。macOS 隐藏 Wi-Fi 名称时显示“Wi-Fi 已连接”；通过系统设置切换网络。
- 网络状态表示系统存在可用路径，不保证外部互联网或特定网站可访问。
- HDMI、数字输出等设备可能不支持系统音量或静音；对应控件自动禁用。
- 第一版没有蓝牙设备面板、充电限制控制、全局快捷键和自动更新。
- 系统状态在本机读取，无遥测或统计上报；偏好设置保存在本机 UserDefaults。

仓库：https://github.com/zZzzPpp12/statusNav
