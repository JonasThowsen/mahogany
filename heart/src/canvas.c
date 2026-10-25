#include <math.h>
#include <stdlib.h>

#include <wlr/util/log.h>

#include <hrt/hrt_canvas.h>
#include "render/cairo_buffer.h"
#include "render/scale_util.h"

struct hrt_canvas {
    // NULL once the node has been destroyed along with its parent:
    struct wlr_scene_buffer *scene_buffer;
    // The frame between hrt_canvas_begin and hrt_canvas_commit:
    struct hrt_cairo_buffer *pending;
    int pending_width, pending_height;
    double pending_scale;

    struct wl_listener node_destroy;
};

static void handle_node_destroy(struct wl_listener *listener, void *data) {
    struct hrt_canvas *canvas =
        wl_container_of(listener, canvas, node_destroy);
    wl_list_remove(&canvas->node_destroy.link);
    canvas->scene_buffer = nullptr;
}

static void drop_pending(struct hrt_canvas *canvas) {
    if (canvas->pending) {
        wlr_buffer_drop(&canvas->pending->base);
        canvas->pending = nullptr;
    }
}

struct hrt_canvas *hrt_canvas_create(struct wlr_scene_tree *parent) {
    struct hrt_canvas *canvas = calloc(1, sizeof(*canvas));
    if (!canvas) {
        wlr_log(WLR_ERROR, "Could not allocate hrt_canvas");
        return nullptr;
    }

    canvas->scene_buffer = wlr_scene_buffer_create(parent, nullptr);
    if (!canvas->scene_buffer) {
        wlr_log(WLR_ERROR, "Could not create scene buffer for hrt_canvas");
        free(canvas);
        return nullptr;
    }

    canvas->node_destroy.notify = handle_node_destroy;
    wl_signal_add(&canvas->scene_buffer->node.events.destroy,
                  &canvas->node_destroy);
    return canvas;
}

void hrt_canvas_destroy(struct hrt_canvas *canvas) {
    drop_pending(canvas);
    if (canvas->scene_buffer) {
        // Runs handle_node_destroy, which removes the listener:
        wlr_scene_node_destroy(&canvas->scene_buffer->node);
    }
    free(canvas);
}

cairo_surface_t *hrt_canvas_begin(struct hrt_canvas *canvas, int width,
                                  int height, double scale) {
    drop_pending(canvas);
    if (!canvas->scene_buffer || width <= 0 || height <= 0 || scale <= 0) {
        return nullptr;
    }

    struct hrt_cairo_buffer *buffer = hrt_cairo_buffer_create(
        (int)ceil(width * scale), (int)ceil(height * scale));
    if (!buffer) {
        return nullptr;
    }
    cairo_surface_set_device_scale(buffer->surface, scale, scale);

    canvas->pending        = buffer;
    canvas->pending_width  = width;
    canvas->pending_height = height;
    canvas->pending_scale  = scale;
    return buffer->surface;
}

bool hrt_canvas_commit(struct hrt_canvas *canvas) {
    struct hrt_cairo_buffer *buffer = canvas->pending;
    if (!buffer || !canvas->scene_buffer) {
        return false;
    }
    canvas->pending = nullptr;

    cairo_surface_flush(buffer->surface);
    wlr_scene_buffer_set_buffer(canvas->scene_buffer, &buffer->base);
    wlr_scene_buffer_set_dest_size(canvas->scene_buffer, canvas->pending_width,
                                   canvas->pending_height);
    wlr_scene_buffer_set_filter_mode(
        canvas->scene_buffer,
        compute_scale_filter(&buffer->base, canvas->pending_scale));
    // The scene buffer holds its own lock on the buffer now, and lets go
    // of it when the next frame replaces it:
    wlr_buffer_drop(&buffer->base);
    return true;
}

void hrt_canvas_set_position(struct hrt_canvas *canvas, int x, int y) {
    if (canvas->scene_buffer) {
        wlr_scene_node_set_position(&canvas->scene_buffer->node, x, y);
    }
}

void hrt_canvas_set_enabled(struct hrt_canvas *canvas, bool enabled) {
    if (canvas->scene_buffer) {
        wlr_scene_node_set_enabled(&canvas->scene_buffer->node, enabled);
    }
}
