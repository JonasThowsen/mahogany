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
  };

  outputs =
    { self, nixpkgs, slynk-cli }:
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
    in
    {
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
                # Running the compositor nested or on a TTY
                foot
                fuzzel
                rofi
                wlr-randr
                wayland-utils
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
              # libheart.so is built into build/heart; libwlroots and libxkbcommon
              # are loaded by name through CFFI.
              export LD_LIBRARY_PATH="$PWD/build/heart:${pkgs.wlroots}/lib:${pkgs.libxkbcommon}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            '';
          };
        }
      );

      formatter = forAllSystems (pkgs: pkgs.nixfmt);
    };
}
