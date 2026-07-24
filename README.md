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
  inputs.nixpkgs.follows = "nixpkgs";
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
are reproducible. The pin advances on its own - a daily GitHub Action bumps it
to the latest upstream commit and commits the result.

To pull a newer monstar into your config, update the input under the
name *you* gave it (`monstar` in the example above):

```sh
nix flake update monstar
```

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
  dependency set — `deps.nix` must be regenerated too (run `./update-deps.sh`),
  or the build fails.
