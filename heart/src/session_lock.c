/**
 * ext-session-lock-v1, after sway's lock.c.
 **/

#include <stdlib.h>

#include <wlr/types/wlr_output_layout.h>
#include <wlr/types/wlr_scene.h>
#include <wlr/types/wlr_session_lock_v1.h>
#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/log.h>

#include "hrt/hrt_output.h"
#include "hrt/hrt_scene.h"
#include "hrt/hrt_server.h"
#include "seat_impl.h"
#include "session_lock_impl.h"

struct hrt_session_lock;

struct hrt_session_lock_output {
    struct wlr_scene_tree *tree;
    struct wlr_scene_rect *background;
    struct hrt_output *output;
    struct hrt_session_lock *lock;
    struct wl_list link; // hrt_session_lock.outputs

    struct wl_listener tree_destroy;

    // The client's lock surface for this output, once it made one:
    struct wlr_session_lock_surface_v1 *surface;
    struct wl_listener surface_destroy;
    struct wl_listener surface_map;
};

struct hrt_session_lock {
    struct hrt_server *server;
    // NULL once the client went away without unlocking:
    struct wlr_session_lock_v1 *lock;
    bool abandoned;
    struct wl_list outputs; // hrt_session_lock_output.link
    // The lock surface with keyboard focus, if any:
    struct wlr_surface *focused;

    struct wl_listener new_surface;
    struct wl_listener unlock;
    struct wl_listener destroy;
};

static const float black[4]    = {0.f, 0.f, 0.f, 1.f};
static const float dark_red[4] = {0.3f, 0.f, 0.f, 1.f};

static void lock_focus(struct hrt_session_lock *lock,
                       struct wlr_surface *surface) {
    struct hrt_seat *seat = &lock->server->seat;
    lock->focused         = surface;
    if (surface) {
        hrt_seat_keyboard_focus_surface(seat, surface);
    } else {
        wlr_seat_keyboard_notify_clear_focus(seat->seat);
    }
}

static void lock_output_reconfigure(struct hrt_session_lock_output *lo) {
    int width, height;
    wlr_output_effective_resolution(lo->output->wlr_output, &width, &height);
    wlr_scene_rect_set_size(lo->background, width, height);
    if (lo->surface) {
        wlr_session_lock_surface_v1_configure(lo->surface, width, height);
    }
}

static void lock_output_refocus(struct hrt_session_lock_output *lo) {
    // The focused surface goes away: move the focus to another lock
    // surface, if one is mapped.
    if (lo->lock->focused != lo->surface->surface) {
        return;
    }
    struct wlr_surface *next = nullptr;
    struct hrt_session_lock_output *other;
    wl_list_for_each(other, &lo->lock->outputs, link) {
        if (other != lo && other->surface && other->surface->surface->mapped) {
            next = other->surface->surface;
            break;
        }
    }
    lock_focus(lo->lock, next);
}

static void handle_surface_map(struct wl_listener *listener, void *data) {
    struct hrt_session_lock_output *lo =
        wl_container_of(listener, lo, surface_map);
    if (lo->lock->focused == nullptr) {
        lock_focus(lo->lock, lo->surface->surface);
    }
    hrt_seat_reset_view_under(&lo->lock->server->seat);
}

static void handle_surface_destroy(struct wl_listener *listener, void *data) {
    struct hrt_session_lock_output *lo =
        wl_container_of(listener, lo, surface_destroy);
    lock_output_refocus(lo);
    wl_list_remove(&lo->surface_destroy.link);
    wl_list_remove(&lo->surface_map.link);
    lo->surface = nullptr;
}

static void handle_new_surface(struct wl_listener *listener, void *data) {
    struct hrt_session_lock *lock =
        wl_container_of(listener, lock, new_surface);
    struct wlr_session_lock_surface_v1 *lock_surface = data;

    struct hrt_session_lock_output *lo = nullptr, *candidate;
    wl_list_for_each(candidate, &lock->outputs, link) {
        if (candidate->output->wlr_output == lock_surface->output) {
            lo = candidate;
            break;
        }
    }
    if (!lo) {
        wlr_log(WLR_ERROR, "Lock surface for an output the lock doesn't know");
        return;
    }
    if (lo->surface) {
        wlr_log(WLR_ERROR, "A second lock surface for output %s",
                lo->output->wlr_output->name);
        return;
    }
    wlr_log(WLR_DEBUG, "New lock surface on %s", lo->output->wlr_output->name);

    lo->surface = lock_surface;
    wlr_scene_subsurface_tree_create(lo->tree, lock_surface->surface);

    lo->surface_destroy.notify = handle_surface_destroy;
    wl_signal_add(&lock_surface->events.destroy, &lo->surface_destroy);
    lo->surface_map.notify = handle_surface_map;
    wl_signal_add(&lock_surface->surface->events.map, &lo->surface_map);

    lock_output_reconfigure(lo);
}

static void lock_output_destroy(struct hrt_session_lock_output *lo) {
    if (lo->surface) {
        lock_output_refocus(lo);
        wl_list_remove(&lo->surface_destroy.link);
        wl_list_remove(&lo->surface_map.link);
    }
    wl_list_remove(&lo->tree_destroy.link);
    wl_list_remove(&lo->link);
    free(lo);
}

static void handle_tree_destroy(struct wl_listener *listener, void *data) {
    // The output's scene went away with the output:
    struct hrt_session_lock_output *lo =
        wl_container_of(listener, lo, tree_destroy);
    lock_output_destroy(lo);
}

static void lock_output_create(struct hrt_session_lock *lock,
                               struct hrt_output *output) {
    struct hrt_session_lock_output *lo = calloc(1, sizeof(*lo));
    if (!lo) {
        wlr_log(WLR_ERROR, "Could not allocate a session lock output");
        return;
    }
    lo->tree = wlr_scene_tree_create(output->scene->session_lock);
    if (!lo->tree) {
        free(lo);
        return;
    }
    lo->background = wlr_scene_rect_create(lo->tree, 0, 0,
                                           lock->abandoned ? dark_red : black);
    if (!lo->background) {
        wlr_scene_node_destroy(&lo->tree->node);
        free(lo);
        return;
    }
    lo->output = output;
    lo->lock   = lock;

    lo->tree_destroy.notify = handle_tree_destroy;
    wl_signal_add(&lo->tree->node.events.destroy, &lo->tree_destroy);

    wl_list_insert(&lock->outputs, &lo->link);
    lock_output_reconfigure(lo);
}

static void session_lock_destroy(struct hrt_session_lock *lock) {
    struct hrt_session_lock_output *lo, *tmp;
    wl_list_for_each_safe(lo, tmp, &lock->outputs, link) {
        // Destroying the tree destroys the lock output, see
        // handle_tree_destroy:
        wlr_scene_node_destroy(&lo->tree->node);
    }
    if (lock->lock) {
        wl_list_remove(&lock->new_surface.link);
        wl_list_remove(&lock->unlock.link);
        wl_list_remove(&lock->destroy.link);
    }
    lock->server->session_lock = nullptr;
    free(lock);
}

static void handle_unlock(struct wl_listener *listener, void *data) {
    struct hrt_session_lock *lock = wl_container_of(listener, lock, unlock);
    struct hrt_server *server     = lock->server;
    wlr_log(WLR_INFO, "Session unlocked");

    session_lock_destroy(lock);
    server->session_locked = false;
    hrt_seat_reset_view_under(&server->seat);
    if (server->session_lock_callbacks &&
        server->session_lock_callbacks->unlocked) {
        server->session_lock_callbacks->unlocked();
    }
}

static void handle_lock_destroy(struct wl_listener *listener, void *data) {
    // The client went away without unlocking: stay locked, and show that
    // something is wrong, until another client locks the session.
    struct hrt_session_lock *lock = wl_container_of(listener, lock, destroy);
    wlr_log(WLR_ERROR,
            "The session lock client went away without unlocking; "
            "the session stays locked");
    wl_list_remove(&lock->new_surface.link);
    wl_list_remove(&lock->unlock.link);
    wl_list_remove(&lock->destroy.link);
    lock->lock      = nullptr;
    lock->abandoned = true;

    struct hrt_session_lock_output *lo;
    wl_list_for_each(lo, &lock->outputs, link) {
        wlr_scene_rect_set_color(lo->background, dark_red);
    }
    lock_focus(lock, nullptr);
}

static void handle_new_lock(struct wl_listener *listener, void *data) {
    struct hrt_server *server =
        wl_container_of(listener, server, new_session_lock);
    struct wlr_session_lock_v1 *wlr_lock = data;

    if (server->session_lock) {
        if (!server->session_lock->abandoned) {
            wlr_log(WLR_ERROR, "Refusing a session lock: already locked");
            wlr_session_lock_v1_destroy(wlr_lock);
            return;
        }
        // A new locker takes over from the one that went away:
        session_lock_destroy(server->session_lock);
    }

    struct hrt_session_lock *lock = calloc(1, sizeof(*lock));
    if (!lock) {
        wlr_log(WLR_ERROR, "Could not allocate a session lock");
        wlr_session_lock_v1_destroy(wlr_lock);
        return;
    }
    lock->server = server;
    lock->lock   = wlr_lock;
    wl_list_init(&lock->outputs);

    struct wlr_output_layout_output *l_output;
    wl_list_for_each(l_output, &server->output_layout->outputs, link) {
        struct hrt_output *output = l_output->output->data;
        if (output) {
            lock_output_create(lock, output);
        }
    }

    lock->new_surface.notify = handle_new_surface;
    wl_signal_add(&wlr_lock->events.new_surface, &lock->new_surface);
    lock->unlock.notify = handle_unlock;
    wl_signal_add(&wlr_lock->events.unlock, &lock->unlock);
    lock->destroy.notify = handle_lock_destroy;
    wl_signal_add(&wlr_lock->events.destroy, &lock->destroy);

    server->session_lock   = lock;
    server->session_locked = true;
    // Nothing but a lock surface may have the focus from now on. The
    // focused window also stops looking focused; Lisp focuses it again
    // after the unlock.
    struct wlr_surface *previous =
        server->seat.seat->keyboard_state.focused_surface;
    if (previous) {
        struct wlr_xdg_toplevel *toplevel =
            wlr_xdg_toplevel_try_from_wlr_surface(previous);
        if (toplevel) {
            wlr_xdg_toplevel_set_activated(toplevel, false);
        }
    }
    lock_focus(lock, nullptr);
    hrt_seat_reset_view_under(&server->seat);

    wlr_log(WLR_INFO, "Session locked");
    wlr_session_lock_v1_send_locked(wlr_lock);
    if (server->session_lock_callbacks &&
        server->session_lock_callbacks->locked) {
        server->session_lock_callbacks->locked();
    }
}

void hrt_session_lock_add_output(struct hrt_server *server,
                                 struct hrt_output *output) {
    if (server->session_lock) {
        lock_output_create(server->session_lock, output);
    }
}

void hrt_session_lock_arrange(struct hrt_server *server) {
    if (!server->session_lock) {
        return;
    }
    struct hrt_session_lock_output *lo;
    wl_list_for_each(lo, &server->session_lock->outputs, link) {
        lock_output_reconfigure(lo);
    }
}

void hrt_session_lock_set_callbacks(
    struct hrt_server *server,
    const struct hrt_session_lock_callbacks *callbacks) {
    server->session_lock_callbacks = callbacks;
}

bool hrt_session_locked(struct hrt_server *server) {
    return server->session_locked;
}

bool hrt_session_lock_init(struct hrt_server *server) {
    server->session_lock_manager =
        wlr_session_lock_manager_v1_create(server->wl_display);
    if (!server->session_lock_manager) {
        wlr_log(WLR_ERROR, "Could not create the session lock manager");
        return false;
    }
    server->new_session_lock.notify = handle_new_lock;
    wl_signal_add(&server->session_lock_manager->events.new_lock,
                  &server->new_session_lock);
    return true;
}

void hrt_session_lock_finish(struct hrt_server *server) {
    if (server->session_lock) {
        session_lock_destroy(server->session_lock);
    }
    wl_list_remove(&server->new_session_lock.link);
}
