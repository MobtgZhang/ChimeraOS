# ChimeraOS 系统架构文档

## 1. 项目概述

ChimeraOS 是一个使用 **Zig** 语言从零编写的操作系统，目标是在 x86_64 / ARM64 架构上实现 macOS 应用程序的二进制兼容。项目采用与 Apple XNU 类似的混合内核设计，结合 Mach 微内核和 BSD 兼容层，为 Mach-O 格式的可执行文件提供原生运行环境。

## 2. 架构分层

```
┌──────────────────────────────────────────────────────────┐
│                   macOS 应用程序 (.app)                    │
├──────────────────────────────────────────────────────────┤
│  Frameworks 层    AppKit / Foundation / CoreGraphics      │
├──────────────────────────────────────────────────────────┤
│  Runtime 层       dyld 动态链接器 / Objective-C Runtime     │
├──────────────────────────────────────────────────────────┤
│  System Libs     libSystem (libc / libdispatch / libxpc)  │
├──────────────────────────────────────────────────────────┤
│  Kernel          Z-Kernel (Mach IPC + BSD POSIX + IOKit)  │
├──────────────────────────────────────────────────────────┤
│  Hardware        x86_64 / ARM64                           │
└──────────────────────────────────────────────────────────┘
```

## 3. 内核子系统

### 3.1 Mach 微内核层

Mach 层提供操作系统最核心的原语：

| 模块 | 说明 |
|------|------|
| `mach/port.zig` | Mach Port 定义与权限管理，进程间通信的基础端点 |
| `mach/message.zig` | `mach_msg()` 收发实现，支持同步/异步消息传递 |
| `mach/task.zig` | Task（进程抽象），资源容器与地址空间隔离 |
| `mach/thread.zig` | Thread 管理与调度接口 |
| `mach/clock.zig` | Mach 时钟服务，定时器与告警处理 |
| `mach/vm/map.zig` | VM Map，虚拟地址空间映射管理 |
| `mach/vm/object.zig` | VM Object，匿名/文件映射对象 |
| `mach/vm/pager.zig` | 默认分页器 |

### 3.2 BSD 兼容层（POSIX）

BSD 层在 Mach 之上构建 POSIX 标准接口：

| 模块 | 说明 |
|------|------|
| `bsd/syscall.zig` | Darwin 系统调用表与分发器 |
| `bsd/proc.zig` | BSD 进程模型（kqueue, wait） |
| `bsd/signal.zig` | POSIX 信号处理 |
| `bsd/vfs/vnode.zig` | VNode 抽象层 |
| `bsd/vfs/devfs.zig` | `/dev` 设备文件系统 |

### 3.3 I/O Kit 驱动框架

| 模块 | 说明 |
|------|------|
| `iokit/registry.zig` | IORegistry 设备树 |
| `iokit/service.zig` | IOService 基类 |
| `iokit/drivers/pcie.zig` | PCIe 总线扫描驱动 |

### 3.4 内存管理

| 模块 | 说明 |
|------|------|
| `mm/pmm.zig` | 物理内存管理器（页帧分配） |
| `mm/slab.zig` | Slab 分配器（小对象快速分配） |
| `lib/buddy.zig` | Buddy 分配器（大块连续内存分配） |

### 3.5 架构相关代码 (x86_64)

| 模块 | 说明 |
|------|------|
| `arch/x86_64/gdt.zig` | 全局描述符表（内核/用户态段） |
| `arch/x86_64/idt.zig` | 中断描述符表（256 中断向量） |
| `arch/x86_64/paging.zig` | 4 级页表管理 |
| `arch/x86_64/serial.zig` | 串口驱动（调试输出） |

## 4. 用户态组件

### 4.1 Mach-O 加载器

| 模块 | 说明 |
|------|------|
| `loader/macho/parser.zig` | Mach-O 头部与 Load Command 解析 |
| `loader/macho/fat.zig` | Fat Binary（Universal）处理 |
| `loader/macho/segments.zig` | Segment/Section 映射 |

### 4.2 系统库（规划中）

- `libsystem_kernel` — 系统调用包装
- `libc` — C 标准库基础函数
- `libdispatch` — Grand Central Dispatch (GCD)
- `libpthread` — POSIX 线程

### 4.3 Objective-C 运行时（规划中）

- `objc_msgSend` 消息派发
- Class / Metaclass 结构管理
- ARC 自动引用计数

## 5. 启动流程

```
UEFI 固件
  └─► BOOTX64.efi (src/main.zig)
        ├── 初始化 UEFI 控制台输出
        ├── 获取 Graphics Output Protocol (GOP)
        ├── 获取内存映射
        ├── 退出 Boot Services
        └─► kernelMain() (src/kernel/main.zig)
              ├── Phase 0: 串口初始化 + 日志系统
              ├── Phase 1: GDT + IDT 加载
              ├── Phase 2: 物理内存管理 (PMM + Buddy)
              ├── Phase 3: 帧缓冲 + 启动画面
              ├── Phase 4: 虚拟内存 (VM Map)
              ├── Phase 5: Mach 子系统 (Task + Thread)
              ├── Phase 6: BSD 层 (Syscall + VFS)
              ├── Phase 7: I/O Kit
              └── Phase 8: 进入空闲循环
```

## 6. 构建系统

项目使用 Zig 原生构建系统 (`build.zig`)：

- **构建目标**: x86_64 UEFI 可执行文件
- **输出目录**: `build/`
- **构建命令**: `zig build --prefix build` 或 `bash scripts/build.sh`
- **QEMU 运行**: `zig build run` 或 `bash scripts/run.sh`
- **磁盘镜像**: `zig build image` 或 `bash scripts/create_image.sh`

## 7. 目录结构

```
ChimeraOS/
├── build.zig              # 顶层构建脚本
├── build.zig.zon          # 依赖与元数据声明
├── src/                   # 源代码
│   ├── main.zig           # UEFI 引导入口
│   ├── kernel/            # 内核层
│   │   ├── main.zig       # 内核入口
│   │   ├── arch/x86_64/   # x86_64 架构代码
│   │   ├── mach/          # Mach 微内核子系统
│   │   ├── bsd/           # BSD POSIX 兼容层
│   │   ├── iokit/         # I/O Kit 驱动框架
│   │   ├── mm/            # 内存管理
│   │   └── lib/           # 内核内部库
│   ├── loader/            # Mach-O 加载器
│   │   └── macho/         # Mach-O 解析与段映射
│   └── lib/               # 公共库（日志等）
├── scripts/               # 构建与运行脚本
│   ├── build.sh           # 构建脚本
│   ├── test.sh            # 测试脚本
│   ├── run.sh             # QEMU 模拟运行
│   └── create_image.sh    # 磁盘镜像创建
└── docs/                  # 项目文档
    ├── architecture.md    # 架构文档（本文件）
    └── features.md        # 特性与路线图

```
