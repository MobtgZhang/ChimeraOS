const std = @import("std");

const ArchTarget = enum {
    x86_64,
    aarch64,
    riscv64,
    loong64,
    mips64el,
};

fn archInfo(a: ArchTarget) struct {
    cpu_arch: std.Target.Cpu.Arch,
    os_tag: std.Target.Os.Tag,
    efi_name: []const u8,
    qemu_bin: []const u8,
    root_source: []const u8,
} {
    return switch (a) {
        .x86_64 => .{
            .cpu_arch = .x86_64,
            .os_tag = .uefi,
            .efi_name = "BOOTX64",
            .qemu_bin = "qemu-system-x86_64",
            .root_source = "src/main.zig",
        },
        .aarch64 => .{
            .cpu_arch = .aarch64,
            .os_tag = .uefi,
            .efi_name = "BOOTAA64",
            .qemu_bin = "qemu-system-aarch64",
            .root_source = "src/main.zig",
        },
        // riscv64/loong64/mips64el: Zig's PE/COFF linker does not yet support
        // these architectures for UEFI output. Build as freestanding ELF instead;
        // a separate UEFI stub loader or U-Boot can chainload the ELF kernel.
        .riscv64 => .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .efi_name = "BOOTRISCV64",
            .qemu_bin = "qemu-system-riscv64",
            .root_source = "src/main.zig", // TODO: freestanding entry
        },
        .loong64 => .{
            .cpu_arch = .loongarch64,
            .os_tag = .freestanding,
            .efi_name = "BOOTLOONGARCH64",
            .qemu_bin = "qemu-system-loongarch64",
            .root_source = "src/main_loong64.zig",
        },
        .mips64el => .{
            .cpu_arch = .mips64el,
            .os_tag = .freestanding,
            .efi_name = "BOOTMIPS64",
            .qemu_bin = "qemu-system-mips64el",
            .root_source = "src/main.zig", // TODO: freestanding entry
        },
    };
}

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const is_debug = optimize == .Debug;

    const enable_logging = b.option(
        bool,
        "log",
        "Enable kernel logging (default: true for Debug, false for Release)",
    ) orelse is_debug;

    const arch_choice = b.option(
        ArchTarget,
        "arch",
        "Target architecture (default: x86_64)",
    ) orelse .x86_64;

    const info = archInfo(arch_choice);

    const options = b.addOptions();
    options.addOption(bool, "enable_logging", enable_logging);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = info.cpu_arch,
        .os_tag = info.os_tag,
    });

    const exe = b.addExecutable(.{
        .name = info.efi_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(info.root_source),
            .target = target,
            .optimize = optimize,
            // LoongArch64 UEFI: PIC forces PC-relative jump tables and
            // data references so the binary works at any load address
            // without relocation entries (PE .reloc section is empty).
            .pic = if (arch_choice == .loong64) true else null,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });

    // LoongArch64 needs 4K-aligned sections for UEFI PE/COFF compatibility.
    if (arch_choice == .loong64) {
        exe.linker_script = b.path("src/loong64_uefi.ld");
    }

    b.installArtifact(exe);

    // LoongArch64: convert freestanding ELF to PE/COFF EFI application.
    // Zig's PE/COFF linker does not yet support LoongArch; we post-process
    // with GNU objcopy to produce a UEFI-loadable binary, then fix the
    // ImageBase so the PE is compact enough for UEFI to load.
    if (arch_choice == .loong64) {
        const objcopy = b.addSystemCommand(&.{
            "loongarch64-linux-gnu-objcopy",
            "-O",
            "pei-loongarch64",
            "--strip-debug",
            "--subsystem",
            "efi-app",
            "--remove-section=.comment",
            "--remove-section=.eh_frame",
            "--remove-section=.eh_frame_hdr",
        });
        objcopy.addArtifactArg(exe);
        const efi_out = objcopy.addOutputFileArg(b.fmt("{s}.efi", .{info.efi_name}));

        const fix_pe = b.addSystemCommand(&.{
            "python3",
            "scripts/fix_pe_imagebase.py",
        });
        fix_pe.addFileArg(efi_out);
        fix_pe.step.dependOn(&objcopy.step);

        const efi_install = b.addInstallBinFile(efi_out, b.fmt("{s}.efi", .{info.efi_name}));
        efi_install.step.dependOn(&fix_pe.step);
        b.getInstallStep().dependOn(&efi_install.step);
    }

    const prefix = b.install_prefix;

    // Setup EFI directory structure and run QEMU
    const run_step = b.step("run", "Run ChimeraOS in QEMU");

    const efi_boot_dir = "efi/boot";

    const setup_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt("mkdir -p {s}/{s} && cp {s}/bin/{s}.efi {s}/{s}/", .{
            prefix,
            efi_boot_dir,
            prefix,
            info.efi_name,
            prefix,
            efi_boot_dir,
        }),
    });
    setup_cmd.step.dependOn(b.getInstallStep());

    const fw_base = "/home/mobtgzhang/Firmware";

    const qemu_cmd = switch (arch_choice) {
        .x86_64 => blk: {
            const cmd = b.addSystemCommand(&.{
                info.qemu_bin,
                "-bios",
                "/usr/share/OVMF/OVMF_CODE_4M.fd",
                "-net",
                "none",
                "-drive",
                b.fmt("format=raw,file=fat:rw:{s}", .{prefix}),
                "-m",
                "256M",
                "-serial",
                "stdio",
                "-no-reboot",
                "-no-shutdown",
            });
            break :blk cmd;
        },
        .aarch64 => blk: {
            const cmd = b.addSystemCommand(&.{
                info.qemu_bin,
                "-machine",
                "virt",
                "-cpu",
                "cortex-a72",
                "-bios",
                "/usr/share/AAVMF/AAVMF_CODE.fd",
                "-net",
                "none",
                "-drive",
                b.fmt("format=raw,file=fat:rw:{s}", .{prefix}),
                "-m",
                "256M",
                "-serial",
                "stdio",
                "-no-reboot",
                "-no-shutdown",
            });
            break :blk cmd;
        },
        .riscv64 => blk: {
            const cmd = b.addSystemCommand(&.{
                info.qemu_bin,
                "-machine",
                "virt",
                "-bios",
                "default",
                "-net",
                "none",
                "-drive",
                b.fmt("format=raw,file=fat:rw:{s}", .{prefix}),
                "-m",
                "256M",
                "-serial",
                "stdio",
                "-no-reboot",
                "-no-shutdown",
            });
            break :blk cmd;
        },
        .loong64 => blk: {
            const cmd = b.addSystemCommand(&.{
                info.qemu_bin,
                "-machine",
                "virt",
                "-cpu",
                "la464",
                "-bios",
                b.fmt("{s}/LoongArchVirtMachine/QEMU_EFI.fd", .{fw_base}),
                "-net",
                "none",
                "-m",
                "1G",
                "-serial",
                "stdio",
                "-no-reboot",
                "-no-shutdown",
                "-kernel",
                b.fmt("{s}/bin/{s}", .{ prefix, info.efi_name }),
            });
            break :blk cmd;
        },
        .mips64el => blk: {
            const cmd = b.addSystemCommand(&.{
                info.qemu_bin,
                "-machine",
                "malta",
                "-net",
                "none",
                "-drive",
                b.fmt("format=raw,file=fat:rw:{s}", .{prefix}),
                "-m",
                "256M",
                "-serial",
                "stdio",
                "-no-reboot",
                "-no-shutdown",
            });
            break :blk cmd;
        },
    };

    qemu_cmd.step.dependOn(&setup_cmd.step);
    run_step.dependOn(&qemu_cmd.step);

    // Disk image creation step
    const img_step = b.step("image", "Create bootable disk image");
    const img_cmd = b.addSystemCommand(&.{
        "bash", "scripts/create_image.sh",
    });
    img_cmd.step.dependOn(b.getInstallStep());
    img_step.dependOn(&img_cmd.step);
}
