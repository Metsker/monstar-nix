{
  description = "monstar (rockorager's Zig/Wayland terminal) packaged for Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Tracks upstream main; flake.lock pins the exact rev (reproducible).
    # deps.nix is generated from the locked rev's build.zig.zon.
    # Bump: `nix flake update monstar-src`, then regenerate deps.nix.
    monstar-src = {
      url = "github:rockorager/monstar";
      flake = false;
    };
  };

  outputs =
    { self, nixpkgs, monstar-src }:
    let
      systems = [ "x86_64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in
    {
      packages = forAll (system: {
        default = nixpkgs.legacyPackages.${system}.callPackage ./package.nix {
          src = monstar-src;
        };
      });

      apps = forAll (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/monstar";
        };
      });
    };
}
