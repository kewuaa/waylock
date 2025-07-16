const Output = @This();

const std = @import("std");
const log = std.log;
const math = std.math;
const mem = std.mem;
const os = std.os;

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("sys/shm.h");
    @cInclude("sys/mman.h");
    @cInclude("sys/fcntl.h");
    @cInclude("sys/unistd.h");
});

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const ext = wayland.client.ext;
const zwlr = wayland.client.zwlr;

const image = @import("image.zig");
const Lock = @import("Lock.zig");

const gpa = std.heap.c_allocator;

lock: *Lock,
name: u32,
wl_output: *wl.Output,
surface: ?*wl.Surface = null,
lock_surface: ?*ext.SessionLockSurfaceV1 = null,
screencopy_frame: ?*zwlr.ScreencopyFrameV1 = null,

configured: bool = false,
// These fields are not used before the first configure is received.
width: u31 = undefined,
height: u31 = undefined,
buffer: struct {
    wl_buffer: *wl.Buffer,
    img: image.Image,
    backup: []u8,
    y_invert: bool,
    done: bool,

    pub fn destroy(self: *const @This()) void {
        self.wl_buffer.destroy();
        std.heap.c_allocator.free(self.backup);
    }
} = undefined,

pub fn create_surface(output: *Output) !void {
    const surface = try output.lock.compositor.?.createSurface();
    output.surface = surface;

    const lock_surface = try output.lock.session_lock.?.getLockSurface(surface, output.wl_output);
    lock_surface.setListener(*Output, lock_surface_listener, output);
    output.lock_surface = lock_surface;
}

pub fn create_screencopy_frame(output: *Output) !void {
    output.buffer.done = false;
    const screencopy_frame = try output.lock.screencopy_manager.?.captureOutput(0, output.wl_output);
    screencopy_frame.setListener(*Output, screencopy_frame_listener, output);
    output.screencopy_frame = screencopy_frame;
}

pub fn destroy(output: *Output) void {
    output.wl_output.release();
    if (output.lock_surface) |lock_surface| lock_surface.destroy();
    if (output.surface) |surface| surface.destroy();
    if (output.screencopy_frame) |frame| frame.destroy();

    output.buffer.destroy();

    const node: *std.SinglyLinkedList(Output).Node = @fieldParentPtr("data", output);
    output.lock.outputs.remove(node);
    gpa.destroy(node);
}

fn lock_surface_listener(
    _: *ext.SessionLockSurfaceV1,
    event: ext.SessionLockSurfaceV1.Event,
    output: *Output,
) void {
    switch (event) {
        .configure => |ev| {
            output.configured = true;
            output.width = @min(std.math.maxInt(u31), ev.width);
            output.height = @min(std.math.maxInt(u31), ev.height);
            output.lock_surface.?.ackConfigure(ev.serial);
            output.attach_buffer(output.buffer.wl_buffer);
        },
    }
}

fn screencopy_frame_listener(
    _: *zwlr.ScreencopyFrameV1,
    event: zwlr.ScreencopyFrameV1.Event,
    output: *Output,
) void {
    const lock = output.lock;
    switch (event) {
        .buffer => |buffer| {
            const ret = create_shm_buffer(
                lock.shm.?,
                buffer.width,
                buffer.height,
                buffer.stride,
                buffer.format,
            ) catch @panic("create shm buffer failed");
            output.buffer.img = image.Image.create(
                buffer.format,
                @ptrCast(ret.data),
                buffer.width,
                buffer.height,
                buffer.stride
            );
            output.buffer.wl_buffer = ret.buffer;
        },
        .buffer_done => {
            output.screencopy_frame.?.copy(output.buffer.wl_buffer);
        },
        .flags => |flags| {
            output.buffer.y_invert = flags.flags.y_invert;
        },
        .ready => {
            output.buffer.img.blur();
            output.buffer.backup = std.heap.c_allocator.alloc(u8, output.buffer.img.data.len)
                catch @panic("alloc failed");
            @memcpy(output.buffer.backup, output.buffer.img.data);
            output.buffer.done = true;
        },
        .failed => {
            @panic("screen copy failed");
        },
        else => {
            //
        }
    }
}

pub fn switch_color(output: *Output, color: Lock.Color) void {
    var img = &output.buffer.img;
    @memcpy(img.data, output.buffer.backup);
    switch (color) {
        .init => {},
        .fail => {
            for (0..img.height) |row| {
                for (0..img.width) |col| {
                    var pixel = img.at(row, col);
                    pixel.set_r(255);
                }
            }
        },
        .input => {
            for (0..img.height) |row| {
                for (0..img.width) |col| {
                    var pixel = img.at(row, col);
                    var ov: struct {u8, u1} = undefined;

                    ov = @mulWithOverflow(pixel.r(), 2);
                    pixel.set_r(if (ov[1] == 0) ov[0] else 255);
                    ov = @mulWithOverflow(pixel.g(), 2);
                    pixel.set_g(if (ov[1] == 0) ov[0] else 255);
                    ov = @mulWithOverflow(pixel.b(), 2);
                    pixel.set_b(if (ov[1] == 0) ov[0] else 255);
                }
            }
        }
    }
    output.attach_buffer(output.buffer.wl_buffer);
}

fn create_shm_buffer(shm: *wl.Shm, width: u32, height: u32, stride: u32, format: wl.Shm.Format) !struct {data: *void, buffer: *wl.Buffer} {
    const size = stride * height;
    const ts = std.time.timestamp();
    var r = std.Random.DefaultPrng.init(@intCast(ts));
    var name: [30:0]u8 = undefined;
    name[0] = '/';

    const fd = blk: {
        for (0..3) |_| {
            r.fill(name[1..]);
            const fd = c.shm_open(&name, c.O_RDWR|c.O_CREAT|c.O_EXCL, c.S_IRUSR|c.S_IWUSR);
            if (fd >= 0) {
                break:blk fd;
            }
        }
        return error.ShmOpenFailed;
    };
    defer _ = c.close(fd);

    _ = c.shm_unlink(&name);
    var ret: i32 = c.EINTR;
    while (ret == c.EINTR) {
        ret = std.c.ftruncate(fd, @intCast(size));
    }
    if (ret < 0) {
        return error.FtruncateFailed;
    }

    const data = c.mmap(null, size, c.PROT_READ|c.PROT_WRITE, c.MAP_SHARED, fd, 0);
    if (data == c.MAP_FAILED) {
        return error.MMAPFailed;
    }

    const pool = try shm.createPool(fd, @intCast(size));
    defer pool.destroy();

    const buffer = try pool.createBuffer(
        0,
        @intCast(width),
        @intCast(height),
        @intCast(stride),
        format
    );

    return .{
        .data = @ptrCast(data.?),
        .buffer = buffer
    };
}

fn attach_buffer(output: *Output, buffer: *wl.Buffer) void {
    if (!output.configured) return;
    output.surface.?.attach(buffer, 0, 0);
    output.surface.?.damageBuffer(0, 0, math.maxInt(i32), math.maxInt(i32));
    output.surface.?.commit();
}
