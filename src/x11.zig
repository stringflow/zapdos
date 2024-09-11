const std = @import("std");

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/cursorfont.h");
});

const Self = @This();

pub const Display = c.Display;
pub const Screen = c.Screen;
pub const Window = c.Window;
pub const Image = c.XImage;

display: *Display,
screen: *Screen,
root: Window,

pub fn init() !Self {
    const display = c.XOpenDisplay("") orelse return error.OpenDisplayFailed;
    const screen = c.XDefaultScreenOfDisplay(display);
    const root = c.XRootWindowOfScreen(screen);

    return Self{
        .display = display,
        .screen = screen,
        .root = root,
    };
}

pub fn deinit(self: Self) void {
    xCall0(c.XCloseDisplay(self.display));
}

pub const Rect = struct {
    x: c_int,
    y: c_int,
    width: c_uint,
    height: c_uint,
};

pub const Selection = struct {
    start_x: c_int,
    start_y: c_int,
    rect: Rect,

    pub fn init(start_x: c_int, start_y: c_int) Selection {
        return Selection{
            .start_x = start_x,
            .start_y = start_y,
            .rect = .{
                .x = start_x,
                .y = start_y,
                .width = 0,
                .height = 0,
            },
        };
    }

    pub fn update(self: *Selection, pointer_x: c_int, pointer_y: c_int) void {
        const x_min = @min(self.start_x, pointer_x);
        const x_max = @max(self.start_x, pointer_x);

        const y_min = @min(self.start_y, pointer_y);
        const y_max = @max(self.start_y, pointer_y);

        self.rect.x = x_min;
        self.rect.y = y_min;
        self.rect.width = @intCast(x_max - x_min);
        self.rect.height = @intCast(y_max - y_min);
    }
};

pub fn selectScreenRegion(self: Self) Rect {
    var vinfo: c.XVisualInfo = undefined;
    xCall(c.XMatchVisualInfo(self.display, c.DefaultScreen(self.display), 32, c.TrueColor, &vinfo));

    var attributes: c.XSetWindowAttributes = .{};
    attributes.colormap = c.XCreateColormap(self.display, self.root, vinfo.visual, c.AllocNone);
    attributes.border_pixel = 0;
    attributes.background_pixel = 0;
    attributes.override_redirect = c.True;
    attributes.event_mask = c.ButtonPressMask | c.ButtonReleaseMask | c.ButtonMotionMask;

    defer xCall(c.XFreeColormap(self.display, attributes.colormap));

    const window = c.XCreateWindow(
        self.display,
        self.root,
        0,
        0,
        @intCast(self.screen.width),
        @intCast(self.screen.height),
        0,
        vinfo.depth,
        c.InputOutput,
        vinfo.visual,
        c.CWColormap | c.CWBorderPixel | c.CWBackPixel | c.CWOverrideRedirect | c.CWEventMask,
        &attributes,
    );
    defer xCall(c.XDestroyWindow(self.display, window));

    xCall(c.XMapWindow(self.display, window));
    defer xCall(c.XUnmapWindow(self.display, window));

    const gc = c.XCreateGC(self.display, window, 0, null);
    defer xCall(c.XFreeGC(self.display, gc));

    const cursor = c.XCreateFontCursor(self.display, c.XC_fleur);
    defer xCall(c.XFreeCursor(self.display, cursor));

    xCall(c.XDefineCursor(self.display, window, cursor));
    defer xCall(c.XUndefineCursor(self.display, window));

    var selection: Selection = undefined;
    var event: c.XEvent = undefined;

    const border_size = 1;

    while (true) {
        xCall0(c.XNextEvent(self.display, &event));

        switch (event.type) {
            c.ButtonPress => {
                selection = Selection.init(event.xbutton.x, event.xbutton.y);
            },
            c.ButtonRelease => {
                selection.update(event.xmotion.x, event.xmotion.y);

                var rect = selection.rect;

                rect.x += border_size;
                rect.y += border_size;
                rect.width -= @min(rect.width, border_size);
                rect.height -= @min(rect.height, border_size);

                return rect;
            },
            c.MotionNotify => {
                selection.update(event.xmotion.x, event.xmotion.y);
                const rect = selection.rect;

                xCall(c.XClearWindow(self.display, window));
                xCall(c.XSetForeground(self.display, gc, 0xffb0b0b0));
                xCall(c.XSetLineAttributes(self.display, gc, border_size, c.LineSolid, c.CapButt, c.JoinMiter));
                xCall(c.XDrawRectangle(self.display, window, gc, rect.x, rect.y, rect.width, rect.height));
            },
            else => unreachable,
        }
    }
}

pub fn getActiveWindow(self: Self) Window {
    var target: Window = c.None;
    var revert_to_return: c_int = 0;
    xCall(c.XGetInputFocus(self.display, &target, &revert_to_return));
    return target;
}

pub fn findWindowManagerFrame(self: Self, window: Window) Window {
    var target: Window = window;
    var root_return: Window = c.None;
    var parent: Window = c.None;
    var children: [*c]Window = undefined;
    var n_children: c_uint = undefined;

    while (true) {
        xCall(c.XQueryTree(self.display, target, &root_return, &parent, &children, &n_children));
        if (children != c.None) {
            xCall(c.XFree(children));
        }
        if (parent == c.None or parent == root_return) {
            break;
        }

        target = parent;
    }

    return target;
}

pub fn getWindowGeometry(self: Self, window: Window) Rect {
    var attributes: c.XWindowAttributes = undefined;
    xCall(c.XGetWindowAttributes(self.display, window, &attributes));

    var x: c_int = 0;
    var y: c_int = 0;
    var child_return: Window = c.None;
    xCall(c.XTranslateCoordinates(self.display, window, self.root, 0, 0, &x, &y, &child_return));

    var width = attributes.width;
    var height = attributes.height;

    width -= @max(0, x + width - self.screen.width);
    height -= @max(0, y + height - self.screen.height);

    return .{
        .x = x,
        .y = y,
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

pub fn getImage(self: Self, window: Window, rect: Rect) !*Image {
    const img = c.XGetImage(
        self.display,
        window,
        rect.x,
        rect.y,
        rect.width,
        rect.height,
        c.AllPlanes,
        c.ZPixmap,
    );

    if (img == null) {
        return error.GetImageFailed;
    }

    return img;
}

pub fn freeImage(img: *Image) void {
    if (img.*.f.destroy_image) |destroy| {
        xCall(@call(.auto, destroy, .{img}));
    }
}

fn xCall(return_value: c_int) void {
    if (return_value != c.True) @panic("x11 call failed!");
}

fn xCall0(return_value: c_int) void {
    if (return_value != 0) @panic("x11 call failed!");
}
