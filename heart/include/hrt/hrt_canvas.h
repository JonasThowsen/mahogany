#ifndef HRT_HRT_CANVAS_H
#define HRT_HRT_CANVAS_H

#include <stdbool.h>
#include <stdint.h>
#include <cairo.h>
#include <wlr/types/wlr_scene.h>

/**
 * A rectangle in the scene graph that the compositor draws into itself,
 * with cairo: a bar, a menu, an on-screen display.
 *
 * Draw a frame by calling hrt_canvas_begin, drawing on the surface it
 * returns, and calling hrt_canvas_commit to show it. Each frame is a new
 * buffer, so a frame being drawn never shows half finished.
 **/
struct hrt_canvas;
struct hrt_server;

/**
 * Pointer input over canvases. X and Y are in the canvas's coordinates,
 * layout pixels from its top left corner. While the pointer is over a
 * canvas, no client has pointer focus. May be NULL, each of them.
 **/
struct hrt_canvas_callbacks {
    //! The pointer entered the canvas, or moved over it.
    void (*pointer_motion)(struct hrt_canvas *canvas, double x, double y);
    //! The pointer left the canvas (or the canvas went away under it).
    void (*pointer_leave)(struct hrt_canvas *canvas);
    //! A button (a linux input code, BTN_LEFT...) went down or up.
    void (*pointer_button)(struct hrt_canvas *canvas, double x, double y,
                           uint32_t button, bool pressed);
    //! The wheel moved: DELTA pixels, vertically or horizontally.
    void (*pointer_axis)(struct hrt_canvas *canvas, double x, double y,
                         bool vertical, double delta);
};

/**
 * Set the callbacks for pointer input over every canvas. The struct must
 * outlive the server.
 **/
void hrt_canvas_set_callbacks(struct hrt_server *server,
                              const struct hrt_canvas_callbacks *callbacks);

/**
 * Create a canvas as a child of PARENT. It shows nothing until the first
 * hrt_canvas_commit.
 *
 * If PARENT is destroyed, the canvas stays valid but shows nothing, and
 * the other functions do nothing; it still has to be destroyed.
 **/
struct hrt_canvas *hrt_canvas_create(struct wlr_scene_tree *parent);

void hrt_canvas_destroy(struct hrt_canvas *canvas);

/**
 * Start a new frame of WIDTH x HEIGHT, in layout coordinates, for an
 * output with the given SCALE. Return the cairo surface to draw it on:
 * its device scale is set, so draw in layout coordinates. The surface
 * belongs to the canvas; don't destroy it.
 *
 * Return NULL if the frame could not be made. Starting a frame drops one
 * that was started and not committed.
 **/
cairo_surface_t *hrt_canvas_begin(struct hrt_canvas *canvas, int width,
                                  int height, double scale);

/**
 * Show the frame started by hrt_canvas_begin in place of the previous
 * one. Return false if there is no frame to show.
 **/
bool hrt_canvas_commit(struct hrt_canvas *canvas);

/**
 * Place the canvas at X,Y relative to its parent.
 **/
void hrt_canvas_set_position(struct hrt_canvas *canvas, int x, int y);

void hrt_canvas_set_enabled(struct hrt_canvas *canvas, bool enabled);

#endif
