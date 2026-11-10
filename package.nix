{
  lib,
  stdenv,
  callPackage,
  src,
  zig_0_17,
  pkg-config,
  wayland-scanner,
  wayland-protocols,
  ncurses,
  autoPatchelfHook,
  wayland,
  libxkbcommon,
  fontconfig,
  freetype,
  harfbuzz,
  dbus,
  libGL,
  vulkan-headers,
  vulkan-loader,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "monstar";
  version = "1.1.0";
  inherit src;

  # Complete Zig dep tree fetched by nix (ghostty's deps/packages.nix plus
  # monstar's direct deps). We fetch with nix rather than `zig build`: zig's
  # HTTP fetcher can't run in the nix sandbox, and `--system` fails on
  # ghostty's `.path` deps (0.16 hung on them). Placed in ./zig-pkg, where
  # zig 0.16+ reads vendored packages, so the build runs fully offline.
  deps = callPackage ./deps.nix { name = "monstar-zig-pkg-${finalAttrs.version}"; };

  nativeBuildInputs = [
    zig_0_17
    pkg-config
    wayland-scanner
    wayland-protocols
    ncurses # provides `tic`, which the build runs to compile the terminfo
    autoPatchelfHook
  ];

  buildInputs = [
    wayland
    libxkbcommon
    fontconfig
    freetype
    harfbuzz
    dbus
    libGL
    vulkan-headers
  ];

  # renderer = vulkan dlopens libvulkan.so.1, which nothing links, so autoPatchelf would miss it.
  runtimeDependencies = [ vulkan-loader ];

  postConfigure = ''
    cp -rL ${finalAttrs.deps} zig-pkg
    chmod -R u+w zig-pkg
  '';

  # Full control of zig flags; baseline CPU keeps the binary portable.
  dontSetZigDefaultFlags = true;
  zigBuildFlags = [
    "-Doptimize=ReleaseFast"
    "-Dcpu=baseline"
  ];

  meta = {
    description = "rockorager's Zig/Wayland terminal emulator";
    homepage = "https://github.com/rockorager/monstar";
    license = lib.licenses.mit;
    mainProgram = "monstar";
    platforms = lib.platforms.linux;
  };
})
