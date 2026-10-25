#include <wayland-util.h>
#include <wlr/util/log.h>
#include <stdio.h>
#include <stdlib.h>

#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <xkbcommon/xkbcommon-keysyms.h>
#include <xkbcommon/xkbcommon-names.h>
#include <wlr/types/wlr_seat.h>

#include <wlr/backend/multi.h>
#include <wlr/backend/session.h>
#include <wlr/types/wlr_keyboard.h>

#include <hrt/hrt_server.h>
#include <hrt/hrt_input.h>
#include <hrt/hrt_session_lock.h>

#include "idle_impl.h"

static size_t seat_translate_keysyms(struct hrt_seat *seat,
                                     xkb_keycode_t keycode,
                                     const xkb_keysym_t **keysyms,
                                     uint32_t *modifiers) {
    struct wlr_keyboard *keyboard = &seat->keyboard_group->keyboard;
    *modifiers                    = wlr_keyboard_get_modifiers(keyboard);
    xkb_mod_mask_t consumed       = xkb_state_key_get_consumed_mods2(
        keyboard->xkb_state, keycode, XKB_CONSUMED_MODE_XKB);
    *modifiers = *modifiers & ~consumed;

    return xkb_state_key_get_syms(keyboard->xkb_state, keycode, keysyms);
}

/*
 * The keysyms of KEYCODE at the first level of its layout, with every
 * modifier held, for keybindings written as s-S-2 rather than s-at:
 * tried when the translated keysyms (at, shift consumed) bind nothing.
 */
static size_t seat_raw_keysyms(struct hrt_seat *seat, xkb_keycode_t keycode,
                               const xkb_keysym_t **keysyms,
                               uint32_t *modifiers) {
    struct wlr_keyboard *keyboard = &seat->keyboard_group->keyboard;
    *modifiers                    = wlr_keyboard_get_modifiers(keyboard);
    xkb_layout_index_t layout =
        xkb_state_key_get_layout(keyboard->xkb_state, keycode);
    return xkb_keymap_key_get_syms_by_level(keyboard->keymap, keycode, layout,
                                            0, keysyms);
}

static bool execute_hardcoded_bindings(struct hrt_server *server,
                                       const xkb_keysym_t *pressed_keysyms,
                                       uint32_t modifiers, size_t keysyms_len) {
    for (size_t i = 0; i < keysyms_len; ++i) {
        xkb_keysym_t keysym = pressed_keysyms[i];

        if (keysym >= XKB_KEY_XF86Switch_VT_1 &&
            keysym <= XKB_KEY_XF86Switch_VT_12) {
            if (wlr_backend_is_multi(server->backend)) {
                struct wlr_session *session = server->session;
                if (session) {
                    wlr_log(WLR_DEBUG, "Changing session");
                    unsigned vt = keysym - XKB_KEY_XF86Switch_VT_1 + 1;
                    wlr_session_change_vt(session, vt);
                }
            }
            return true;
        }
    }
    return false;
}

static void seat_handle_key(struct wl_listener *listener, void *data) {
    struct hrt_seat *seat = wl_container_of(listener, seat, keyboard_key);
    struct wlr_keyboard_key_event *event = data;
    struct hrt_server *server            = seat->server;

    hrt_idle_notify_activity(seat);

    xkb_keycode_t keycode = event->keycode + 8;

    bool handled = false;

    // While the session is locked, keys go to the lock surface only; no
    // keybinding runs.
    if (event->state == WL_KEYBOARD_KEY_STATE_PRESSED &&
        !hrt_session_locked(server)) {
        const xkb_keysym_t *translated_keysyms;
        uint32_t translated_modifiers;
        size_t translated_keysyms_len = seat_translate_keysyms(
            seat, keycode, &translated_keysyms, &translated_modifiers);

        struct hrt_keypress_info key_info = {
            .keysyms      = translated_keysyms,
            .keysyms_len  = translated_keysyms_len,
            .modifiers    = translated_modifiers,
            .wl_key_state = event->state,
        };
        handled = seat->callbacks->keyboard_keypress_event(seat, &key_info);

        if (!handled) {
            const xkb_keysym_t *raw_keysyms;
            uint32_t raw_modifiers;
            size_t raw_keysyms_len =
                seat_raw_keysyms(seat, keycode, &raw_keysyms, &raw_modifiers);
            bool same = raw_keysyms_len == translated_keysyms_len &&
                raw_modifiers == translated_modifiers;
            for (size_t i = 0; same && i < raw_keysyms_len; ++i) {
                same = raw_keysyms[i] == translated_keysyms[i];
            }
            if (!same && raw_keysyms_len > 0) {
                struct hrt_keypress_info raw_info = {
                    .keysyms      = raw_keysyms,
                    .keysyms_len  = raw_keysyms_len,
                    .modifiers    = raw_modifiers,
                    .wl_key_state = event->state,
                };
                handled =
                    seat->callbacks->keyboard_keypress_event(seat, &raw_info);
            }
        }

        if (!handled) {
            handled = execute_hardcoded_bindings(server, translated_keysyms,
                                                 translated_modifiers,
                                                 translated_keysyms_len);
        }
    }

    // TODO: I don't know if this condition is correct
    if (!handled) {
        wlr_seat_keyboard_notify_key(seat->seat, event->time_msec,
                                     event->keycode, event->state);
    } else {
        wlr_log(WLR_DEBUG, "Keypress handled by keybinding");
    }
}

static void seat_handle_modifiers(struct wl_listener *listener, void *data) {
    wlr_log(WLR_DEBUG, "Keyboard modifier pressed");
    struct hrt_seat *seat = wl_container_of(listener, seat, keyboard_modifiers);

    wlr_seat_keyboard_notify_modifiers(
        seat->seat, &seat->keyboard_group->keyboard.modifiers);
}

static void handle_keyboard_destroy(struct wl_listener *listener, void *data) {
    struct wlr_keyboard *kb = data;
    wlr_log(WLR_DEBUG, "hrt keyboard destroyed %p", kb);
    struct hrt_seat *seat = wl_container_of(listener, seat, destroy.keyboard);

    xkb_context_unref(seat->xkb_context);
    wl_list_remove(&seat->keyboard_key.link);
    wl_list_remove(&seat->keyboard_modifiers.link);
    wl_list_remove(&seat->destroy.keyboard.link);
}

void hrt_keyboard_init(struct hrt_seat *seat) {
    seat->keyboard_group    = wlr_keyboard_group_create();
    struct wlr_keyboard *kb = &seat->keyboard_group->keyboard;

    struct xkb_rule_names rules = {0};
    seat->xkb_context           = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    struct xkb_keymap *keymap   = xkb_map_new_from_names(
        seat->xkb_context, &rules, XKB_KEYMAP_COMPILE_NO_FLAGS);
    wlr_keyboard_set_keymap(kb, keymap);
    xkb_keymap_unref(keymap);

    seat->keyboard_key.notify = seat_handle_key;
    wl_signal_add(&kb->events.key, &seat->keyboard_key);
    seat->keyboard_modifiers.notify = seat_handle_modifiers;
    wl_signal_add(&kb->events.modifiers, &seat->keyboard_modifiers);

    wlr_seat_set_keyboard(seat->seat, kb);

    seat->destroy.keyboard.notify = handle_keyboard_destroy;
    wl_signal_add(&kb->base.events.destroy, &seat->destroy.keyboard);
}

void hrt_keyboard_destroy(struct hrt_seat *seat) {
    wlr_keyboard_group_destroy(seat->keyboard_group);
}
