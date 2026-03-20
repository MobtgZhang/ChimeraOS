const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const is_debug = optimize == .Debug;

    const enable_logging = b.option(
        bool,
        "log",
        "Enable kernel logging (default: true for Debug, false for Release)",
    ) orelse is_debug;

    const options = b.addOptions();
    options.addOption(bool, "enable_logging", enable_logging);

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .uefi,
    });

    const exe = b.addExecutable(.{
        .name = "BOOTX64",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "build_options", .module = options.createModule() },
            },
        }),
    });

    b.installArtifact(exe);

    const prefix = b.install_prefix;

    // Setup EFI directory structure and run QEMU
    const run_step = b.step("run", "Run ChimeraOS in QEMU");

    const setup_cmd = b.addSystemCommand(&.{
        "sh", "-c",
        b.fmt("mkdir -p {s}/efi/boot && cp {s}/bin/BOOTX64.efi {s}/efi/boot/", .{ prefix, prefix, prefix }),
    });
    setup_cmd.step.dependOn(b.getInstallStep());

    const qemu_args = &[_][]const u8{
        "qemu-system-x86_64",
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
    };

    const qemu_cmd = b.addSystemCommand(qemu_args);
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
