#include <assert.h>
#include <stdlib.h>

#include <wayland-server-core.h>
#include <wayland-util.h>
#include <wlr/util/log.h>

#include "hrt/hrt_input.h"
#include "hrt/hrt_output.h"
#include "hrt/hrt_scene.h"
#include "hrt/hrt_server.h"
#include "xdg_impl.h"
#include "hrt/hrt_view.h"
#include "view_impl.h"

#include <wlr/types/wlr_xdg_shell.h>
#include <wlr/util/edges.h>
#include <wlr/types/wlr_xdg_decoration_v1.h>
#include <wlr/types/wlr_xdg_activation_v1.h>

/**
 * The view of a toplevel's xdg_surface: hrt_view_init puts the view's
 * xdg scene tree in the surface's data, and the view in that tree's node.
 **/
static struct hrt_view *view_from_xdg_surface(struct wlr_xdg_surface *surface) {
    if (surface->role != WLR_XDG_SURFACE_ROLE_TOPLEVEL || !surface->data) {
        return nullptr;
    }
    struct wlr_scene_tree *tree = surface->data;
    return tree->node.data;
}

/**
 * Ask the view's client to draw no decorations. A configure can only be
 * scheduled once the toplevel is initialized, so this runs both when the
 * decoration appears and at the initial commit, whichever comes last.
 **/
static void view_apply_decoration_mode(struct hrt_view *view) {
    if (view->decoration && view->xdg_toplevel->base->initialized) {
        wlr_xdg_toplevel_decoration_v1_set_mode(
            view->decoration, WLR_XDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE);
    }
}

static void handle_decoration_request_mode(struct wl_listener *listener,
                                           void *data) {
    struct hrt_view *view =
        wl_container_of(listener, view, decoration_request_mode);
    view_apply_decoration_mode(view);
}

static void view_forget_decoration(struct hrt_view *view) {
    if (view->decoration) {
        wl_list_remove(&view->decoration_request_mode.link);
        wl_list_remove(&view->decoration_destroy.link);
        view->decoration = nullptr;
    }
}

static void handle_decoration_destroy(struct wl_listener *listener,
                                      void *data) {
    struct hrt_view *view = wl_container_of(listener, view, decoration_destroy);
    view_forget_decoration(view);
}

static void handle_new_xdg_decoration(struct wl_listener *listener,
                                      void *data) {
    struct wlr_xdg_toplevel_decoration_v1 *decoration = data;
    struct hrt_view *view = view_from_xdg_surface(decoration->toplevel->base);
    if (!view) {
        wlr_log(WLR_ERROR, "xdg-decoration for a toplevel without a view");
        return;
    }
    view_forget_decoration(view);
    view->decoration                     = decoration;
    view->decoration_request_mode.notify = handle_decoration_request_mode;
    wl_signal_add(&decoration->events.request_mode,
                  &view->decoration_request_mode);
    view->decoration_destroy.notify = handle_decoration_destroy;
    wl_signal_add(&decoration->events.destroy, &view->decoration_destroy);
    view_apply_decoration_mode(view);
}

static void handle_request_activate(struct wl_listener *listener, void *data) {
    struct hrt_server *server =
        wl_container_of(listener, server, request_activate);
    const struct wlr_xdg_activation_v1_request_activate_event *event = data;
    struct wlr_xdg_surface *xdg_surface =
        wlr_xdg_surface_try_from_wlr_surface(event->surface);
    if (!xdg_surface) {
        return;
    }
    struct hrt_view *view = view_from_xdg_surface(xdg_surface);
    // A request for a view that is not mapped yet is a startup
    // notification; nothing to focus:
    if (!view || !xdg_surface->surface->mapped) {
        return;
    }
    if (server->view_callbacks->request_activate) {
        server->view_callbacks->request_activate(view);
    }
}

static void handle_xdg_toplevel_map(struct wl_listener *listener, void *data) {
    wlr_log(WLR_DEBUG, "XDG Toplevel Mapped!");
    struct hrt_view *view = wl_container_of(listener, view, map);
    // The callback should be sending a configure event:
    view->callbacks->view_mapped(view);
}

static void handle_xdg_toplevel_unmap(struct wl_listener *listener,
                                      void *data) {
    wlr_log(WLR_DEBUG, "XDG Toplevel unmapped!");
    struct hrt_view *view = wl_container_of(listener, view, unmap);
    view->callbacks->view_unmapped(view);
}

static void handle_xdg_toplevel_request_maximize(struct wl_listener *listener,
                                                 void *data) {
    wlr_log(WLR_DEBUG, "XDG Toplevel request maximize");
    struct hrt_view *view = wl_container_of(listener, view, request_maximize);
    // The protocol specifies that after this request is made, we must
    // send a configure event.
    if (view->callbacks->request_maximize) {
        view->callbacks->request_maximize(view);
    } else {
        hrt_view_send_configure(view);
    }
}

static void handle_xdg_toplevel_request_minimize(struct wl_listener *listener,
                                                 void *data) {
    wlr_log(WLR_DEBUG, "XDG Toplevel request maximize");
    struct hrt_view *view = wl_container_of(listener, view, request_minimize);
    // The protocol specifies that after this request is made, we must
    // send a configure event.
    if (view->callbacks->request_minimize) {
        view->callbacks->request_minimize(view);
    } else {
        hrt_view_send_configure(view);
    }
}

static void handle_xdg_toplevel_request_fullscreen(struct wl_listener *listener,
                                                   void *data) {
    struct hrt_view *view = wl_container_of(listener, view, request_fullscreen);
    struct wlr_xdg_toplevel *toplevel = view->xdg_toplevel;

    if (!toplevel->base->surface->mapped) {
        hrt_view_send_configure(view);
        return;
    }

    struct hrt_output *requested_output    = NULL;
    struct wlr_xdg_toplevel_requested *req = &toplevel->requested;
    if (req->fullscreen && req->fullscreen_output &&
        req->fullscreen_output->data) {
        requested_output = req->fullscreen_output->data;
    }
    bool changed = view->callbacks->request_fullscreen(view, requested_output,
                                                       req->fullscreen);
    wlr_log(WLR_DEBUG, "Fullscreen request fufilled: %d", changed);
    // If no change was made, we still need to send a configure event;
    // send a blank one to show that nothing happened:
    if (!changed) {
        hrt_view_send_configure(view);
    }
}

static void handle_xdg_toplevel_destroy(struct wl_listener *listener,
                                        void *data) {
    wlr_log(WLR_DEBUG, "XDG Toplevel Destroyed!");
    struct hrt_view *view = wl_container_of(listener, view, destroy);

    view->callbacks->view_destroyed(view);

    wl_list_remove(&view->map.link);
    wl_list_remove(&view->unmap.link);
    wl_list_remove(&view->destroy.link);
    wl_list_remove(&view->commit.link);
    wl_list_remove(&view->request_fullscreen.link);
    wl_list_remove(&view->request_maximize.link);
    wl_list_remove(&view->request_minimize.link);
    wl_list_remove(&view->new_popup.link);
    // The decoration outlives this signal handler by a moment: wlroots
    // destroys it from the same toplevel destroy signal, after us.
    view_forget_decoration(view);

    hrt_view_cleanup(view);
    free(view);
}

static void handle_xdg_toplevel_commit(struct wl_listener *listener,
                                       void *data) {
    struct hrt_view *view = wl_container_of(listener, view, commit);
    struct wlr_xdg_toplevel *const toplevel = view->xdg_toplevel;
    if (toplevel->base->initial_commit) {
        wlr_xdg_toplevel_set_tiled(toplevel,
                                   WLR_EDGE_TOP | WLR_EDGE_BOTTOM |
                                       WLR_EDGE_LEFT | WLR_EDGE_RIGHT);
        view_apply_decoration_mode(view);
        view->callbacks->new_view(view);
    } else if (view->xdg_surface->surface->mapped) {
        const uint32_t committed = toplevel->base->current.committed;
        if (committed & WLR_XDG_SURFACE_STATE_WINDOW_GEOMETRY) {
            view->callbacks->view_size_changed(view);
        }
    }
}

static void handle_new_xdg_popup(struct wl_listener *listener, void *data);

static struct hrt_view *
create_view_from_xdg_surface(struct wlr_xdg_toplevel *xdg_toplevel,
                             struct hrt_server *server) {
    struct hrt_view *view = calloc(1, sizeof(struct hrt_view));
    if (!view) {
        wlr_log(WLR_ERROR, "Failed to allocate hrt_view object for toplevel %p",
                xdg_toplevel);
        return nullptr;
    }
    view->xdg_toplevel                  = xdg_toplevel;
    struct wlr_xdg_surface *xdg_surface = xdg_toplevel->base;
    // TODO: Maybe remove view->xdg_surface? We can get to it via the toplevel.
    view->xdg_surface = xdg_surface;
    view->callbacks   = server->view_callbacks;
    view->server      = server;

    // Using the scene root here is not as efficient as it could be,
    // as we then need to reparent the node in the initial commit.
    // Depending on how many nodes are in the tree,
    // it could be costly. It may also cause flickering, but I haven't
    // observed that.
    hrt_view_init(view, server->scene_root->normal);

    view->map.notify = handle_xdg_toplevel_map;
    wl_signal_add(&xdg_surface->surface->events.map, &view->map);
    view->unmap.notify = handle_xdg_toplevel_unmap;
    wl_signal_add(&xdg_surface->surface->events.unmap, &view->unmap);
    view->destroy.notify = handle_xdg_toplevel_destroy;
    wl_signal_add(&xdg_toplevel->events.destroy, &view->destroy);
    view->commit.notify = handle_xdg_toplevel_commit;
    wl_signal_add(&xdg_toplevel->base->surface->events.commit, &view->commit);
    view->new_popup.notify = handle_new_xdg_popup;
    wl_signal_add(&xdg_surface->events.new_popup, &view->new_popup);

    // Swaywm registers these when the toplevel is mapped, but I don't think  that should make
    // a difference:
    view->request_fullscreen.notify = handle_xdg_toplevel_request_fullscreen;
    wl_signal_add(&xdg_toplevel->events.request_fullscreen,
                  &view->request_fullscreen);
    view->request_maximize.notify = &handle_xdg_toplevel_request_maximize;
    wl_signal_add(&xdg_toplevel->events.request_maximize,
                  &view->request_maximize);
    view->request_minimize.notify = &handle_xdg_toplevel_request_minimize;
    wl_signal_add(&xdg_toplevel->events.request_minimize,
                  &view->request_minimize);

    return view;
}

static void popup_unconstrain(struct hrt_xdg_popup *popup) {
    struct hrt_view *view           = popup->view;
    struct wlr_xdg_popup *wlr_popup = popup->xdg_popup;

    struct hrt_output *output = view->callbacks->get_view_output(view);
    if (!output) {
        wlr_log(WLR_ERROR, "Could not get output to unconstrain popup.");
        return;
    }
    int x, y;
    hrt_output_position(output, &x, &y);
    int width, height;
    hrt_output_resolution(output, &width, &height);

    struct wlr_box output_toplevel_sx_box = {
        .x      = x,
        .y      = y,
        .width  = width,
        .height = height,
    };

    wlr_xdg_popup_unconstrain_from_box(wlr_popup, &output_toplevel_sx_box);
}

static void handle_xdg_popup_reposition(struct wl_listener *listener,
                                        void *data) {
    struct hrt_xdg_popup *popup = wl_container_of(listener, popup, reposition);
    popup_unconstrain(popup);
}

static void handle_xdg_popup_commit(struct wl_listener *listener, void *data) {
    struct hrt_xdg_popup *popup = wl_container_of(listener, popup, commit);
    if (popup->xdg_popup->base->initial_commit) {
        // wlr_xdg_surface_schedule_configure(popup->xdg_popup->base);
        popup_unconstrain(popup);
    }
}

static void handle_xdg_popup_destroy(struct wl_listener *listener, void *data) {
    struct hrt_xdg_popup *popup = wl_container_of(listener, popup, destroy);

    wl_list_remove(&popup->destroy.link);
    wl_list_remove(&popup->commit.link);
    wl_list_remove(&popup->new_popup.link);
    wl_list_remove(&popup->reposition.link);

    free(popup);
}

static void handle_popup_new_xdg_popup(struct wl_listener *listener,
                                       void *data);

static struct hrt_xdg_popup *create_popup(struct hrt_view *view,
                                          struct wlr_xdg_popup *xdg_popup,
                                          struct wlr_scene_tree *parent) {
    struct hrt_xdg_popup *popup = calloc(1, sizeof(*popup));
    if (!popup) {
        wlr_log(WLR_ERROR, "Failed to allocated hrt_xdg_popup");
        return nullptr;
    }
    popup->view      = view;
    popup->xdg_popup = xdg_popup;
    popup->scene     = wlr_scene_xdg_surface_create(parent, xdg_popup->base);

    if (!popup->scene) {
        wlr_log(WLR_ERROR, "Failed to allocate XDG surface for popup");
        free(popup);
        return nullptr;
    }
    xdg_popup->base->data = popup->scene;

    popup->commit.notify = handle_xdg_popup_commit;
    wl_signal_add(&xdg_popup->base->surface->events.commit, &popup->commit);

    popup->destroy.notify = handle_xdg_popup_destroy;
    wl_signal_add(&xdg_popup->events.destroy, &popup->destroy);

    popup->new_popup.notify = handle_popup_new_xdg_popup;
    wl_signal_add(&xdg_popup->base->events.new_popup, &popup->new_popup);
    popup->reposition.notify = handle_xdg_popup_reposition;
    wl_signal_add(&xdg_popup->events.reposition, &popup->reposition);

    return popup;
}

static void handle_popup_new_xdg_popup(struct wl_listener *listener,
                                       void *data) {
    struct hrt_xdg_popup *parent = wl_container_of(listener, parent, new_popup);
    struct wlr_xdg_popup *xdg_popup = data;
    create_popup(parent->view, xdg_popup, parent->scene);
}

static void handle_new_xdg_popup(struct wl_listener *listener, void *data) {
    wlr_log(WLR_DEBUG, "New xdg popup received");
    struct hrt_view *view = wl_container_of(listener, view, new_popup);
    struct wlr_xdg_popup *xdg_popup = data;
    create_popup(view, xdg_popup, view->xdg_scene);
}

static void handle_new_xdg_toplevel(struct wl_listener *listener, void *data) {
    wlr_log(WLR_DEBUG, "New XDG Toplevel received");
    struct hrt_server *server =
        wl_container_of(listener, server, new_xdg_toplevel);
    struct wlr_xdg_toplevel *toplevel = data;
    // Initialization occurs in two steps so the consumer can place the view
    // where it needs to go; in order to create a scene tree node, it must have
    // a parent. We don't have it until the callback.
    create_view_from_xdg_surface(toplevel, server);
}

static void check_callbacks(const struct hrt_view_callbacks *callbacks) {
    assert(callbacks->new_view != nullptr);
    assert(callbacks->view_size_changed != nullptr);
    assert(callbacks->view_mapped != nullptr);
    assert(callbacks->view_unmapped != nullptr);
    assert(callbacks->request_minimize != nullptr);
    assert(callbacks->request_maximize != nullptr);
    assert(callbacks->view_destroyed != nullptr);
    assert(callbacks->request_fullscreen != nullptr);
    assert(callbacks->get_view_output != nullptr);
}

bool hrt_xdg_shell_init(struct hrt_server *server) {
    check_callbacks(server->view_callbacks);
    server->xdg_shell = wlr_xdg_shell_create(server->wl_display, 3);
    if (!server->xdg_shell) {
        wlr_log(WLR_ERROR, "Could not initialize wlr_xdg_shell");
        return false;
    }

    server->new_xdg_toplevel.notify = handle_new_xdg_toplevel;
    wl_signal_add(&server->xdg_shell->events.new_toplevel,
                  &server->new_xdg_toplevel);

    server->xdg_decoration_manager =
        wlr_xdg_decoration_manager_v1_create(server->wl_display);
    if (!server->xdg_decoration_manager) {
        wlr_log(WLR_ERROR, "Could not create the xdg-decoration manager");
        return false;
    }
    server->new_xdg_decoration.notify = handle_new_xdg_decoration;
    wl_signal_add(
        &server->xdg_decoration_manager->events.new_toplevel_decoration,
        &server->new_xdg_decoration);

    server->xdg_activation = wlr_xdg_activation_v1_create(server->wl_display);
    if (!server->xdg_activation) {
        wlr_log(WLR_ERROR, "Could not create xdg-activation");
        return false;
    }
    server->request_activate.notify = handle_request_activate;
    wl_signal_add(&server->xdg_activation->events.request_activate,
                  &server->request_activate);
    return true;
}

void hrt_xdg_shell_destroy(struct hrt_server *server) {
    wl_list_remove(&server->new_xdg_toplevel.link);
    wl_list_remove(&server->new_xdg_decoration.link);
    wl_list_remove(&server->request_activate.link);
}
