{
  lib,
  stdenv,
  callPackage,
  src,
  zig_0_16,
  pkg-config,
  wayland-scanner,
  wayland-protocols,
  autoPatchelfHook,
  wayland,
  libxkbcommon,
  fontconfig,
  freetype,
  harfbuzz,
  dbus,
  libGL,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "monstar";
  version = "0.2.0";
  inherit src;

  # Complete Zig dep tree fetched by nix (ghostty's build.zig.zon.nix plus
  # monstar's direct deps). We fetch with nix rather than `zig build`: zig
  # 0.16's async HTTP fetcher can't run in the nix sandbox, and `--system`
  # loops forever on this graph. Placed in ./zig-pkg, where zig 0.16 reads
  # vendored packages, so the build runs fully offline.
  deps = callPackage ./deps.nix { name = "monstar-zig-pkg-${finalAttrs.version}"; };

  nativeBuildInputs = [
    zig_0_16
    pkg-config
    wayland-scanner
    wayland-protocols
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
  ];

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
