#include "wlr/util/log.h"
#include <stdint.h>
#include <wayland-util.h>
#include <wlr/types/wlr_xcursor_manager.h>
#include <hrt/hrt_session_lock.h>
#include <wlr/types/wlr_cursor.h>
#include <wlr/types/wlr_seat.h>

#include <hrt/hrt_server.h>
#include <hrt/hrt_input.h>

#include "idle_impl.h"
#include "scene_descriptor.h"
#include "seat_impl.h"
#include <hrt/hrt_canvas.h>

// This function is shamelessly ripped from the tinywl implementation:
static void *find_view_at(struct hrt_server *server, double lx, double ly,
                          struct wlr_surface **surface, double *sx,
                          double *sy) {
    /* This returns the topmost node in the scene at the given layout coords.
     * We only care about surface nodes as we are specifically looking for a
     * surface in the surface tree of a tinywl_toplevel. */
    struct wlr_scene_node *node =
        wlr_scene_node_at(&server->scene->tree.node, lx, ly, sx, sy);
    if (node == NULL || node->type != WLR_SCENE_NODE_BUFFER) {
        return NULL;
    }
    struct wlr_scene_buffer *scene_buffer = wlr_scene_buffer_from_node(node);
    struct wlr_scene_surface *scene_surface =
        wlr_scene_surface_try_from_buffer(scene_buffer);
    if (!scene_surface) {
        return NULL;
    }

    *surface = scene_surface->surface;
    /* Find the node corresponding to the toplevel at the root of this
     * surface tree, it is the only one for which we set the data field. */
    struct wlr_scene_tree *tree = node->parent;
    while (tree != NULL && tree->node.data == NULL) {
        tree = tree->node.parent;
    }
    if (tree) {
        return tree->node.data;
    } else {
        return NULL;
    }
}

// Canvases under the pointer

static struct hrt_canvas *find_canvas_at(struct hrt_server *server, double lx,
                                         double ly, double *cx, double *cy) {
    struct wlr_scene_node *node =
        wlr_scene_node_at(&server->scene->tree.node, lx, ly, cx, cy);
    if (node == NULL || node->type != WLR_SCENE_NODE_BUFFER) {
        return NULL;
    }
    return scene_descriptor_try_get(node, HRT_SCENE_DESC_CANVAS);
}

static void canvas_under_clear(struct hrt_seat *seat) {
    if (seat->canvas_under) {
        wl_list_remove(&seat->canvas_under_destroy.link);
        seat->canvas_under = nullptr;
    }
}

static void handle_canvas_under_destroy(struct wl_listener *listener,
                                        void *data) {
    struct hrt_seat *seat =
        wl_container_of(listener, seat, canvas_under_destroy);
    // The canvas is going away under the pointer: it hears nothing more.
    canvas_under_clear(seat);
}

/**
 * Make CANVAS (or none) the canvas under the pointer, telling the one
 * that was there that the pointer left.
 **/
static void canvas_under_set(struct hrt_seat *seat, struct hrt_canvas *canvas) {
    if (seat->canvas_under == canvas) {
        return;
    }
    const struct hrt_canvas_callbacks *callbacks =
        seat->server->canvas_callbacks;
    struct hrt_canvas *previous = seat->canvas_under;
    canvas_under_clear(seat);
    if (previous && callbacks && callbacks->pointer_leave) {
        callbacks->pointer_leave(previous);
    }
    if (canvas) {
        seat->canvas_under                = canvas;
        seat->canvas_under_destroy.notify = handle_canvas_under_destroy;
        wl_signal_add(&hrt_canvas_node(canvas)->events.destroy,
                      &seat->canvas_under_destroy);
    }
}

/**
 * Route the pointer's position to a canvas if one is under it. Returns
 * true when a canvas took it; clients then have no pointer focus.
 **/
static bool route_pointer_to_canvas(struct hrt_seat *seat, bool moved) {
    double cx, cy;
    struct hrt_canvas *canvas = find_canvas_at(seat->server, seat->cursor->x,
                                               seat->cursor->y, &cx, &cy);
    canvas_under_set(seat, canvas);
    if (!canvas) {
        return false;
    }
    wlr_seat_pointer_clear_focus(seat->seat);
    wlr_cursor_set_xcursor(seat->cursor, seat->xcursor_manager,
                           seat->cursor_image);
    const struct hrt_canvas_callbacks *callbacks =
        seat->server->canvas_callbacks;
    if (moved && callbacks && callbacks->pointer_motion) {
        callbacks->pointer_motion(canvas, cx, cy);
    }
    return true;
}

void hrt_seat_reset_view_under(struct hrt_seat *seat) {
    if (!seat->grabbed) {
        if (!hrt_session_locked(seat->server) &&
            route_pointer_to_canvas(seat, true)) {
            return;
        }
        double sx, sy;
        struct wlr_surface *found_surface = NULL;
        void *view = find_view_at(seat->server, seat->cursor->x,
                                  seat->cursor->y, &found_surface, &sx, &sy);

        if (!view) {
            wlr_cursor_set_xcursor(seat->cursor, seat->xcursor_manager,
                                   seat->cursor_image);
        }
        if (found_surface) {
            wlr_seat_pointer_notify_enter(seat->seat, found_surface, sx, sy);
        } else {
            wlr_seat_pointer_clear_focus(seat->seat);
        }
    }
}

void hrt_cursor_handle_motion(struct hrt_seat *seat, uint32_t time) {
    hrt_idle_notify_activity(seat);
    if (!seat->grabbed) {
        if (!hrt_session_locked(seat->server) &&
            route_pointer_to_canvas(seat, true)) {
            return;
        }
        double sx, sy;
        struct wlr_surface *found_surface = NULL;
        void *view = find_view_at(seat->server, seat->cursor->x,
                                  seat->cursor->y, &found_surface, &sx, &sy);
        if (!view) {
            wlr_cursor_set_xcursor(seat->cursor, seat->xcursor_manager,
                                   seat->cursor_image);
        }
        if (found_surface) {
            wlr_seat_pointer_notify_enter(seat->seat, found_surface, sx, sy);
            wlr_seat_pointer_notify_motion(seat->seat, time, sx, sy);
        } else {
            wlr_seat_pointer_clear_focus(seat->seat);
        }
    }
}

static void seat_motion(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, motion);
    struct wlr_pointer_motion_event *ev = data;

    wlr_cursor_move(seat->cursor, &ev->pointer->base, ev->delta_x, ev->delta_y);
    hrt_cursor_handle_motion(seat, ev->time_msec);
}

static void seat_motion_absolute(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, motion_absolute);
    struct wlr_pointer_motion_absolute_event *ev = data;

    wlr_cursor_warp_absolute(seat->cursor, &ev->pointer->base, ev->x, ev->y);
    hrt_cursor_handle_motion(seat, ev->time_msec);
}

void hrt_cursor_handle_button(struct hrt_seat *seat,
                              struct wlr_pointer_button_event *event) {
    hrt_idle_notify_activity(seat);
    if (hrt_session_locked(seat->server)) {
        // Only the lock surface under the pointer, if any, hears of it:
        wlr_seat_pointer_notify_button(seat->seat, event->time_msec,
                                       event->button, event->state);
    } else if (seat->canvas_under) {
        double cx, cy;
        struct hrt_canvas *canvas = find_canvas_at(
            seat->server, seat->cursor->x, seat->cursor->y, &cx, &cy);
        const struct hrt_canvas_callbacks *callbacks =
            seat->server->canvas_callbacks;
        if (canvas && callbacks && callbacks->pointer_button) {
            callbacks->pointer_button(canvas, cx, cy, event->button,
                                      event->state ==
                                          WL_POINTER_BUTTON_STATE_PRESSED);
        }
    } else if (!seat->grabbed) {
        /* Notify the client with pointer focus that a button press has occurred */
        seat->callbacks->button_event(seat, event);
    }
}

static void seat_button(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, button);
    hrt_cursor_handle_button(seat, data);
}

static void seat_axis(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, axis);
    hrt_idle_notify_activity(seat);
    struct wlr_pointer_axis_event *ev = data;
    if (hrt_session_locked(seat->server)) {
        wlr_seat_pointer_notify_axis(seat->seat, ev->time_msec, ev->orientation,
                                     ev->delta, ev->delta_discrete, ev->source,
                                     ev->relative_direction);
    } else if (seat->canvas_under) {
        double cx, cy;
        struct hrt_canvas *canvas = find_canvas_at(
            seat->server, seat->cursor->x, seat->cursor->y, &cx, &cy);
        const struct hrt_canvas_callbacks *callbacks =
            seat->server->canvas_callbacks;
        if (canvas && callbacks && callbacks->pointer_axis) {
            callbacks->pointer_axis(
                canvas, cx, cy,
                ev->orientation == WL_POINTER_AXIS_VERTICAL_SCROLL, ev->delta);
        }
    } else if (!seat->grabbed) {
        seat->callbacks->wheel_event(seat, ev);
    }
}

static void seat_frame(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, frame);
    wlr_seat_pointer_notify_frame(seat->seat);
}

constexpr uint32_t xcursor_base_size = 24;

bool hrt_seat_cursor_set_theme(struct hrt_seat *seat, char *theme_name,
                               uint32_t base_size) {
    if (base_size < 1) {
        wlr_log(WLR_ERROR, "Cannot set cursor base size to zero.");
    }
    struct wlr_xcursor_manager *manager =
        wlr_xcursor_manager_create(theme_name, base_size);
    if (!manager) {
        return false;
    }

    struct wlr_output_layout_output *output;
    wl_list_for_each(output, &seat->server->output_layout->outputs, link) {
        struct wlr_output *wlr_output = output->output;
        const float scale             = wlr_output->scale;
        if (!wlr_xcursor_manager_load(manager, scale)) {
            wlr_log(WLR_ERROR, "Failed to load cursor theme for scale %f",
                    scale);
            goto error;
        }
    }
    wlr_xcursor_manager_destroy(seat->xcursor_manager);
    seat->xcursor_manager = manager;
    hrt_seat_reset_view_under(seat);

    return true;
error:
    wlr_xcursor_manager_destroy(manager);
    return false;
}

bool hrt_cursor_init(struct hrt_seat *seat, struct hrt_server *server) {
    seat->cursor = wlr_cursor_create();
    if (!seat->cursor) {
        return false;
    }
    wlr_cursor_attach_output_layout(seat->cursor, server->output_layout);

    seat->xcursor_manager = wlr_xcursor_manager_create(NULL, xcursor_base_size);
    if (!seat->xcursor_manager) {
        wlr_log(WLR_ERROR, "Could not create the xcursor manager");
        return false;
    }

    seat->motion.notify = seat_motion;
    wl_signal_add(&seat->cursor->events.motion, &seat->motion);
    seat->motion_absolute.notify = seat_motion_absolute;
    wl_signal_add(&seat->cursor->events.motion_absolute,
                  &seat->motion_absolute);
    seat->button.notify = seat_button;
    wl_signal_add(&seat->cursor->events.button, &seat->button);
    seat->axis.notify = seat_axis;
    wl_signal_add(&seat->cursor->events.axis, &seat->axis);
    seat->frame.notify = seat_frame;
    wl_signal_add(&seat->cursor->events.frame, &seat->frame);

    return true;
}

void hrt_cursor_destroy(struct hrt_seat *seat) {
    wlr_log(WLR_DEBUG, "hrt_cursor destroyed");
    canvas_under_clear(seat);
    wl_list_remove(&seat->frame.link);
    wl_list_remove(&seat->axis.link);
    wl_list_remove(&seat->button.link);
    wl_list_remove(&seat->motion_absolute.link);
    wl_list_remove(&seat->motion.link);

    wlr_xcursor_manager_destroy(seat->xcursor_manager);
    wlr_cursor_destroy(seat->cursor);
}
