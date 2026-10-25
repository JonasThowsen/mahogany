# Mahogany

A tiling Wayland compositor modeled after StumpWM: a thin C backend
(`heart/`, wrapping wlroots) and the window manager itself in Common Lisp
(`lisp/`). This fork is being grown into a complete Lisp desktop (bar,
launcher, lock screen, idle, networking, audio, monitors), developed
live in the running image. See `CONTRIBUTING.md` for commit message
style (`area: Imperative summary`) and formatting.

## Environment

Everything comes from the Nix dev shell: `nix develop`, or automatically
through direnv (`.envrc` is `use flake`). It provides SBCL with the Lisp
libraries, meson/ninja, wlroots 0.20, `LD_LIBRARY_PATH` for
`build/heart/libheart.so`, and the `lisp` command (the `slynk-cli` flake
input, github:JonasThowsen/slynk-cli, which brings its own Slynk). `MAHOGANY_NIX=1` makes the Makefile skip
its Quicklisp step. Two Lisp libraries are git submodules under
`dependencies/` (`git submodule update --init dependencies/cl-xkbcommon
dependencies/cl-interactive`); the wlroots submodule is not needed.

- `make` — build heart (meson, into `build/heart/`) and the executable
  `build/mahogany`.
- `make test` — the fiasco test suite (`test/`, `mahogany-test.asd`).
- `make run` — run the compositor with the debugger enabled. Under a
  Wayland or X11 session it opens nested in a window. Without one:
  `WLR_BACKENDS=headless WLR_RENDERER=pixman ./build/mahogany -q -l debug`
  (set `XDG_RUNTIME_DIR` to a writable directory).
- `ninja -C build/heart` — rebuild only the C side. C changes need a
  restart of the compositor; Lisp changes do not.

## Working in a running image

Use slynk-cli: `lisp start` loads the `mahogany` system into an image,
then `lisp eval`, `lisp compile FILE:LINE` (one form, as `C-c C-c`), and
its debugger (`frame`, `eval --in`, `restart-frame`). Read
https://github.com/JonasThowsen/slynk-cli/blob/main/docs/guide.md first. `.slynk-cli.sexp` configures it.

Rules that are specific to a compositor:

- **wlroots is single-threaded.** Everything that touches compositor
  state or calls into heart (`hrt:` functions, anything holding a
  foreign pointer, the frame tree, groups, outputs, views) must run on
  the main thread. `lisp eval` runs in its own thread, so wrap such
  forms: `(hrt:with-main-thread () ...)` (`lisp/heart/server.lisp`).
  Redefining a function with `lisp compile` is safe from any thread; the
  next event uses the new definition.
- **Never `abort` an evaluation paused inside the main thread**, and
  never unwind through a C callback: use `restart-frame`, `return`, or
  the `continue` restart that the work queue offers. Aborting unwinds
  wlroots' stack and leaves it inconsistent.
- The compositor keeps rendering only while the main thread runs. A
  main-thread debugger pause freezes input and output until it is
  resumed, so when the compositor is the user's session, be quick.
- The Lisp side is compiled with `(debug 3)` by `lisp start`; heart is
  built `-O0 -g -Werror`.

## Layout

- `heart/src/*.c`, `heart/include/hrt/*.h` — the C backend; keep it a
  thin wrapper, policy lives in Lisp. Bindings in
  `lisp/heart/hrt-bindings.lisp` are generated with cl-bindgen from
  `cffi/*.yml` (`make lisp/heart/hrt-bindings.lisp`) when headers change.
- `lisp/heart/` — the Lisp side of heart: server, event-loop work queue
  and timers, outputs, views, layer shell, subprocesses, messages.
- `lisp/tree/` — the frame tree; `lisp/group.lisp`, `lisp/state.lisp` —
  groups and compositor state; `lisp/command.lisp`, `lisp/key-bindings.lisp`,
  `lisp/kmap-modes.lisp` — commands and keymaps; `lisp/main.lisp` — startup
  and the user's `~/.config/mahogany/init.lisp`.
- `doc/manual/` — user manual (org); `doc/devel/` — design notes.
