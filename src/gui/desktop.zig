/// Desktop compositor — the main GUI module that brings everything together.
/// Manages the wallpaper, menu bar, dock, window manager, and input routing.

const graphics = @import("graphics.zig");
const color_mod = @import("color.zig");
const menubar = @import("menubar.zig");
const dock = @import("dock.zig");
const window = @import("window.zig");
const cursor = @import("cursor.zig");
const event_mod = @import("event.zig");
const widgets = @import("widgets.zig");
const font = @import("font.zig");
const Color = color_mod.Color;
const theme = color_mod.theme;

var initialized: bool = false;
var frame_count: u64 = 0;
var needs_redraw: bool = true;

pub fn enableDoubleBuffer(back_buf: [*]u32) void {
    graphics.enableDoubleBuffer(back_buf);
}

pub fn init(fb_base: [*]volatile u32, w: u32, h: u32, stride: u32) void {
    graphics.init(fb_base, w, h, stride);
    menubar.init();
    dock.init();
    window.init();
    widgets.init();

    // Create default windows
    if (window.createWindow("About ChimeraOS", @intCast(w / 2 - 200), @intCast(h / 2 - 140), 400, 280, .about_dialog)) |_| {}

    if (window.createWindow("System Info", 60, 80, 380, 260, .text_view)) |id| {
        window.setWindowText(id, "ChimeraOS Z-Kernel v0.2.0\n\nArchitecture: x86_64\nKernel: XNU-style Hybrid\n  - Mach IPC subsystem\n  - BSD POSIX layer\n  - IOKit driver framework\n\nDrivers loaded:\n  PS/2 Keyboard, PS/2 Mouse\n  PIT Timer, CMOS RTC\n  GOP Framebuffer\n  ATA/IDE, AC97 Audio\n  PCIe Bus Scanner");
    }

    initialized = true;
    needs_redraw = true;
}

// ── Main render loop ─────────────────────────────────────

pub fn render() void {
    if (!initialized) return;

    drawWallpaper();
    window.renderAll();
    menubar.render();
    dock.render();
}

pub fn drawCursor(mx: i32, my: i32) void {
    cursor.draw(mx, my);
}

pub fn presentFrame() void {
    graphics.swapBuffers();
}

fn drawWallpaper() void {
    const sw = graphics.screenWidth();
    const sh = graphics.screenHeight();

    // Three-stage gradient wallpaper (macOS-inspired purple/blue)
    const mid_y = sh / 2;
    graphics.fillGradientV(0, 0, sw, mid_y, theme.wallpaper_top, theme.wallpaper_mid);
    graphics.fillGradientV(0, @intCast(mid_y), sw, sh - mid_y, theme.wallpaper_mid, theme.wallpaper_bottom);
}

// ── Input handling ───────────────────────────────────────

pub fn handleMouseMove(mx: i32, my: i32) void {
    dock.updateHover(mx, my);

    if (window.isDragging()) {
        window.updateDrag(mx, my);
        needs_redraw = true;
    }
}

pub fn handleMouseDown(mx: i32, my: i32) void {
    // Check menu bar
    if (menubar.isInMenuBar(my)) {
        return;
    }

    // Check dock
    if (dock.hitTest(mx, my)) |idx| {
        handleDockClick(idx);
        return;
    }

    // Check windows
    if (window.hitTest(mx, my)) |hit| {
        switch (hit.hit) {
            .close_btn => {
                window.closeWindow(hit.id);
                needs_redraw = true;
            },
            .minimize_btn => {
                window.closeWindow(hit.id);
                needs_redraw = true;
            },
            .maximize_btn => {},
            .title_bar => {
                window.focusWindow(hit.id);
                window.beginDrag(hit.id, mx, my);
                needs_redraw = true;
            },
            .content => {
                window.focusWindow(hit.id);
                needs_redraw = true;
            },
            .none => {},
        }
        return;
    }
}

pub fn handleMouseUp(_: i32, _: i32) void {
    if (window.isDragging()) {
        window.endDrag();
        needs_redraw = true;
    }
}

pub fn handleKeyPress(ascii: u8) void {
    _ = ascii;
    needs_redraw = true;
}

fn handleDockClick(idx: usize) void {
    const label = dock.getItemLabel(idx) orelse return;
    dock.setRunning(idx, true);

    if (strEql(label, "Finder")) {
        if (window.createWindow("Finder", 120, 100, 440, 320, .file_manager)) |_| {}
        menubar.setActiveApp("Finder");
    } else if (strEql(label, "Terminal")) {
        if (window.createWindow("Terminal", 200, 140, 500, 320, .terminal)) |id| {
            window.setWindowText(id, "ChimeraOS Terminal\n$ uname -a\nChimeraOS 0.2.0 x86_64 Z-Kernel\n$ whoami\nroot\n$ ls /dev\nnull  zero  console\n$ ");
        }
        menubar.setActiveApp("Terminal");
    } else if (strEql(label, "Settings")) {
        if (window.createWindow("System Preferences", 180, 100, 460, 340, .text_view)) |id| {
            window.setWindowText(id, "General\n  Appearance: Dark\n  Accent Color: Blue\n\nDisplay\n  Resolution: auto\n  Refresh: 60 Hz\n\nSound\n  Output: AC97\n  Volume: 80%\n\nNetwork\n  Status: Not Connected\n\nStorage\n  Primary: ATA/IDE\n\nAbout\n  ChimeraOS v0.2.0\n  Zig Z-Kernel");
        }
        menubar.setActiveApp("System Preferences");
    } else if (strEql(label, "TextEdit")) {
        if (window.createWindow("Untitled - TextEdit", 240, 120, 420, 300, .text_view)) |id| {
            window.setWindowText(id, "Welcome to ChimeraOS!\n\nThis is a simple desktop OS\nwritten entirely in Zig.\n\nIt features:\n- XNU-style hybrid kernel\n- Mach IPC messaging\n- BSD POSIX syscalls\n- IOKit driver framework\n- macOS-like desktop UI");
        }
        menubar.setActiveApp("TextEdit");
    } else if (strEql(label, "About")) {
        if (window.createWindow("About ChimeraOS", @intCast(graphics.screenWidth() / 2 - 200), @intCast(graphics.screenHeight() / 2 - 140), 400, 280, .about_dialog)) |_| {}
    }

    needs_redraw = true;
}

pub fn updateClock(hour: u8, minute: u8) void {
    menubar.updateClock(hour, minute);
}

pub fn tick() void {
    frame_count +%= 1;
}

pub fn needsRedraw() bool {
    return needs_redraw;
}

pub fn clearRedrawFlag() void {
    needs_redraw = false;
}

pub fn requestRedraw() void {
    needs_redraw = true;
}

fn strEql(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ca, cb| if (ca != cb) return false;
    return true;
}
