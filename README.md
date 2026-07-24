# monstar-nix

A Nix flake that packages [monstar](https://github.com/rockorager/monstar) —
rockorager's Zig/Wayland terminal.
Unofficial.

## Use

Try it without installing:

```sh
nix run github:Metsker/monstar-nix
```

Install into your profile:

```sh
nix profile install github:Metsker/monstar-nix
```

As an input in a NixOS / home-manager flake:

```nix
inputs.monstar = {
  url = "github:Metsker/monstar-nix";
  inputs.nixpkgs.follows = "nixpkgs"; # build against your own nixpkgs
};
```

```nix
# home-manager
home.packages = [ inputs.monstar.packages.${pkgs.system}.default ];
# or NixOS
environment.systemPackages = [ inputs.monstar.packages.${pkgs.system}.default ];
```

Outputs: `packages.x86_64-linux.default` and `apps.x86_64-linux.default`.

## Versioning

Tracks monstar's upstream `main`; `flake.lock` pins the exact commit, so builds
are reproducible. The pin advances on its own — a daily GitHub Action bumps it
to the latest upstream commit and commits the result.

To pull a newer monstar into **your own** config, update the input under the
name *you* gave it (`monstar` in the example above):

```sh
nix flake update monstar
```

`monstar-src` is this repo's *internal* input (the upstream source). You only
touch it when bumping this repo's own pin, which also requires regenerating
`deps.nix` — see [Regenerating deps.nix](#regenerating-depsnix).

## Caveats

- **x86_64-linux only** — no other systems are declared.
- **Built from source, no binary cache.** The first build compiles ghostty-vt
  and monstar; the ReleaseFast LLVM pass is largely single-threaded, so expect
  several minutes (cached afterwards).
- **Baseline CPU** (`-Dcpu=baseline`) for a portable binary, not native-tuned.
- **Needs working OpenGL at runtime.** `autoPatchelfHook` wires libGL, Wayland,
  fontconfig, etc., but the GL driver itself comes from the host (on NixOS,
  enable `hardware.graphics`).
- **Dependencies are vendored by Nix, not fetched by Zig.** `deps.nix` is
  fetched with Nix's own fetchers and staged into `zig-pkg/`, because zig 0.16's
  HTTP fetcher can't run inside the Nix sandbox and `zig build --system` hangs
  on monstar's lazy ghostty dependency graph. **Consequence:** a plain
  `nix flake update monstar-src` is not enough when a bump changes monstar's
  dependency set — `deps.nix` must be regenerated too (one command, below), or
  the build fails.
monstar's own deps (`nix-prefetch-git` for git deps, `nix store prefetch-file`
for raw tarballs — the same fetchers `deps.nix` uses), and splices them in. It
needs `curl`, `jq`, and `nix` on `PATH`. If monstar ever adds an https
*package-dir* dep (not a raw tarball), the script stops and asks for a new case
rather than emitting a wrong hash.
