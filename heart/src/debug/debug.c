#include <stdbool.h>
#include <wlr/config.h>
#include <wlr/util/log.h>
#include <wlr/backend/wayland.h>
#include <wlr/backend/multi.h>

#if WLR_HAS_X11_BACKEND
#include <wlr/backend/x11.h>
#endif

#include <hrt/hrt_server.h>
#include <hrt/debug/hrt_debug.h>
#include <time.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_pointer.h>
#include "seat_impl.h"

struct multi_backend_data {
    bool added;
};

static bool add_output(struct wlr_backend *backend) {
    if (wlr_backend_is_wl(backend)) {
        wlr_log(WLR_DEBUG, "Adding WL output");
        return wlr_wl_output_create(backend);
    }

#if WLR_HAS_X11_BACKEND
    if (wlr_backend_is_x11(backend)) {
        wlr_log(WLR_DEBUG, "Adding X11 output");
        return wlr_x11_output_create(backend);
    }
#endif
    return false;
}

static void multi_bakend_callback(struct wlr_backend *backend, void *data) {
    struct multi_backend_data *thing = data;
    if (!thing->added) {
        thing->added = add_output(backend);
    }
}

bool hrt_add_output(const struct hrt_server *server) {
    struct wlr_backend *backend = server->backend;

    if (wlr_backend_is_multi(backend)) {
        struct multi_backend_data data = {
            .added = false,
        };

        wlr_multi_for_each_backend(backend, multi_bakend_callback, &data);
        if (data.added) {
            return true;
        }
    }

    return add_output(backend);
}

static uint32_t now_msec(void) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    return now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

void hrt_debug_pointer_warp(struct hrt_server *server, double lx, double ly) {
    struct hrt_seat *seat = &server->seat;
    wlr_cursor_warp_closest(seat->cursor, NULL, lx, ly);
    hrt_cursor_handle_motion(seat, now_msec());
}

void hrt_debug_pointer_button(struct hrt_server *server, uint32_t button,
                              bool pressed) {
    struct wlr_pointer_button_event event = {
        .pointer   = NULL,
        .time_msec = now_msec(),
        .button    = button,
        .state     = pressed ? WL_POINTER_BUTTON_STATE_PRESSED :
                               WL_POINTER_BUTTON_STATE_RELEASED,
    };
    hrt_cursor_handle_button(&server->seat, &event);
}
