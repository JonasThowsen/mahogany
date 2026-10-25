#ifndef HRT_HRT_SESSION_LOCK_H
#define HRT_HRT_SESSION_LOCK_H

#include <stdbool.h>

struct hrt_server;

/**
 * ext-session-lock: a client such as swaylock locks the session. While
 * it is locked, every output shows only the client's lock surface (or
 * black until it has one), keyboard and pointer input go only to those
 * surfaces, and nothing else can take the focus. Should the client go
 * away without unlocking, the session stays locked and blank, red, until
 * another client locks it.
 **/
struct hrt_session_lock_callbacks {
    //! A client locked the session. May be NULL.
    void (*locked)(void);
    //! The client unlocked the session; the compositor is usable again.
    //! May be NULL.
    void (*unlocked)(void);
};

/**
 * Set the callbacks run when the session is locked and unlocked. The
 * struct must outlive the server.
 **/
void hrt_session_lock_set_callbacks(
    struct hrt_server *server,
    const struct hrt_session_lock_callbacks *callbacks);

/**
 * Whether the session is locked, including left locked by a client that
 * went away.
 **/
bool hrt_session_locked(struct hrt_server *server);

#endif
