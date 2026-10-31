#pragma once

#include <stdbool.h>
#include <wlr/types/wlr_scene.h>

#include "hrt/hrt_server.h"

struct hrt_drag {
    struct hrt_seat *seat;
    struct wlr_drag *drag;
    struct wlr_scene_tree *icon_tree;

    struct wl_listener motion;
    struct wl_listener destroy;
};

bool hrt_seat_init(struct hrt_seat *seat, struct hrt_server *server,
                   const struct hrt_seat_callbacks *callbacks);
void hrt_seat_destroy(struct hrt_seat *seat);

bool hrt_seat_keyboard_focus_surface(struct hrt_seat *seat,
                                     struct wlr_surface *surface);
bool hrt_seat_keyboard_focus_surface_clear(struct hrt_seat *seat,
                                           struct wlr_surface *surface);

void hrt_keyboard_init(struct hrt_seat *seat);
void hrt_keyboard_destroy(struct hrt_seat *seat);

bool hrt_cursor_init(struct hrt_seat *seat, struct hrt_server *server);
void hrt_cursor_destroy(struct hrt_seat *seat);

/**
 * Route the pointer's position and buttons: to the canvas or the client
 * under it, or, while a button pressed on a client is held, to that
 * client. DX, DY is how far the cursor just moved. For the cursor's own
 * events, and for debug tools that move the pointer.
 **/
void hrt_cursor_handle_motion(struct hrt_seat *seat, uint32_t time_msec,
                              double dx, double dy);
void hrt_cursor_handle_button(struct hrt_seat *seat,
                              struct wlr_pointer_button_event *event);

struct hrt_canvas;
struct wlr_scene_node *hrt_canvas_node(struct hrt_canvas *canvas);
