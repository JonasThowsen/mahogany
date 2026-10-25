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
  restart of the compositor (`lisp stop` / `lisp start`); Lisp changes do not.
- `nix flake check` — what CI runs: the test suite, a headless smoke test
  of the built compositor, and `clang-format --dry-run`. `nix build`
  gives `result/bin/mahogany`, the compositor wrapped with its libraries
  (`.#heart` builds the C backend alone). The two vendored Lisp libraries
  are pinned flake inputs there, since a flake does not see submodules.

## Working in a running image

Use slynk-cli (`lisp`). Read its guide first, in particular the section
"The main thread":
https://github.com/JonasThowsen/slynk-cli/blob/main/docs/guide.md

`.slynk-cli.sexp` configures it: `lisp start` loads the `mahogany`
system and then runs the compositor, `mahogany::main`, in the image's
main thread (`:main`); `lisp stop` ends it; `.slynk-cli/image.log` is
its log. Without a display, export the headless variables above before
`lisp start`. Then:

- `lisp eval --main FORM` — evaluate on the main thread, through
  `hrt:run-in-main-thread` (`:main-thread-dispatcher`). **Use `--main`
  for anything that touches compositor state or calls into heart**
  (`hrt:` functions, foreign pointers, the frame tree, groups, outputs,
  views): wlroots is single-threaded, and a plain `lisp eval` runs in a
  thread of its own. `(hrt:with-main-thread () ...)` does the same from
  code.
- `lisp eval` reads in `cl-user`: pass `--package mahogany` so the local
  nicknames `tree:`, `hrt:` read, or write `mahogany/tree:`; a reader
  error shows as "Stream: STRING-INPUT-STREAM" and the form never runs.
- `lisp compile FILE:LINE` — recompile one form (as `C-c C-c`); safe from
  any thread, the next event uses the new definition.
- `defcommand` defines a generic function of that name (cl-interactive),
  so a `defun` may not share a command's name: `(defun take-screenshot)`
  + `(defcommand screenshot-area)`, never `(defun screenshot-area)` too.
  The load errors with "already names an ordinary function".
- A new file in `mahogany.asd`: `lisp eval '(load (compile-file "lisp/x.lisp"))'`
  gets it into the running image. `(asdf:load-system "mahogany")` works
  too, but when the load errors (a `defcommand` whose name a `defun`
  already has, say) the image is left half-loaded and every `--main`
  eval fails: fix the file, then `lisp stop` / `lisp start`.
- An error on the main thread (inside a wlroots callback) pauses the
  compositor and shows up in `lisp status` as a paused evaluation "in
  the main thread": `frame`, `eval --in`, `backtrace`, `restart-frame`,
  `return` and `restart` work on it.
- **Never `abort` a main-thread pause**, never unwind through a C
  callback: `lisp abort` refuses it. Use `restart-frame` after fixing the
  function, `return`, or a restart the code offers (the work queue
  offers `continue`, callbacks offer `callback-exit`).
- The compositor renders and takes input only while the main thread
  runs: a main-thread pause freezes the session until it is resumed, so
  when the compositor is the user's session, be quick. Long `--main`
  forms also stall it.
- The Lisp side is compiled with `(debug 3)` by `lisp start`; heart is
  built `-O0 -g -Werror`.

- `make` and `make test` always run `ninja -C build/heart`. With C
  changes and the compositor running from `build/heart/libheart.so`, check
  them in a meson build directory of their own (`meson setup DIR heart`,
  then tests with that directory first in `LD_LIBRARY_PATH`), and rebuild
  `build/heart` when the compositor restarts.
- Heart's bindings are generated: after changing a header, run `make
  lisp/heart/hrt-bindings.lisp` (cl-bindgen, in the dev shell) and review
  the diff; list a new header in `cffi/hrt-bindings.yml`. Lisp allocates
  `struct hrt_server` from its mirror, so `server-init` refuses to start
  when the mirror's size differs from C's.
- Format C with `clang-format -i FILE` (in the dev shell, `.clang-format`
  at the root); the tree is clean under `clang-format --dry-run --Werror`.

## Tracking work: ferdig

Features, bugs and what is being worked on are in ferdig, Jonas's
tracker, as the project «Mahogany» (customer «Jonas»), reached over MCP
(the claude.ai connector «Ferdig», https://ferdig.jonasnettside.no/mcp).
Name yourself «Claude i mahogany» (or where you run, as «Claude i
mahogany, remote»):

- Before working: `projects_list`, then `items_list` with the project's
  id; the planned items are next.
- `items_start` the item you work on, with `agent`; `comments_add` what
  you did, with the commit; `items_finish` when it is done and verified.
- New work found on the way is a new item (`items_create`), not a
  detour. A question for Jonas is `questions_ask` with `asks` "jonas",
  then `questions_wait`.

## Layout

- `heart/src/*.c`, `heart/include/hrt/*.h` — the C backend; keep it a
  thin wrapper, policy lives in Lisp. Bindings in
  `lisp/heart/hrt-bindings.lisp` are generated with cl-bindgen from
  `cffi/*.yml` (`make lisp/heart/hrt-bindings.lisp`) when headers change.
- `heart/src/session_lock.c` — ext-session-lock: while a locker such as
  swaylock holds the session, heart shows only lock surfaces, routes input
  to them alone and refuses other focus; Lisp hears `locked`/`unlocked`
  (`state-locked-p`).
- `lisp/heart/` — the Lisp side of heart: server, event-loop work queue
  and timers, outputs, views, layer shell, subprocesses, messages.
- `lisp/draw/` — cairo/pango bindings and drawing helpers (`draw:`); with
  `hrt:make-canvas` and `hrt:with-canvas-frame` (`lisp/heart/canvas.lisp`)
  Lisp draws bars, menus and OSDs directly into an output's scene.
- `lisp/tree/` — the frame tree; `lisp/group.lisp`, `lisp/state.lisp` —
  groups and compositor state; `lisp/command.lisp`, `lisp/key-bindings.lisp`,
  `lisp/kmap-modes.lisp` — commands and keymaps; `lisp/main.lisp` — startup
  and the user's `~/.config/mahogany/init.lisp`.
- Lisp desktop pieces, one file each: `lisp/mode-line.lisp` (bar and
  its modules), `lisp/menu.lisp` + `lisp/launcher.lisp` (menus, launcher
  modes), `lisp/osd.lisp`, `lisp/idle.lisp`, `lisp/system-status.lisp`
  (battery, network, volume, brightness via subprocesses),
  `lisp/themes.lisp` (`define-theme`/`set-theme`, presets, wallpaper
  canvas), `lisp/screenshot.lisp`, `lisp/scratchpad.lisp`,
  `lisp/outputs.lisp` (focus/windows between outputs), `lisp/layouts.lisp`
  (`define-layout`, per-group tiling layouts), `lisp/default-bindings.lisp`
  (SUPER keys, `*autostart*`), `lisp/xwayland.lisp` (xwayland-satellite),
  `lisp/lid.lisp` (lid switch: lock, internal screen off/on). Each has a
  manual page in `doc/manual/`.
- `doc/manual/` — user manual (org); `doc/devel/` — design notes.
