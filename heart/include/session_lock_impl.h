#pragma once

#include "hrt/hrt_server.h"
#include "hrt/hrt_session_lock.h"

bool hrt_session_lock_init(struct hrt_server *server);
void hrt_session_lock_finish(struct hrt_server *server);

/**
 * Give OUTPUT a lock surface slot (and a blank backdrop) if the session
 * is locked: for outputs that appear while it is.
 **/
void hrt_session_lock_add_output(struct hrt_server *server,
                                 struct hrt_output *output);

/**
 * Resize the backdrops and lock surfaces to their outputs: after the
 * output layout changed.
 **/
void hrt_session_lock_arrange(struct hrt_server *server);
