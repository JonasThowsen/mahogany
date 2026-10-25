#ifndef HRT_HRT_IDLE_H
#define HRT_HRT_IDLE_H

#include <stdbool.h>
#include <stdint.h>

struct hrt_server;
struct hrt_idle_timeout;

/**
 * Idle timeouts for the compositor's own policy (locking, screens off),
 * beside the idle-notify protocol that serves clients. A timeout's idle
 * function runs when there has been no input for its duration, and its
 * resume function at the first input after that; input restarts every
 * timeout. While a visible client inhibits idling, timeouts do not run
 * out.
 **/
typedef void (*hrt_idle_timeout_func)(struct hrt_idle_timeout *timeout,
                                      void *data);

/**
 * Add a timeout of TIMEOUT_MSEC. RESUME may be NULL. DATA is handed to
 * both functions. Returns NULL when it could not be made.
 **/
struct hrt_idle_timeout *hrt_idle_timeout_add(struct hrt_server *server,
                                              uint32_t timeout_msec,
                                              hrt_idle_timeout_func idle,
                                              hrt_idle_timeout_func resume,
                                              void *data);

void hrt_idle_timeout_destroy(struct hrt_idle_timeout *timeout);

/**
 * Milliseconds since the last input, or since the start.
 **/
uint64_t hrt_idle_milliseconds(struct hrt_server *server);

/**
 * Whether a visible client asks that the user not be considered idle.
 **/
bool hrt_idle_inhibited(struct hrt_server *server);

/**
 * Count as input: restart the timeouts and run the resume functions of
 * those that had run out. For waking up from Lisp, say on a lid opening.
 **/
void hrt_idle_activity(struct hrt_server *server);

#endif
