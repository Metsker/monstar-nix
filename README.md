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
inputs.monstar.url = "github:Metsker/monstar-nix";
```

```nix
# home-manager
home.packages = [ inputs.monstar.packages.${pkgs.system}.default ];
# or NixOS
environment.systemPackages = [ inputs.monstar.packages.${pkgs.system}.default ];
```

Outputs: `packages.x86_64-linux.default` and `apps.x86_64-linux.default`.

## Binary cache

CI pushes every build to [Cachix](https://monstar.cachix.org), so you can
fetch the binary instead of compiling. This flake declares the cache in its
`nixConfig`, so `nix run` / `nix build` offer to use it. For a NixOS or
home-manager config, add it to your nix settings:

```nix
nix.settings = {
  extra-substituters = [ "https://monstar.cachix.org" ];
  extra-trusted-public-keys = [
    "monstar.cachix.org-1:75M9ke+wZlmUcNsXpDae9793qhdRgtlNUEu/mW7u20c="
  ];
};
```

Cache hits require building against **this flake's pinned nixpkgs**, so add the
input *without* `inputs.nixpkgs.follows` (as shown above): a different nixpkgs
changes the store path and falls back to a source build.

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
