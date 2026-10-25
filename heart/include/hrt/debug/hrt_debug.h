#ifndef HRT_DEBUG_HRT_DEBUG
#define HRT_DEBUG_HRT_DEBUG

#include <hrt/hrt_server.h>
#include <stdbool.h>
#include <stdint.h>

bool hrt_add_output(const struct hrt_server *server);

/**
 * Move the pointer to LX,LY in layout coordinates and press or release
 * BUTTON (a linux input code), as if an input device had. For tests on a
 * compositor without input devices.
 **/
void hrt_debug_pointer_warp(struct hrt_server *server, double lx, double ly);
void hrt_debug_pointer_button(struct hrt_server *server, uint32_t button,
                              bool pressed);

#endif
