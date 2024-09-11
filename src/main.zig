const std = @import("std");
const Allocator = std.mem.Allocator;
const Arena = std.heap.ArenaAllocator;

const x11 = @import("x11.zig");
const png = @import("png.zig");

const Options = struct {
    strategy: enum {
        select,
        active,
    },
    include_decoration: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const options = parseArgv() orelse {
        try printHelp();
        return;
    };

    try takeScreenshot(allocator, options);
}

fn printHelp() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Usage: zapdos [select | active] [options]\n\n");
    try stdout.writeAll("Options:\n");
    try stdout.writeAll("\t-d\tIncludes the window decorations (active only)\n");
}

fn parseArgv() ?Options {
    var argv = std.process.args();
    _ = argv.next().?; // NOTE(stringflow): path to executable

    const command = argv.next() orelse return null;

    var options: Options = undefined;

    if (std.ascii.eqlIgnoreCase(command, "select")) {
        options.strategy = .select;
    } else if (std.ascii.eqlIgnoreCase(command, "active")) {
        options.strategy = .active;
    } else {
        return null;
    }

    while (argv.next()) |arg| {
        if (std.ascii.eqlIgnoreCase(arg, "-d")) {
            options.include_decoration = true;
        }
    }

    return options;
}

fn takeScreenshot(gpa: Allocator, options: Options) !void {
    const x = try x11.init();
    defer x.deinit();

    const rect = blk: {
        switch (options.strategy) {
            .select => break :blk x.selectScreenRegion(),
            .active => {
                var window = x.getActiveWindow();
                if (options.include_decoration) {
                    window = x.findWindowManagerFrame(window);
                }

                break :blk x.getWindowGeometry(window);
            },
        }
    };

    if (rect.width == 0 or rect.height == 0) {
        return error.RectTooSmall;
    }

    var arena = Arena.init(gpa);
    defer arena.deinit();
    const allocator = arena.allocator();

    const img = try x.getImage(x.root, rect);
    defer x11.freeImage(img);

    const width: usize = @intCast(img.width);
    const height: usize = @intCast(img.height);
    const bpp: usize = @intCast(img.bits_per_pixel);
    const pixels_length = width * height * bpp / 8;
    const pixels = img.data[0..pixels_length];

    try png.encodeAndDump(
        allocator,
        width,
        height,
        pixels,
        @intCast(img.red_mask),
        @intCast(img.green_mask),
        @intCast(img.blue_mask),
    );
}
