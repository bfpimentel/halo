{
  description = "halo: a widget runtime for macOS (bars, panels and HUDs written in TSX)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      # Version and hash of the published release zip; updated by scripts/bump-nix.sh.
      release = builtins.fromJSON (builtins.readFile ./nix/release.json);
    in
    {
      packages = forAllSystems (pkgs: rec {
        halo = pkgs.callPackage ./nix/package.nix { inherit release; };
        default = halo;
      });

      homeManagerModules.default = import ./nix/home-manager.nix self;
      darwinModules.default = import ./nix/darwin.nix self;

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.esbuild
            pkgs.bun
            pkgs.oxlint
            pkgs.oxfmt
          ];
        };
      });
    };
}
