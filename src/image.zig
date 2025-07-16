const std = @import("std");
const log = std.log.scoped(.Image);

const wayland = @import("wayland");
const wl = wayland.client.wl;

const Pixel = struct {
    const Self = @This();

    data: *[4]u8,
    info: *const PixelInfo,

    pub inline fn a(self: *const Self) ?u8 {
        return if (self.info.a_offset) |offset| self.data[offset] else null;
    }

    pub inline fn r(self: *const Self) u8 {
        return self.data[self.info.r_offset];
    }

    pub inline fn g(self: *const Self) u8 {
        return self.data[self.info.g_offset];
    }

    pub inline fn b(self: *const Self) u8 {
        return self.data[self.info.b_offset];
    }

    pub inline fn set_a(self: *Self, A: u8) void {
        if (self.info.a_offset) |offset| {
            self.data[offset] = A;
        } else {
            log.warn("try to set channal A while it not exists", .{});
        }
    }

    pub inline fn set_r(self: *Self, R: u8) void {
        self.data[self.info.r_offset] = R;
    }

    pub inline fn set_g(self: *Self, G: u8) void {
        self.data[self.info.g_offset] = G;
    }

    pub inline fn set_b(self: *Self, B: u8) void {
        self.data[self.info.b_offset] = B;
    }
};
const PixelInfo = struct {
    a_offset: ?u2,
    r_offset: u2,
    g_offset: u2,
    b_offset: u2,
    chan_num: usize = 4,
};

pub const Image = struct {
    const Self = @This();

    data: []u8,
    width: usize,
    height: usize,
    stride: usize,
    format: wl.Shm.Format,
    pixel_info: PixelInfo,

    pub fn create(
        fmt: wl.Shm.Format,
        data: [*]u8,
        width: usize,
        heigth: usize,
        stride: usize,
    ) Self {
        var info: PixelInfo = undefined;
        info.a_offset = null;
        // try to map
        const name = @tagName(fmt);
        var i: usize = 0;
        while (name[i] != 0): (i += 1) {
            switch (name[i]) {
                'x' => {},
                'a' => info.a_offset = @intCast(3 - i),
                'r' => info.r_offset = @intCast(3 - i),
                'g' => info.g_offset = @intCast(3 - i),
                'b' => info.b_offset = @intCast(3 - i),
                '8' => break,
                else => @panic("unsupport format"),
            }
        }
        info.chan_num = i;
        std.debug.assert(info.chan_num == stride/width);
        std.debug.assert(info.a_offset == null or info.chan_num == 4);

        return .{
            .data = data[0..heigth*stride],
            .width = width,
            .height = heigth,
            .stride = stride,
            .format = fmt,
            .pixel_info = info,
        };
    }

    pub fn at(self: *const Self, row: usize, col: usize) Pixel {
        if (row >= self.height or col >= self.width)
            @panic("row or col out of range");
        const point: *[4]u8 = @ptrCast(
            self.data.ptr
            + row*self.stride
            + col*@sizeOf(u8)*self.pixel_info.chan_num
        );
        return .{
            .data = point,
            .info = &self.pixel_info
        };
    }

    pub fn blur(self: *Self) void {
        const data = std.heap.c_allocator.alloc(u8, self.height*self.stride)
            catch @panic("alloc failed");
        var temp = Self.create(self.format, data.ptr, self.width, self.height, self.stride);
        const radius = 5;
        blur_h(&temp, self, radius);
        blur_v(self, &temp, radius);
    }

    pub inline fn copy(self: *const Self, data: []u8) Self {
        @memcpy(data, self.data);
        return .{
            .data = data,
            .width = self.width,
            .height = self.height,
            .stride = self.stride,
            .format = self.format,
            .pixel_info = self.pixel_info
        };
    }
};

fn blur_h(dst: *Image, src: *const Image, radius: usize) void {
    std.debug.assert(dst.width == src.width);
    std.debug.assert(dst.height == src.height);

    for (0..src.height) |row| {
        var r_sum: u32 = 0;
        var g_sum: u32 = 0;
        var b_sum: u32 = 0;
        for (0..radius) |col| {
            const pixcel = src.at(row, col);
            r_sum += pixcel.r();
            g_sum += pixcel.g();
            b_sum += pixcel.b();
        }
        var range = radius;
        for (0..src.width) |col| {
            if (col >= radius) {
                const pixel = src.at(row, col-radius);
                r_sum -= pixel.r();
                g_sum -= pixel.g();
                b_sum -= pixel.b();
                range -= 1;
            }
            if (col < src.width-radius) {
                const pixel = src.at(row, col+radius);
                r_sum += pixel.r();
                g_sum += pixel.g();
                b_sum += pixel.b();
                range += 1;
            }
            var pixel = dst.at(row, col);
            pixel.set_r(@intCast(r_sum/range));
            pixel.set_g(@intCast(g_sum/range));
            pixel.set_b(@intCast(b_sum/range));
        }
    }
}

fn blur_v(dst: *Image, src: *const Image, radius: usize) void {
    std.debug.assert(dst.width == src.width);
    std.debug.assert(dst.height == src.height);

    for (0..src.width) |col| {
        var r_sum: u32 = 0;
        var g_sum: u32 = 0;
        var b_sum: u32 = 0;
        for (0..radius) |row| {
            const pixcel = src.at(row, col);
            r_sum += pixcel.r();
            g_sum += pixcel.g();
            b_sum += pixcel.b();
        }
        var range = radius;
        for (0..src.height) |row| {
            if (row >= radius) {
                const pixel = src.at(row-radius, col);
                r_sum -= pixel.r();
                g_sum -= pixel.g();
                b_sum -= pixel.b();
                range -= 1;
            }
            if (row < src.height-radius) {
                const pixel = src.at(row+radius, col);
                r_sum += pixel.r();
                g_sum += pixel.g();
                b_sum += pixel.b();
                range += 1;
            }
            var pixel = dst.at(row, col);
            pixel.set_r(@intCast(r_sum/range));
            pixel.set_g(@intCast(g_sum/range));
            pixel.set_b(@intCast(b_sum/range));
        }
    }
}

test "Image" {
    const data = [_]u8 {
        1, 2, 3, 4,
        5, 6, 7, 8,
        9, 10, 11, 12,
    };
    var image: Image(.bgrx8888) = undefined;
    image.data = @ptrCast(&data);
    image.width = 1;
    image.height = 3;
    image.stride = 4;
    const pixcel = image.at(1, 0);
    try std.testing.expect(pixcel.A == 255);
    try std.testing.expect(pixcel.R == 6);
    try std.testing.expect(pixcel.G == 7);
    try std.testing.expect(pixcel.B == 8);
}
