{
  description = "Mahogany: a StumpWM-like Wayland compositor in Common Lisp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    # The `lisp` command: a running image, debugger and compile-a-form for
    # coding agents (and people), driven from the shell.
    slynk-cli = {
      url = "github:JonasThowsen/slynk-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # The two Lisp libraries vendored as git submodules under dependencies/,
    # at the submodules' commits, for the builds and checks (a flake does not
    # see submodule contents).
    cl-xkbcommon = {
      url = "github:sdilts/cl-xkbcommon/5e24ddaa10019ce3a261b6eb07e0a1cf12d317ef";
      flake = false;
    };
    cl-interactive = {
      url = "github:sdilts/cl-interactive/0705552e4dcfe1519f298aeadc94ea9f7277626d";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      slynk-cli,
      cl-xkbcommon,
      cl-interactive,
    }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # The Common Lisp libraries mahogany.asd and mahogany-test.asd depend on,
      # apart from cl-xkbcommon and cl-interactive, which are git submodules
      # under dependencies/ and found by init-build-env.lisp.
      lispDependencies =
        ps: with ps; [
          alexandria
          cl-ansi-text
          cl-colors2
          terminfo
          adopt
          iterate
          atomics
          fset
          bordeaux-threads
          float-features
          trivial-garbage
          cffi
          cffi-grovel
          closer-mop
          # tests
          fiasco
          cl-mock
          # interactive development
          slynk
        ];

      # cl-bindgen generates lisp/heart/*-bindings.lisp from heart's headers
      # (make lisp/heart/hrt-bindings.lisp). It is not in nixpkgs, and the
      # committed bindings use options (enum-constants, make-inline with a
      # feature flag) that its PyPI release lacks, so this is git master,
      # on nixpkgs' libclang Python bindings.
      clBindgen =
        pkgs:
        pkgs.python3Packages.buildPythonApplication {
          pname = "cl_bindgen";
          version = "1.6.0-unstable-2026-06-25";
          pyproject = true;
          src = pkgs.fetchFromGitHub {
            owner = "sdilts";
            repo = "cl-bindgen";
            rev = "bad33f070cd51aa4f721c8edf96804b4f8547f8d";
            hash = "sha256-zmdZzFq9TUmVd+H0GuLyNt2s7AN5EKl8jI94yi3UnZk=";
          };
          build-system = [ pkgs.python3Packages.setuptools ];
          dependencies = with pkgs.python3Packages; [
            libclang
            pyyaml
          ];
          # libclang parses the headers without a compiler driver, so it
          # needs told where clang's own headers are (cl-bindgen asks
          # `clang --print-resource-dir`) and where glibc's and
          # wayland-protocols' are; pkg-config supplies the rest.
          makeWrapperArgs = [
            "--prefix"
            "PATH"
            ":"
            "${pkgs.llvmPackages.clang-unwrapped}/bin"
            "--prefix"
            "CPATH"
            ":"
            "${pkgs.glibc.dev}/include:${pkgs.wayland-protocols}/include"
          ];
          doCheck = false;
          pythonImportsCheck = [ "cl_bindgen" ];
        };

      # What heart (the C backend) is built with.
      heartBuildInputs =
        pkgs: with pkgs; [
          wlroots
          wayland
          wayland-protocols
          libxkbcommon
          libinput
          libdrm
          pixman
          cairo
          pango
          libxcb
        ];

      # The shared libraries CFFI loads by name at run time.
      runtimeLibraryPath =
        pkgs: heart:
        pkgs.lib.makeLibraryPath [
          heart
          pkgs.wlroots
          pkgs.libxkbcommon
          pkgs.cairo
          pkgs.pango.out
          pkgs.glib.out
        ];

      # heart, the C backend, as the Makefile builds it: -O0 -g, -Werror.
      heart =
        pkgs:
        pkgs.stdenv.mkDerivation {
          pname = "mahogany-heart";
          version = "0.1";
          src = ./heart;
          nativeBuildInputs = with pkgs; [
            meson
            ninja
            pkg-config
            wayland-scanner
          ];
          buildInputs = heartBuildInputs pkgs;
          mesonBuildType = "debug";
          mesonFlags = [ "-Dexample=false" ];
          hardeningDisable = [ "fortify" ];
        };

      # The Lisp side with the vendored libraries in place, as the checkout
      # has them. init-build-env.lisp writes compiled files under its root,
      # so builds copy this somewhere writable first.
      lispSource =
        pkgs:
        pkgs.runCommand "mahogany-lisp-source" { } ''
          mkdir -p $out/dependencies
          cp -r ${./lisp} $out/lisp
          cp -r ${./test} $out/test
          cp ${./mahogany.asd} $out/mahogany.asd
          cp ${./mahogany-test.asd} $out/mahogany-test.asd
          cp ${./init-build-env.lisp} $out/init-build-env.lisp
          cp ${./run-tests.lisp} $out/run-tests.lisp
          cp ${./build-mahogany.lisp} $out/build-mahogany.lisp
          cp -r ${cl-xkbcommon} $out/dependencies/cl-xkbcommon
          cp -r ${cl-interactive} $out/dependencies/cl-interactive
        '';

      # The compositor: the SBCL executable, wrapped so it finds heart and
      # the other libraries.
      mahogany =
        pkgs:
        let
          heart' = heart pkgs;
        in
        pkgs.stdenv.mkDerivation {
          pname = "mahogany";
          version = "0.0.1";
          src = lispSource pkgs;
          nativeBuildInputs = [
            (pkgs.sbcl.withPackages lispDependencies)
            pkgs.pkg-config
            pkgs.makeWrapper
          ];
          # cl-xkbcommon grovels libxkbcommon's headers with the C compiler:
          buildInputs = heartBuildInputs pkgs ++ [ heart' ];
          dontConfigure = true;
          # The executable is SBCL's runtime with the Lisp image appended;
          # strip and patchelf would cut the image off.
          dontStrip = true;
          dontPatchELF = true;
          buildPhase = ''
            runHook preBuild
            export HOME=$TMPDIR
            export LD_LIBRARY_PATH=${runtimeLibraryPath pkgs heart'}
            sbcl --non-interactive --load build-mahogany.lisp
            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            install -Dm755 build/mahogany $out/libexec/mahogany
            makeWrapper $out/libexec/mahogany $out/bin/mahogany \
              --prefix LD_LIBRARY_PATH : ${runtimeLibraryPath pkgs heart'}
            runHook postInstall
          '';
          meta.mainProgram = "mahogany";
        };

      # Fonts for pango in the sandbox: the tests draw text, the compositor's
      # mode-line too.
      fontsConf = pkgs: pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts ]; };
    in
    {
      packages = forAllSystems (pkgs: {
        heart = heart pkgs;
        mahogany = mahogany pkgs;
        default = mahogany pkgs;
      });

      checks = forAllSystems (
        pkgs:
        let
          heart' = heart pkgs;
        in
        {
          # The fiasco test suite, as make test runs it. runCommandCC: cffi-grovel
          # compiles cl-xkbcommon's grovel file with the C compiler.
          test =
            pkgs.runCommandCC "mahogany-test"
              {
                nativeBuildInputs = [
                  (pkgs.sbcl.withPackages lispDependencies)
                  pkgs.pkg-config
                ];
                buildInputs = heartBuildInputs pkgs ++ [ heart' ];
                FONTCONFIG_FILE = fontsConf pkgs;
              }
              ''
                cp -r ${lispSource pkgs} src && chmod -R u+w src && cd src
                export HOME=$TMPDIR
                export LD_LIBRARY_PATH=${runtimeLibraryPath pkgs heart'}
                sbcl --non-interactive --load run-tests.lisp
                touch $out
              '';

          # The compositor starts headless and serves its protocols.
          smoke =
            pkgs.runCommand "mahogany-smoke"
              {
                nativeBuildInputs = [
                  (mahogany pkgs)
                  pkgs.wayland-utils
                ];
                FONTCONFIG_FILE = fontsConf pkgs;
              }
              ''
                export HOME=$TMPDIR
                export XDG_RUNTIME_DIR=$TMPDIR/run
                mkdir -p $XDG_RUNTIME_DIR
                export WLR_BACKENDS=headless WLR_RENDERER=pixman
                mahogany -q -l debug > mahogany.log 2>&1 &
                pid=$!
                for i in $(seq 1 100); do
                  grep -q "Running on Wayland socket" mahogany.log && break
                  kill -0 $pid || { cat mahogany.log; exit 1; }
                  sleep 0.2
                done
                socket=$(grep -oE "wayland-[0-9]+" mahogany.log | head -1)
                # Give the first frame and the mode-line a moment:
                sleep 2
                WAYLAND_DISPLAY=$socket wayland-info > globals
                for global in wl_compositor xdg_wm_base zwlr_layer_shell_v1 \
                    zwlr_output_manager_v1 zxdg_decoration_manager_v1 \
                    xdg_activation_v1 wp_cursor_shape_manager_v1 \
                    ext_idle_notifier_v1 wp_presentation; do
                  grep -q "'$global'" globals || { echo "missing $global"; cat globals; exit 1; }
                done
                kill -0 $pid || { echo "the compositor died"; cat mahogany.log; exit 1; }
                ! grep -q "ERROR - Could not draw the mode-line" mahogany.log || { cat mahogany.log; exit 1; }
                kill $pid; wait $pid || true
                touch $out
              '';

          formatting =
            pkgs.runCommand "mahogany-formatting" { nativeBuildInputs = [ pkgs.clang-tools ]; } ''
              cd ${./.}
              clang-format --dry-run --Werror heart/src/*.c heart/src/render/*.c heart/include/hrt/*.h
              touch $out
            '';
        }
      );

      devShells = forAllSystems (
        pkgs:
        let
          sbcl = pkgs.sbcl.withPackages lispDependencies;
        in
        {
          default = pkgs.mkShell {
            packages =
              [
                sbcl
                slynk-cli.packages.${pkgs.stdenv.hostPlatform.system}.default
              ]
              ++ (with pkgs; [
                meson
                ninja
                pkg-config
                wayland-scanner
                gnumake
                clang-tools # clang-format, see .clang-format
                (clBindgen pkgs)
                # Running the compositor nested or on a TTY
                foot
                fuzzel
                rofi
                wlr-randr
                wayland-utils
                grim # screenshots, also of a headless compositor
              ])
              ++ heartBuildInputs pkgs;

            # init-build-env.lisp inherits ASDF's configuration, so the libraries
            # sbcl.withPackages registers are found; the dependency install step
            # of the Makefile (Quicklisp) is not needed.
            MAHOGANY_NIX = "1";

            # heart is built with -O0 -g and -Werror; glibc's _FORTIFY_SOURCE
            # warns without optimization, which Nix's hardening turns on.
            hardeningDisable = [ "fortify" ];

            shellHook = ''
              # libheart.so is built into build/heart; libwlroots, libxkbcommon and,
              # for drawing without heart (the tests), cairo, pango and gobject are
              # loaded by name through CFFI.
              export LD_LIBRARY_PATH="$PWD/build/heart:${pkgs.wlroots}/lib:${pkgs.libxkbcommon}/lib:${pkgs.cairo}/lib:${pkgs.pango.out}/lib:${pkgs.glib.out}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
