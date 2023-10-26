const std = @import("std");
const x11 = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xutil.h");
    @cInclude("X11/Xatom.h");
});

var close_requested: bool = false;

fn onDelete(display: *x11.Display, window: x11.Window) void {
    _ = x11.XDestroyWindow(display, window);
    close_requested = true;
}

var mouse_coordinates: struct { x: c_int, y: c_int } = .{ .x = 0, .y = 0 };

inline fn keysymToChar(keysym: x11.KeySym, shift: bool) ?u8 {
    const base_char: u8 = switch (keysym) {
        x11.XK_space => ' ',
        x11.XK_KP_0 => '0',
        x11.XK_KP_1 => '1',
        x11.XK_KP_2 => '2',
        x11.XK_KP_3 => '3',
        x11.XK_KP_4 => '4',
        x11.XK_KP_5 => '5',
        x11.XK_KP_6 => '6',
        x11.XK_KP_7 => '7',
        x11.XK_KP_8 => '8',
        x11.XK_KP_9 => '9',

        x11.XK_a => 'a',
        x11.XK_b => 'b',
        x11.XK_c => 'c',
        x11.XK_d => 'd',
        x11.XK_e => 'e',
        x11.XK_f => 'f',
        x11.XK_g => 'g',
        x11.XK_h => 'h',
        x11.XK_i => 'i',
        x11.XK_j => 'j',
        x11.XK_k => 'k',
        x11.XK_l => 'l',
        x11.XK_m => 'm',
        x11.XK_n => 'n',
        x11.XK_o => 'o',
        x11.XK_p => 'p',
        x11.XK_q => 'q',
        x11.XK_r => 'r',
        x11.XK_s => 's',
        x11.XK_t => 't',
        x11.XK_u => 'u',
        x11.XK_v => 'v',
        x11.XK_w => 'w',
        x11.XK_x => 'x',
        x11.XK_y => 'y',
        x11.XK_z => 'z',
        x11.XK_A => 'A',
        x11.XK_B => 'B',
        x11.XK_C => 'C',
        x11.XK_D => 'D',
        x11.XK_E => 'E',
        x11.XK_F => 'F',
        x11.XK_G => 'G',
        x11.XK_H => 'G',
        x11.XK_I => 'I',
        x11.XK_J => 'J',
        x11.XK_K => 'K',
        x11.XK_L => 'L',
        x11.XK_M => 'M',
        x11.XK_N => 'N',
        x11.XK_O => 'O',
        x11.XK_P => 'P',
        x11.XK_Q => 'Q',
        x11.XK_R => 'R',
        x11.XK_S => 'S',
        x11.XK_T => 'T',
        x11.XK_U => 'U',
        x11.XK_V => 'V',
        x11.XK_W => 'W',
        x11.XK_X => 'X',
        x11.XK_Y => 'Y',
        x11.XK_Z => 'Z',

        x11.XK_0 => '0',
        x11.XK_1 => '1',
        x11.XK_2 => '2',
        x11.XK_3 => '3',
        x11.XK_4 => '4',
        x11.XK_5 => '5',
        x11.XK_6 => '6',
        x11.XK_7 => '7',
        x11.XK_8 => '8',
        x11.XK_9 => '9',
        // x11.XK_ => '',

        else => return null,
    };

    if (shift and (base_char >= 'a' and base_char <= 'z')) {
        const caps_offset: u8 = 'a' - 'A';
        return base_char - caps_offset;
    }

    return base_char;
}

var shift_mod_left: bool = false;
var shift_mod_right: bool = false;

const text_to_paste: [*:0]const u8 = "Hello, clipboard world!";

pub fn main() !void {
    var display: *x11.Display = x11.XOpenDisplay(null) orelse {
        std.log.err("Failed to open X11 display", .{});
        return error.OpenX11DisplayFail;
    };
    errdefer _ = x11.XCloseDisplay(display);

    std.log.info("X11 display created", .{});

    var root: x11.Window = x11.DefaultRootWindow(display);
    if (root == x11.None) {
        std.log.err("Failed to find root x11 window", .{});
        return error.FindRootX11WindowFail;
    }

    var window: x11.Window = x11.XCreateSimpleWindow(display, root, 0, 0, 800, 600, 0, 0, 0xffffffff);
    if (window == x11.None) {
        std.log.err("Failed to create an x11 window", .{});
        return error.CreateX11WindowFail;
    }

    _ = x11.XMapWindow(display, window);

    var wm_delete_window: x11.Atom = x11.XInternAtom(display, "WM_DELETE_WINDOW", x11.False);
    _ = x11.XSetWMProtocols(display, window, &wm_delete_window, 1);

    _ = x11.XSetStandardProperties(display, window, "X11 Client in Zig", "X11 client", x11.None, null, 0, null);

    const clipboard_atom = x11.XInternAtom(display, "CLIPBOARD", x11.True);
    const targets_atom = x11.XInternAtom(display, "TARGETS", x11.True);
    const utf8_string_atom = x11.XInternAtom(display, "UTF8_STRING", x11.True);

    // Available masks:
    //   KeyPress,
    //   KeyRelease,
    //   ButtonPress,
    //   ButtonRelease,
    //   PointerMotion,
    //   Button1Motion,
    //   Button2Motion,
    //   Button3Motion,
    //   Button4Motion,
    //   Button5Motion,
    //   ButtonMotion
    // src: https://tronche.com/gui/x/xlib/window/attributes/event-and-do-not-propagate.html
    _ = x11.XSelectInput(display, window, x11.ExposureMask | x11.ButtonPressMask | x11.KeyPressMask | x11.KeyReleaseMask | x11.PointerMotionMask);

    var event: x11.XEvent = undefined;
    while (!close_requested) {
        _ = x11.XNextEvent(display, &event);
        switch (event.type) {
            x11.ClientMessage => {
                std.log.info("Client message recieved", .{});
                if (event.xclient.data.l[0] == wm_delete_window) {
                    onDelete(event.xclient.display.?, event.xclient.window);
                }
            },
            x11.KeyPress => {
                const keypress_event: *x11.XKeyEvent = @ptrCast(&event);
                const keysym: x11.KeySym = x11.XLookupKeysym(keypress_event, 0);

                if (keysym == x11.XK_Shift_L) {
                    shift_mod_left = true;
                    continue;
                }

                if (keysym == x11.XK_Shift_R) {
                    shift_mod_right = true;
                    continue;
                }

                if (keysymToChar(keysym, shift_mod_left or shift_mod_right)) |ch| {
                    std.log.info("Pressed: {c}", .{ch});
                    if (keysym == ' ') {
                        std.log.info("Copy simulated", .{});
                        _ = x11.XSetSelectionOwner(display, clipboard_atom, window, x11.CurrentTime);
                    }
                }
            },
            x11.KeyRelease => {
                const keypress_event: *x11.XKeyEvent = @ptrCast(&event);
                const keysym: x11.KeySym = x11.XLookupKeysym(keypress_event, 0);

                if (keysym == x11.XK_Shift_L) {
                    shift_mod_left = false;
                    continue;
                }

                if (keysym == x11.XK_Shift_R) {
                    shift_mod_right = false;
                    continue;
                }
            },
            x11.ButtonPress => std.log.info("XEvent: ButtonPress", .{}),
            x11.ButtonRelease => std.log.info("XEvent: ButtonRelease", .{}),
            x11.MotionNotify => {
                const motion_event: *x11.XMotionEvent = @ptrCast(&event);
                mouse_coordinates.x = motion_event.x;
                mouse_coordinates.y = motion_event.y;
                // std.debug.print("Mouse: ({d}, {d})\n", .{ mouse_coordinates.x, mouse_coordinates.y });
            },
            x11.EnterNotify => std.log.info("XEvent: EnterNotify", .{}),
            x11.LeaveNotify => std.log.info("XEvent: LeaveNotify", .{}),
            x11.FocusIn => std.log.info("XEvent: FocusIn", .{}),
            x11.FocusOut => std.log.info("XEvent: FocusOut", .{}),
            x11.KeymapNotify => std.log.info("XEvent: KeymapNotify", .{}),
            x11.Expose => std.log.info("XEvent: Expose", .{}),
            x11.GraphicsExpose => std.log.info("XEvent: GraphicsExpose", .{}),
            x11.NoExpose => std.log.info("XEvent: NoExpose", .{}),
            x11.VisibilityNotify => std.log.info("XEvent: VisibilityNotify", .{}),
            x11.CreateNotify => std.log.info("XEvent: CreateNotify", .{}),
            x11.DestroyNotify => std.log.info("XEvent: DestroyNotify", .{}),
            x11.UnmapNotify => std.log.info("XEvent: UnmapNotify", .{}),
            x11.MapNotify => std.log.info("XEvent: MapNotify", .{}),
            x11.MapRequest => std.log.info("XEvent: MapRequest", .{}),
            x11.ReparentNotify => std.log.info("XEvent: ReparentNotify", .{}),
            x11.ConfigureNotify => std.log.info("XEvent: ConfigureNotify", .{}),
            x11.ConfigureRequest => std.log.info("XEvent: ConfigureRequest", .{}),
            x11.GravityNotify => std.log.info("XEvent: GravityNotify", .{}),
            x11.ResizeRequest => std.log.info("XEvent: ResizeRequest", .{}),
            x11.CirculateNotify => std.log.info("XEvent: CirculateNotify", .{}),
            x11.CirculateRequest => std.log.info("XEvent: CirculateRequest", .{}),
            x11.PropertyNotify => std.log.info("XEvent: PropertyNotify", .{}),
            x11.SelectionClear => std.log.info("XEvent: SelectionClear", .{}),
            x11.SelectionRequest => {
                std.log.info("XEvent: SelectionRequest", .{});
                const selection_request_event: *x11.XSelectionRequestEvent = @ptrCast(&event);
                const selection_owner = x11.XGetSelectionOwner(display, clipboard_atom);
                if (selection_owner == window and selection_request_event.selection == clipboard_atom) {
                    if (selection_request_event.target == utf8_string_atom) {
                        //
                        // Client is requesting the selection in utf8
                        //
                        _ = x11.XChangeProperty(
                            selection_request_event.display,
                            selection_request_event.requestor,
                            selection_request_event.property,
                            selection_request_event.target,
                            8,
                            x11.PropModeReplace,
                            text_to_paste,
                            @intCast(std.mem.len(text_to_paste)),
                        );
                        std.log.info("Text sent to client", .{});
                    } else if (selection_request_event.target == targets_atom) {
                        //
                        // Client is requesting the supported targets for the selection (Clipboard)
                        //
                        _ = x11.XChangeProperty(
                            selection_request_event.display,
                            selection_request_event.requestor,
                            selection_request_event.property,
                            x11.XA_ATOM,
                            32,
                            x11.PropModeReplace,
                            @ptrCast(&utf8_string_atom),
                            1,
                        );
                        std.log.info("Supported formats for selection sent to client", .{});
                    }
                    var response_event = x11.XSelectionEvent{
                        .type = x11.SelectionNotify,
                        .serial = selection_request_event.serial,
                        .send_event = selection_request_event.send_event,
                        .display = selection_request_event.display,
                        .requestor = selection_request_event.requestor,
                        .selection = selection_request_event.selection,
                        .target = selection_request_event.target,
                        .property = selection_request_event.property,
                        .time = selection_request_event.time,
                    };

                    _ = x11.XSendEvent(display, selection_request_event.requestor, 0, 0, @ptrCast(&response_event));
                }
            },
            x11.SelectionNotify => std.log.info("XEvent: SelectionNotify", .{}),
            x11.ColormapNotify => std.log.info("XEvent: ColormapNotify", .{}),
            x11.MappingNotify => std.log.info("XEvent: MappingNotify", .{}),
            x11.GenericEvent => std.log.info("XEvent: GenericEvent", .{}),
            else => std.log.info("Unknown event with type: {d}", .{event.type}),
        }
    }
}
