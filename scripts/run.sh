#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

ARCH="x86_64"
MEMORY="256M"
DISPLAY_OPT=""
EXTRA_ARGS=()
AUTO_BUILD=true
GDB_SERVER=false
MONITOR=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Launch ChimeraOS in QEMU"
    echo ""
    echo "Options:"
    echo "  --arch ARCH      Target architecture: x86_64 (default), aarch64, riscv64, loong64, mips64el"
    echo "  --no-build       Skip automatic rebuild before running"
    echo "  --memory SIZE    Set guest memory (default: 256M)"
    echo "  --headless       Run without graphical display"
    echo "  --debug          Enable QEMU GDB server on port 1234"
    echo "  --monitor        Enable QEMU monitor on stdio"
    echo "  -h, --help       Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)       ARCH="$2"; shift 2 ;;
        --no-build)   AUTO_BUILD=false; shift ;;
        --memory)     MEMORY="$2"; shift 2 ;;
        --headless)   DISPLAY_OPT="-display none"; shift ;;
        --debug)      GDB_SERVER=true; shift ;;
        --monitor)    MONITOR=true; shift ;;
        -h|--help)    usage ;;
        *)            EXTRA_ARGS+=("$1"); shift ;;
    esac
done

# Map architecture to EFI binary name and QEMU binary
case "$ARCH" in
    x86_64)
        EFI_NAME="BOOTX64"
        QEMU_BIN="qemu-system-x86_64"
        ;;
    aarch64|arm64)
        ARCH="aarch64"
        EFI_NAME="BOOTAA64"
        QEMU_BIN="qemu-system-aarch64"
        ;;
    riscv64)
        EFI_NAME="BOOTRISCV64"
        QEMU_BIN="qemu-system-riscv64"
        ;;
    loong64|loongarch64)
        ARCH="loong64"
        EFI_NAME="BOOTLOONGARCH64"
        QEMU_BIN="qemu-system-loongarch64"
        ;;
    mips64el|mips64)
        ARCH="mips64el"
        EFI_NAME="BOOTMIPS64"
        QEMU_BIN="qemu-system-mips64el"
        ;;
    *)
        echo "[QEMU] ERROR: Unknown architecture: $ARCH"
        echo "       Supported: x86_64, aarch64, riscv64, loong64, mips64el"
        exit 1
        ;;
esac

EFI_BIN="$BUILD_DIR/bin/${EFI_NAME}.efi"

cd "$PROJECT_DIR"

# Auto-build
if $AUTO_BUILD; then
    echo "[QEMU] Building ChimeraOS for $ARCH..."
    zig build --prefix "$BUILD_DIR" -Darch="$ARCH"
fi

if [ ! -f "$EFI_BIN" ]; then
    echo "[QEMU] ERROR: $EFI_BIN not found."
    echo "       Run 'bash scripts/build.sh --arch $ARCH' first."
    exit 1
fi

# Setup EFI boot directory structure
mkdir -p "$BUILD_DIR/efi/boot"
cp "$EFI_BIN" "$BUILD_DIR/efi/boot/"

echo "[QEMU] Starting ChimeraOS ($ARCH)..."
echo "  Architecture: $ARCH"
echo "  EFI Binary  : $EFI_BIN"
echo "  Memory      : $MEMORY"
echo "  Serial      : stdio"
echo ""

# Build QEMU command based on architecture
case "$ARCH" in
    x86_64)
        # Locate OVMF firmware
        OVMF_MODE=""
        OVMF_CODE=""
        OVMF_VARS=""

        SPLIT_CANDIDATES=(
            "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd"
            "/usr/share/edk2/x64/OVMF_CODE.4m.fd:/usr/share/edk2/x64/OVMF_VARS.4m.fd"
            "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd"
            "/usr/share/edk2/ovmf/OVMF_CODE.fd:/usr/share/edk2/ovmf/OVMF_VARS.fd"
        )

        for pair in "${SPLIT_CANDIDATES[@]}"; do
            code="${pair%%:*}"
            vars="${pair##*:}"
            if [ -f "$code" ] && [ -f "$vars" ]; then
                OVMF_MODE="pflash"
                OVMF_CODE="$code"
                OVMF_VARS="$vars"
                break
            fi
        done

        if [ -z "$OVMF_MODE" ]; then
            COMBINED_CANDIDATES=(
                "/usr/share/ovmf/OVMF.fd"
                "/usr/share/qemu/OVMF.fd"
                "/usr/share/OVMF/OVMF.fd"
                "/usr/share/edk2/x64/OVMF.fd"
            )
            for fw in "${COMBINED_CANDIDATES[@]}"; do
                if [ -f "$fw" ]; then
                    OVMF_MODE="bios"
                    OVMF_CODE="$fw"
                    break
                fi
            done
        fi

        if [ -z "$OVMF_MODE" ]; then
            echo "[QEMU] ERROR: OVMF firmware not found."
            echo "       Install: sudo apt install ovmf"
            exit 1
        fi

        QEMU_ARGS=(
            "$QEMU_BIN"
            -net none
            -drive "format=raw,file=fat:rw:$BUILD_DIR"
            -m "$MEMORY"
            -serial stdio
            -no-reboot
            -no-shutdown
        )

        if [ "$OVMF_MODE" = "pflash" ]; then
            PFLASH_VARS="$BUILD_DIR/OVMF_VARS.fd"
            [ ! -f "$PFLASH_VARS" ] && cp "$OVMF_VARS" "$PFLASH_VARS"
            QEMU_ARGS+=(
                -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE"
                -drive "if=pflash,format=raw,file=$PFLASH_VARS"
            )
            echo "  Firmware  : $OVMF_CODE (pflash)"
        else
            QEMU_ARGS+=(-bios "$OVMF_CODE")
            echo "  Firmware  : $OVMF_CODE (bios)"
        fi
        ;;

    aarch64)
        # Locate AAVMF/EDK2 ARM firmware
        AAVMF_CODE=""
        AAVMF_CANDIDATES=(
            "/usr/share/AAVMF/AAVMF_CODE.fd"
            "/usr/share/edk2/aarch64/QEMU_EFI.fd"
            "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd"
            "/usr/share/edk2/aarch64/QEMU_CODE.fd"
        )
        for fw in "${AAVMF_CANDIDATES[@]}"; do
            if [ -f "$fw" ]; then
                AAVMF_CODE="$fw"
                break
            fi
        done

        if [ -z "$AAVMF_CODE" ]; then
            echo "[QEMU] ERROR: ARM64 UEFI firmware not found."
            echo "       Install: sudo apt install qemu-efi-aarch64"
            exit 1
        fi

        echo "  Firmware  : $AAVMF_CODE"

        QEMU_ARGS=(
            "$QEMU_BIN"
            -machine virt
            -cpu cortex-a72
            -bios "$AAVMF_CODE"
            -net none
            -drive "format=raw,file=fat:rw:$BUILD_DIR"
            -m "$MEMORY"
            -serial stdio
            -no-reboot
            -no-shutdown
        )
        ;;

    riscv64)
        # RISC-V UEFI firmware (U-Boot or EDK2)
        RISCV_FW=""
        RISCV_CANDIDATES=(
            "/usr/share/qemu/opensbi-riscv64-generic-fw_dynamic.bin"
            "/usr/share/opensbi/lp64/generic/firmware/fw_dynamic.bin"
            "/usr/lib/riscv64-linux-gnu/opensbi/generic/fw_dynamic.bin"
        )
        for fw in "${RISCV_CANDIDATES[@]}"; do
            if [ -f "$fw" ]; then
                RISCV_FW="$fw"
                break
            fi
        done

        echo "  Firmware  : ${RISCV_FW:-default}"

        QEMU_ARGS=(
            "$QEMU_BIN"
            -machine virt
            -net none
            -drive "format=raw,file=fat:rw:$BUILD_DIR"
            -m "$MEMORY"
            -serial stdio
            -no-reboot
            -no-shutdown
        )

        if [ -n "$RISCV_FW" ]; then
            QEMU_ARGS+=(-bios "$RISCV_FW")
        else
            QEMU_ARGS+=(-bios default)
        fi
        ;;

    loong64)
        echo "  Firmware  : default (QEMU built-in)"

        QEMU_ARGS=(
            "$QEMU_BIN"
            -machine virt
            -net none
            -drive "format=raw,file=fat:rw:$BUILD_DIR"
            -m "$MEMORY"
            -serial stdio
            -no-reboot
            -no-shutdown
            -bios default
        )
        ;;

    mips64el)
        echo "  Firmware  : Malta ROM (non-UEFI)"
        echo "  NOTE: MIPS64el uses direct kernel load, not standard UEFI boot."

        QEMU_ARGS=(
            "$QEMU_BIN"
            -machine malta
            -net none
            -m "$MEMORY"
            -serial stdio
            -no-reboot
            -no-shutdown
            -kernel "$EFI_BIN"
        )
        ;;
esac

if $GDB_SERVER; then
    echo "[QEMU] GDB server listening on tcp::1234"
    QEMU_ARGS+=(-s -S)
fi

if $MONITOR; then
    QEMU_ARGS+=(-monitor telnet:127.0.0.1:55555,server,nowait)
    echo "[QEMU] Monitor: telnet 127.0.0.1 55555"
fi

if [ -n "$DISPLAY_OPT" ]; then
    # shellcheck disable=SC2206
    QEMU_ARGS+=($DISPLAY_OPT)
fi

QEMU_ARGS+=("${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}")

exec "${QEMU_ARGS[@]}"
