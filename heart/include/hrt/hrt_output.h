#ifndef HRT_HRT_OUTPUT_H
#define HRT_HRT_OUTPUT_H

#include "hrt/hrt_scene.h"
#include <wayland-server.h>

#include <wlr/types/wlr_output.h>
#include <wlr/util/box.h>

#include <hrt/hrt_server.h>

struct hrt_scene_output;

struct hrt_output_config {
    double scale;
    // Use the exact settings instead of the closest supported match:
    bool custom_mode;
    int width, height;
    float refresh_rate;
    // Place the output in a specific spot in the layout based on the
    // given X,Y coordinates:
    bool custom_position;
    // These are in layout coordinates, not pixel coordinates:
    int x, y;
    bool enabled;
};

struct hrt_output {
    struct wlr_output *wlr_output;
    struct hrt_server *server;
    struct hrt_scene_output *scene;
    struct wlr_scene_output *wlr_scene;

    struct wlr_box usable_area;
    // Space kept free at each edge, in layout coordinates, for what the
    // compositor draws itself, such as a bar. See hrt_output_set_reserved.
    int reserved_top, reserved_right, reserved_bottom, reserved_left;

    struct wl_list layer_surfaces;

    struct wl_listener request_state;
    struct wl_listener frame;
    struct wl_listener destroy;
    // Turned off by hrt_output_set_power; still part of the layout.
    bool powered_off;
};

struct hrt_output_callbacks {
    void (*output_added)(struct hrt_output *output);
    void (*output_removed)(struct hrt_output *output);
    void (*output_layout_changed)();
};

bool hrt_output_configure(struct hrt_output *output,
                          struct hrt_output_config *config);

bool hrt_output_configure_atomic(struct hrt_output *outputs[],
                                 struct hrt_output_config configs[],
                                 const size_t length);

/**
 * Get the effective output resolution of the output that can be used to
 * set the width and height of views.
 **/
void hrt_output_resolution(struct hrt_output *output, int *width, int *height);

void hrt_output_position(struct hrt_output *output, int *x, int *y);

/**
 * Keep space free at the edges of the output, in layout coordinates, the
 * way a layer surface's exclusive zone does: the usable area shrinks by
 * it, layer surfaces are arranged inside what is left, and the
 * layers_reconfigured callback runs if the usable area changed.
 * Negative values count as 0.
 **/
void hrt_output_set_reserved(struct hrt_output *output, int top, int right,
                             int bottom, int left);

/**
 * Whether the output is in use: configured on, whether or not its power
 * is off at the moment.
 **/
bool hrt_output_enabled(struct hrt_output *output);

/**
 * Turn the output's power off, or on again. It keeps its place in the
 * layout and its windows; this is for idling, not for configuration.
 * Returns false if the output refused.
 **/
bool hrt_output_set_power(struct hrt_output *output, bool on);

bool hrt_output_powered_off(struct hrt_output *output);

/**
 * The output's scale: layout coordinates times it are pixels.
 **/
double hrt_output_scale(struct hrt_output *output);

char *hrt_output_name(struct hrt_output *output);

char *hrt_output_make(struct hrt_output *output);

char *hrt_output_model(struct hrt_output *output);

char *hrt_output_serial(struct hrt_output *output);

#endif
