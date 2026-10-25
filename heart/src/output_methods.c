#include <hrt/hrt_output.h>

#include "layer_shell_impl.h"

void hrt_output_resolution(struct hrt_output *output, int *width, int *height) {
    wlr_output_effective_resolution(output->wlr_output, width, height);
}

void hrt_output_position(struct hrt_output *output, int *x, int *y) {
    struct wlr_output_layout_output *l_output = wlr_output_layout_get(
        output->server->output_layout, output->wlr_output);
    *x = l_output->x;
    *y = l_output->y;
}

void hrt_output_set_reserved(struct hrt_output *output, int top, int right,
                             int bottom, int left) {
    output->reserved_top    = top > 0 ? top : 0;
    output->reserved_right  = right > 0 ? right : 0;
    output->reserved_bottom = bottom > 0 ? bottom : 0;
    output->reserved_left   = left > 0 ? left : 0;
    hrt_layer_shell_arrange_layers(output, true);
}

bool hrt_output_enabled(struct hrt_output *output) {
    return output->wlr_output->enabled;
}

double hrt_output_scale(struct hrt_output *output) {
    return output->wlr_output->scale;
}

char *hrt_output_name(struct hrt_output *output) {
    return output->wlr_output->name;
}

char *hrt_output_make(struct hrt_output *output) {
    return output->wlr_output->make;
}

char *hrt_output_model(struct hrt_output *output) {
    return output->wlr_output->model;
}

char *hrt_output_serial(struct hrt_output *output) {
    return output->wlr_output->serial;
}
