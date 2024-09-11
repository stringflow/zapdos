const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn encodeAndDump(arena: Allocator, width: usize, height: usize, pixels: []const u8, red_mask: u32, green_mask: u32, blue_mask: u32) !void {
    const alpha_mask = ~(red_mask | green_mask | blue_mask);

    const red_index = @ctz(red_mask) / 8;
    const green_index = @ctz(green_mask) / 8;
    const blue_index = @ctz(blue_mask) / 8;
    const alpha_index = @ctz(alpha_mask) / 8;

    var fmt: [4]u8 = undefined;
    fmt[red_index] = 'r';
    fmt[green_index] = 'g';
    fmt[blue_index] = 'b';
    fmt[alpha_index] = 'a';

    const size = try std.fmt.allocPrint(arena, "{d}x{d}", .{ width, height });

    var process = std.process.Child.init(&.{
        "ffmpeg",
        "-f",
        "rawvideo",
        "-s",
        size,
        "-pix_fmt",
        &fmt,
        "-i",
        "-",
        "-vf",
        "colorlevels=aomin=1.0",
        "-vframes",
        "1",
        "-vcodec",
        "png",
        "-f",
        "image2pipe",
        "pipe:1",
    }, arena);

    process.stdout_behavior = .Inherit;
    process.stdin_behavior = .Pipe;
    process.stderr_behavior = .Ignore;

    try process.spawn();
    try process.stdin.?.writeAll(pixels);
    _ = try process.wait();
}
