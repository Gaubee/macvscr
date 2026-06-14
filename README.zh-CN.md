# macvscr

[English](README.md)

一个 macOS 菜单栏工具，用于创建**可自由控制的虚拟显示器**——任意分辨率、HiDPI（Retina `@2x`）、宽高比，以及 iMac 预设。它解决 headless Mac（例如不接显示器的 Mac mini）远程屏幕共享被锁死在 1920×1080 非 HiDPI 的问题。

npm 包：**[macvscr](https://www.npmjs.com/package/macvscr)** · 命令：`macvscr`

## 安装

```bash
npx -y macvscr@latest setup     # 零安装：稳定二进制 + shell alias + 登录 LaunchAgent
# 或
npm install -g macvscr && macvscr setup
```

需要 macOS 13+，Apple Silicon（arm64）。

## 三种运行方式（渐进）

| 模式 | 命令 | 行为 | 停止 |
|---|---|---|---|
| ① 前台 | `macvscr`（默认）/`macvscr run` | 占用终端，打印引导；Ctrl+C 退出 | Ctrl+C |
| ② 后台 | `macvscr run -d` | detached，终端立即返回 | `macvscr stop` |
| ③ 登录服务 | `macvscr setup` | LaunchAgent，登录自启 + 崩溃重启 | `macvscr stop` / `uninstall` |

```bash
macvscr                                  # 前台，默认 3440×1440 @2x
macvscr --width 2560 --ratio 16:9 --hidpi
macvscr run -d --width 2560 --ratio 16:9
macvscr setup --width 2560 --ratio 16:9
macvscr status | stop | start | restart | uninstall
```

## 分辨率模型

输入与显示统一用**逻辑像素**；HiDPI（`@2x`）表示物理面翻倍。

- `2560×1440 @2x` → 逻辑工作区 2560×1440，物理 5120×2880（与 macOS 描述 5K iMac 的方式一致）
- `1920×1080`（关闭 HiDPI）→ 逻辑 = 物理 = 1920×1080

托盘头部同时显示两者，逻辑/物理不再混淆。

## 菜单栏

点击显示器图标：**Presets ▸**（iMac 尺寸合并并带尾标）、**Width ▸ / Height ▸ / Aspect ▸**（各有 `Custom…` 输入对话框）、**HiDPI / Retina @2x**、**Quit**。宽/高/比例联动（宽度为主轴）。切换即实时重建显示器，无需重启。

## Headless / 屏幕共享

1. 在 headless Mac 上运行 `macvscr setup`，从菜单栏选一个预设。
2. 从另一台 Mac 屏幕共享连入，在 **View** 菜单选中该 dummy。
3. 远程会话以所选几何尺寸 + Retina 渲染。

## 原理

- **Swift**（SPM，AppKit）。虚拟显示器走私有 `CGVirtualDisplay*` ObjC 类——它们位于**公开的 CoreGraphics 二进制**内，无需 `dlopen`，**SIP 保持开启**。ObjC 声明放在一个小的 `VSCBridge` target，对 Swift 暴露纯 C API。
- 纯 CLI，无 `.app`。菜单栏托盘应用只能在**登录时**启动（LaunchAgent），不能在开机时（LaunchDaemon 没有 GUI 会话）。
- 内置 arm64 二进制由 CI 重建，经**可信发布（provenance）**发布到 npm。

## 构建

```bash
swift build -c release --arch arm64   # → .build/release/macvscr
.build/release/macvscr --help
```

## 发布（CI）

打 `v*` 标签触发 `.github/workflows/release.yml`（macos-14 runner → 构建 arm64 → `npm publish --provenance`）。

## 验证

```bash
system_profiler SPDisplaysDataType | grep -i virtual
```

MIT 协议。
