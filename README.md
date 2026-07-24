# monstar-nix

A Nix flake that packages [monstar](https://github.com/rockorager/monstar) —
rockorager's Zig/Wayland terminal — which ships no Nix packaging of its own.
Unofficial; not affiliated with upstream.

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
are reproducible. Bump to the latest upstream commit with:

```sh
nix flake update monstar-src
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
  dependency set — `deps.nix` must be regenerated too (one command, below), or
  the build fails.

## Regenerating deps.nix

`deps.nix` is ghostty's own `build.zig.zon.nix` (its full transitive tree, at
the ghostty commit monstar pins) plus monstar's direct deps. Bump and regenerate:

```sh
nix flake update monstar-src   # move the pin to latest monstar main
./update-deps.sh               # rewrite deps.nix + package.nix version for that pin
nix build                      # verify
```

A weekly GitHub Action (`.github/workflows/update-deps.yml`) runs exactly this,
verifies the result with `nix build`, and commits any change — so the pin stays
current on its own. Trigger it by hand from the repo's Actions tab too.

`update-deps.sh` reads the locked rev from `flake.lock`, fetches ghostty's
`build.zig.zon.nix` at the rev monstar pins, recomputes the Nix hashes for
monstar's own deps (`nix-prefetch-git` for git deps, `nix store prefetch-file`
for raw tarballs — the same fetchers `deps.nix` uses), and splices them in. It
needs `curl`, `jq`, and `nix` on `PATH`. If monstar ever adds an https
*package-dir* dep (not a raw tarball), the script stops and asks for a new case
rather than emitting a wrong hash.
