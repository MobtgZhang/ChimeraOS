#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
EFI_BIN="$BUILD_DIR/bin/BOOTX64.efi"

MEMORY="256M"
DISPLAY_OPT=""
EXTRA_ARGS=()
AUTO_BUILD=true

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Launch ChimeraOS in QEMU (x86_64 UEFI mode)"
    echo ""
    echo "Options:"
    echo "  --no-build       Skip automatic rebuild before running"
    echo "  --memory SIZE    Set guest memory (default: 256M)"
    echo "  --headless       Run without graphical display"
    echo "  --debug          Enable QEMU GDB server on port 1234"
    echo "  --monitor        Enable QEMU monitor on stdio"
    echo "  -h, --help       Show this help message"
    exit 0
}

GDB_SERVER=false
MONITOR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-build)   AUTO_BUILD=false; shift ;;
        --memory)     MEMORY="$2"; shift 2 ;;
        --headless)   DISPLAY_OPT="-display none"; shift ;;
        --debug)      GDB_SERVER=true; shift ;;
        --monitor)    MONITOR=true; shift ;;
        -h|--help)    usage ;;
        *)            EXTRA_ARGS+=("$1"); shift ;;
    esac
done

cd "$PROJECT_DIR"

# Auto-build if EFI binary doesn't exist or --no-build not set
if $AUTO_BUILD; then
    echo "[QEMU] Building ChimeraOS..."
    zig build --prefix "$BUILD_DIR"
fi

if [ ! -f "$EFI_BIN" ]; then
    echo "[QEMU] ERROR: $EFI_BIN not found."
    echo "       Run 'bash scripts/build.sh' first."
    exit 1
fi

# Setup EFI boot directory structure
mkdir -p "$BUILD_DIR/efi/boot"
cp "$EFI_BIN" "$BUILD_DIR/efi/boot/"

# Locate OVMF firmware
OVMF_FW=""
for fw in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/edk2/x64/OVMF_CODE.4m.fd /usr/share/OVMF/OVMF_CODE.fd; do
    if [ -f "$fw" ]; then
        OVMF_FW="$fw"
        break
    fi
done

if [ -z "$OVMF_FW" ]; then
    echo "[QEMU] ERROR: OVMF firmware not found."
    echo "       Install with: sudo apt install ovmf  (Debian/Ubuntu)"
    echo "                  or: sudo pacman -S edk2-ovmf  (Arch)"
    exit 1
fi

echo "[QEMU] Starting ChimeraOS..."
echo "  Firmware : $OVMF_FW"
echo "  EFI      : $EFI_BIN"
echo "  Memory   : $MEMORY"
echo "  Serial   : stdio"
echo ""

QEMU_ARGS=(
    qemu-system-x86_64
    -bios "$OVMF_FW"
    -net none
    -drive "format=raw,file=fat:rw:$BUILD_DIR"
    -m "$MEMORY"
    -serial stdio
    -no-reboot
    -no-shutdown
)

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
