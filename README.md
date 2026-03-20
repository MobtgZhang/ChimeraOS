# ChimeraOS

使用 **Zig** 从零编写的操作系统，目标是在 x86_64 / ARM64 上实现 **macOS 应用程序的二进制兼容**。采用与 Apple XNU 类似的混合内核设计（Mach 微内核 + BSD 兼容层），为 Mach-O 可执行文件提供原生运行环境。

## 特性概览

- **Zig 全量实现** — 内核与用户态均用 Zig 编写，无隐藏控制流、显式错误处理、C ABI 兼容
- **XNU 风格混合内核** — Mach（IPC、Task/Thread、虚拟内存）+ BSD（POSIX 系统调用）+ I/O Kit 驱动框架
- **Mach-O 支持** — 解析 Header/Load Command、Fat Binary、Segment 映射；规划 dyld 动态链接
- **UEFI 原生启动** — 直接生成 `BOOTX64.efi`，支持 GOP 帧缓冲与标准内存映射交接
- **完整内存管理** — PMM 页帧分配、Buddy 大块分配、Slab 小对象分配

## 架构分层

```
macOS 应用 (.app) → Frameworks → dyld / ObjC Runtime → libSystem → Z-Kernel (Mach + BSD + IOKit) → x86_64/ARM64
```

## 构建与运行

**环境要求：** Zig 工具链、QEMU、OVMF（UEFI 固件）

```bash
# 构建（输出至 build/）
zig build --prefix build
# 或
./scripts/build.sh

# 在 QEMU 中运行
zig build run
# 或
./scripts/run.sh
```

更多构建选项（如日志开关）见 `zig build --help`。

## 目录结构

```
ChimeraOS/
├── build.zig / build.zig.zon   # 构建与依赖
├── src/
│   ├── main.zig                # UEFI 引导入口
│   ├── kernel/                 # 内核：arch, mach, bsd, iokit, mm, lib
│   ├── loader/macho/           # Mach-O 解析与段映射
│   └── lib/                    # 公共库（日志等）
├── scripts/                    # build / run / test / create_image
├── docs/                       # 架构与特性文档
└── ideas/                      # 设计与路线图
```

## 文档与路线图

- [架构说明](docs/architecture.md) — 内核子系统、启动流程、目录说明
- [特性与路线图](docs/features.md) — 开发阶段、多架构支持、与 Darling/GNUstep 对比

## 当前状态

- **x86_64**：开发中（UEFI 引导、内存管理、Mach Task/Thread、BSD 系统调用表、VFS/DevFS、I/O Kit、PCIe 扫描、Mach-O 基础解析已实现）
- **ARM64**：规划中

## 许可

LGPL-2.1 license 
