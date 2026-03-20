# ChimeraOS

使用 **Zig** 从零编写的操作系统，目标是在 **x86_64 / ARM64 / RISC-V / LoongArch / MIPS64** 上实现 **macOS 应用程序的二进制兼容**。采用与 Apple XNU 类似的混合内核设计（Mach 微内核 + BSD 兼容层），为 Mach-O 可执行文件提供原生运行环境。

## 特性概览

- **Zig 全量实现** — 内核与用户态均用 Zig 编写，无隐藏控制流、显式错误处理、C ABI 兼容
- **XNU 风格混合内核** — Mach（IPC、Task/Thread、虚拟内存）+ BSD（POSIX 系统调用）+ I/O Kit 驱动框架
- **多架构 UEFI 启动** — 支持 x86_64、aarch64、riscv64、loong64、mips64el 五种架构
- **双缓冲显示** — 消除画面撕裂，通过 back buffer + swap 实现无闪烁桌面渲染
- **Mach-O 支持** — 解析 Header/Load Command、Fat Binary、Segment 映射；规划 dyld 动态链接
- **完整内存管理** — PMM 页帧分配、Buddy 大块分配、Slab 小对象分配
- **macOS 风格桌面** — 菜单栏、Dock 栏、窗口管理器、鼠标光标、系统图标
- **硬件抽象层（HAL）** — 统一的架构抽象接口，便于多平台移植

## 支持的架构

| 架构 | EFI 文件名 | QEMU 命令 | 状态 |
|------|-----------|-----------|------|
| x86_64 (AMD64) | `BOOTX64.efi` | `qemu-system-x86_64` | ✅ 完整支持 |
| aarch64 (ARM64) | `BOOTAA64.efi` | `qemu-system-aarch64` | 🔧 基础支持 |
| riscv64 (RISC-V) | `BOOTRISCV64.efi` | `qemu-system-riscv64` | 🔧 基础支持 |
| loong64 (LoongArch) | `BOOTLOONGARCH64.efi` | `qemu-system-loongarch64` | 🔧 基础支持 |
| mips64el (MIPS64) | `BOOTMIPS64.efi` | `qemu-system-mips64el` | ⚠️ 实验性 |

## 架构分层

```
macOS 应用 (.app) → Frameworks → dyld / ObjC Runtime → libSystem
    → Z-Kernel (Mach + BSD + IOKit)
        → HAL (Hardware Abstraction Layer)
            → x86_64 / aarch64 / riscv64 / loong64 / mips64el
```

## 桌面环境

ChimeraOS 实现了一个类似 macOS 的桌面界面（双缓冲无闪烁渲染）：

- **菜单栏** — 屏幕顶部，显示 Apple 图标、应用名称、菜单项、系统时钟
- **Dock 栏** — 屏幕底部居中，包含 Finder、终端、设置、文本编辑、关于等应用图标
- **窗口管理** — 可拖拽窗口，带有红黄绿"交通灯"按钮，圆角边框和阴影
- **鼠标光标** — 标准箭头光标，支持 PS/2 鼠标输入
- **渐变壁纸** — 紫蓝渐变桌面背景

## 构建与运行

**环境要求：** Zig 工具链（≥ 0.15.2）、QEMU、UEFI 固件（OVMF / AAVMF）

```bash
# 构建 x86_64（默认）
zig build --prefix build

# 构建指定架构
zig build --prefix build -Darch=aarch64
zig build --prefix build -Darch=riscv64
zig build --prefix build -Darch=loong64
zig build --prefix build -Darch=mips64el

# 在 QEMU 中运行（默认 x86_64）
zig build run
./scripts/run.sh

# 在 QEMU 中运行指定架构
./scripts/run.sh --arch aarch64
./scripts/run.sh --arch riscv64
./scripts/run.sh --arch loong64
```

更多构建选项见 `zig build --help`。

## 目录结构

```
ChimeraOS/
├── build.zig / build.zig.zon    # 多架构构建系统
├── src/
│   ├── main.zig                 # UEFI 引导入口（跨架构）
│   ├── kernel/
│   │   ├── main.zig             # 内核主入口与初始化流程
│   │   ├── arch/
│   │   │   ├── hal.zig          # 架构分发器（编译期选择）
│   │   │   ├── x86_64/          # x86_64: GDT, IDT, PIC, Serial, Paging, Ports, HAL
│   │   │   ├── aarch64/         # ARM64: PL011 UART, GICv2, MMU, HAL
│   │   │   ├── riscv64/         # RISC-V: 16550 UART, PLIC, Sv48 MMU, HAL
│   │   │   ├── loong64/         # LoongArch: UART, EIOINTC, MMU, HAL
│   │   │   └── mips64el/        # MIPS64: UART, CP0 IRQ, TLB, HAL
│   │   ├── mach/                # Mach 子系统：Port, Message, Task, Thread, Clock, VM
│   │   ├── bsd/                 # BSD 层：Syscall, Proc, Signal, VFS, DevFS
│   │   ├── iokit/               # I/O Kit：Registry, Service
│   │   │   └── drivers/         # 驱动：PCIe, PIT, RTC, KBD, Mouse, FB, ATA, AC97
│   │   ├── mm/                  # 内存管理：PMM, Slab
│   │   └── lib/                 # 内核库：Buddy, RBTree
│   ├── gui/                     # 桌面图形界面（双缓冲）
│   │   ├── desktop.zig          # 桌面合成器
│   │   ├── graphics.zig         # 2D 图形原语 + 双缓冲
│   │   ├── window.zig           # 窗口管理器
│   │   ├── menubar.zig          # 菜单栏
│   │   ├── dock.zig             # Dock 栏
│   │   ├── widgets.zig          # UI 组件
│   │   ├── cursor.zig           # 鼠标光标
│   │   ├── icons.zig            # 系统图标
│   │   ├── font.zig             # 8×16 位图字体
│   │   ├── color.zig            # 颜色与主题
│   │   └── event.zig            # 事件系统
│   ├── loader/macho/            # Mach-O 解析
│   └── lib/                     # 公共库（日志 — 多架构串口）
├── scripts/                     # build / run / test / create_image
└── docs/                        # 架构与特性文档
```

## HAL（硬件抽象层）接口

每个架构实现以下统一接口：

| 接口 | 说明 |
|------|------|
| `earlyInit()` | 串口初始化（最早调用） |
| `cpuInit()` | CPU 表 / 中断控制器 / MMU |
| `timerInit()` | 硬件定时器配置 |
| `timerTick()` | 定时器 tick 处理 |
| `inputInit()` | 键盘 / 鼠标初始化 |
| `readTime()` | 读取墙上时钟 |
| `cpuRelax()` | CPU 让出（pause/yield/wfi） |
| `halt()` | 停机（hlt/wfe/wfi/wait） |

## 各架构驱动实现

### x86_64（完整）
| 驱动 | 说明 |
|------|------|
| 8259 PIC | IRQ 重映射至向量 32-47 |
| PIT 8254 | 1000 Hz 系统时钟 |
| CMOS RTC | 日期时间读取 |
| PS/2 键盘 | 扫描码翻译、US QWERTY |
| PS/2 鼠标 | 3 字节包解析、绝对坐标 |
| GOP 帧缓冲 | UEFI 显示驱动 |
| ATA/IDE | PIO 模式磁盘读写 |
| AC97 音频 | 音频编解码器 |
| PCIe 总线 | 设备扫描与注册 |

### aarch64（基础）
PL011 UART、GICv2 中断控制器、ARM Generic Timer、4 级页表

### riscv64（基础）
16550 UART、PLIC 中断控制器、SBI 定时器、Sv48 页表

### loong64（基础）
16550 UART、EIOINTC 中断控制器、Stable Counter 定时器、多级页表

### mips64el（实验性）
16550 UART、CP0 中断控制器、CP0 Count/Compare 定时器、软件 TLB

## 当前状态

- **x86_64**：✅ 完整支持（UEFI 启动、双缓冲桌面、全部驱动）
- **aarch64**：🔧 HAL + 串口 + 中断控制器 + MMU 桩
- **riscv64**：🔧 HAL + 串口 + PLIC + MMU 桩
- **loong64**：🔧 HAL + 串口 + 中断控制器 + MMU 桩
- **mips64el**：⚠️ HAL 桩（UEFI 非官方支持）

## 许可

LGPL-2.1 license
