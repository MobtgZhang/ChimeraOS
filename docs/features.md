# ChimeraOS 特性与技术路线图

## 1. 核心特性

### 1.1 Zig 语言全量实现

整个操作系统从内核到用户态库全部使用 Zig 编写，充分利用 Zig 的优势：

- **无隐藏控制流** — 内核代码行为完全可预测
- **编译期计算 (comptime)** — 根据目标架构自动生成系统调用表、中断向量等
- **C ABI 兼容** — 无缝对接 Darwin 头文件与现有 C 生态
- **显式错误处理** — 杜绝内核中的隐式异常崩溃
- **零开销抽象** — 保证内核的运行时性能

### 1.2 XNU 混合内核架构

采用与 macOS XNU 相同的混合内核设计：

- **Mach 微内核** — 提供 IPC (Port/Message)、Task/Thread、虚拟内存等核心原语
- **BSD 兼容层** — 在 Mach 之上实现 POSIX 标准系统调用接口
- **I/O Kit** — 面向对象的驱动框架，设备树式管理

### 1.3 macOS 二进制兼容

目标是无需修改即可运行 macOS Mach-O 格式的可执行文件：

- Mach-O 解析器 — 解析 Header、Load Command、Segment/Section
- Fat Binary 支持 — 处理多架构通用二进制
- dyld 动态链接 — 符号绑定、ASLR 重定位、延迟绑定

### 1.4 UEFI 原生启动

- UEFI 引导加载器直接生成为 `BOOTX64.efi`
- 支持 Graphics Output Protocol (GOP) 获取帧缓冲
- 标准 UEFI 内存映射交接

### 1.5 完整的内存管理体系

三级内存分配器协作：

| 分配器 | 用途 | 粒度 |
|--------|------|------|
| PMM (页帧分配器) | 物理内存管理 | 4KB 页 |
| Buddy 分配器 | 大块连续内存 | 多页块 |
| Slab 分配器 | 小对象快速分配 | 字节级 |

### 1.6 调试友好

- 串口日志输出（支持 Debug/Release 编译时开关）
- 分级日志系统 (INFO / WARN / ERR / DEBUG)
- 启动画面帧缓冲渲染（Catppuccin Mocha 主题配色）

## 2. 多架构支持

| 架构 | 状态 | 说明 |
|------|------|------|
| x86_64 | **开发中** | 主要开发架构，QEMU 验证 |
| ARM64 (AArch64) | 规划中 | 未来支持 Apple Silicon |

## 3. 技术选型

| 模块 | 方案 | 参考项目 |
|------|------|----------|
| 内核语言 | Zig（全量） | — |
| Mach-O 解析 | Zig 原生实现 | `zig-macho`、LLVM lld |
| 动态链接 | 仿 Apple dyld4 | apple/dyld（开源） |
| ObjC 运行时 | Zig + GNUstep libobjc2 参考 | GNUstep、ObjFW |
| 图形后端 | Vulkan（跨平台） | MoltenVK、Zink |
| POSIX 兼容 | Darwin syscall 表对照 | XNU 源码 |
| 框架重实现 | Zig + ObjC 接口 | Darling、GNUstep |
| 构建系统 | `build.zig` 全平台 | — |

## 4. 开发路线图

### 第一阶段 · 内核基石（已完成）

- [x] UEFI 引导加载器
- [x] 串口日志系统
- [x] GDT / IDT 初始化
- [x] 8259 PIC 中断控制器
- [x] 物理内存管理 (PMM)
- [x] Buddy 分配器
- [x] Slab 分配器
- [x] 帧缓冲启动画面
- [x] Mach VM Map
- [x] Mach Task / Thread
- [x] BSD 系统调用表
- [x] VFS + DevFS
- [x] I/O Kit 注册表
- [x] PCIe 总线扫描
- [x] PIT 定时器（1000 Hz）
- [x] CMOS 实时时钟 (RTC)
- [x] PS/2 键盘驱动（扫描码翻译、修饰键）
- [x] PS/2 鼠标驱动（3 字节数据包解析、绝对坐标）
- [x] GOP 帧缓冲显示驱动
- [x] ATA/IDE 磁盘驱动（PIO 模式）
- [x] AC97 音频驱动（基础初始化）
- [ ] 多核启动 (SMP)
- [ ] 上下文切换
- [ ] Mach IPC 消息传递

### 第二阶段 · 二进制加载与系统调用

- [x] Mach-O 解析器（基础）
- [x] Fat Binary 处理
- [x] Segment 映射
- [ ] dyld 动态链接器
- [ ] Darwin 系统调用映射 (write, exit, mmap ...)
- [ ] libsystem_kernel 包装
- [ ] 最小化 libc 实现
- [ ] launchd PID 1 骨架

### 第三阶段 · POSIX 与运行时

- [ ] VFS 完善 (open, read, write, mmap)
- [ ] APFS 只读挂载
- [ ] libdispatch (GCD)
- [ ] Objective-C Runtime
- [ ] CoreFoundation 基础类型
- [ ] POSIX 信号完整实现
- [ ] 网络栈 (TCP/UDP)

### 第四阶段 · 图形栈与 UI 框架

- [x] 桌面合成器（壁纸、渐变渲染）
- [x] 窗口管理器（macOS 风格标题栏、交通灯按钮、拖拽、Z 序管理）
- [x] macOS 风格菜单栏（Apple 图标、应用名、菜单项、系统时钟）
- [x] macOS 风格 Dock 栏（应用图标、悬停效果、运行指示器）
- [x] 2D 图形引擎（矩形、圆角矩形、圆、直线、渐变、文字渲染）
- [x] 8×16 VGA 位图字体（完整 ASCII 可打印字符）
- [x] macOS 风格主题色板（交通灯、菜单栏、窗口、Dock 等）
- [x] 系统图标集（Apple、Finder、终端、设置、文件夹、文件、信息、电源）
- [x] 鼠标光标渲染（标准箭头光标）
- [x] UI 组件库（按钮、标签、文本输入框）
- [x] 键鼠输入驱动
- [ ] 窗口合成服务器 (Quartz Compositor)
- [ ] Metal → Vulkan 映射层
- [ ] CoreGraphics
- [ ] AppKit 骨架

### 第五阶段 · 完善与生态

- [ ] libxpc 进程间通信
- [ ] 代码签名校验
- [ ] dyld shared cache
- [ ] USB / NVMe 驱动完善
- [ ] SwiftUI 兼容探索

## 5. 与同类项目的区别

| 对比维度 | ChimeraOS | Darling | GNUstep |
|----------|-----------|---------|---------|
| 实现层级 | 完整 OS（内核 + 用户态） | Linux 用户态兼容层 | 仅 Framework 层 |
| 实现语言 | Zig | C/C++ | Objective-C/C |
| 内核 | 自有混合内核 | 依赖 Linux 内核 | 依赖宿主 OS |
| 二进制兼容 | 原生 Mach-O 加载 | syscall 转译 | 需重编译 |
| 目标 | 独立运行 macOS 应用 | 在 Linux 上运行 macOS 应用 | 提供 Cocoa API |
