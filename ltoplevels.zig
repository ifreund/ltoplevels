const std = @import("std");

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const gpa = std.heap.c_allocator;

const ToplevelInfo = struct {
    title: []const u8 = undefined,
    app_id: []const u8 = undefined,
    maximized: bool = false,
    minimized: bool = false,
    activated: bool = false,
    fullscreen: bool = false,
    // TODO: parent and output
};

const InfoList = std.TailQueue(ToplevelInfo);

pub fn main() anyerror!void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var info_list = InfoList{};
    var opt_manager: ?*zwlr.ForeignToplevelManagerV1 = null;

    registry.setListener(*?*zwlr.ForeignToplevelManagerV1, registryListener, &opt_manager) catch unreachable;
    _ = try display.roundtrip();

    const manager = opt_manager orelse return error.ForeignToplevelManagementNotAdvertised;

    manager.setListener(*InfoList, managerListener, &info_list) catch unreachable;
    _ = try display.roundtrip();

    const slice = gpa.alloc(ToplevelInfo, info_list.len) catch @panic("out of memory");
    var it = info_list.first;
    var i: usize = 0;
    while (it) |node| : (it = node.next) {
        slice[i] = node.data;
        i += 1;
    }

    const stdout = std.io.getStdOut().writer();
    try std.json.stringify(slice, .{ .whitespace = .{} }, stdout);
    try stdout.writeByte('\n');
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, manager: *?*zwlr.ForeignToplevelManagerV1) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, zwlr.ForeignToplevelManagerV1.getInterface().name) == 0) {
                manager.* = registry.bind(global.name, zwlr.ForeignToplevelManagerV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn managerListener(
    manager: *zwlr.ForeignToplevelManagerV1,
    event: zwlr.ForeignToplevelManagerV1.Event,
    info_list: *InfoList,
) void {
    switch (event) {
        .toplevel => |ev| {
            const node = gpa.create(InfoList.Node) catch @panic("out of memory");
            node.data = .{};
            info_list.append(node);
            ev.toplevel.setListener(*ToplevelInfo, handleListener, &node.data) catch unreachable;
        },
        .finished => {},
    }
}

fn handleListener(
    handle: *zwlr.ForeignToplevelHandleV1,
    event: zwlr.ForeignToplevelHandleV1.Event,
    info: *ToplevelInfo,
) void {
    switch (event) {
        .title => |ev| info.title = gpa.dupe(u8, std.mem.span(ev.title)) catch @panic("out of memory"),
        .app_id => |ev| info.app_id = gpa.dupe(u8, std.mem.span(ev.app_id)) catch @panic("out of memory"),
        .state => |ev| {
            for (ev.state.slice(zwlr.ForeignToplevelHandleV1.State)) |state| {
                switch (state) {
                    .maximized => info.maximized = true,
                    .minimized => info.minimized = true,
                    .activated => info.activated = true,
                    .fullscreen => info.fullscreen = true,
                    else => {},
                }
            }
        },
        .done, .closed, .output_enter, .output_leave, .parent => {},
    }
}
