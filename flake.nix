{
  description = "WireGuard with sops-nix integration NixOS module + simple watchdog";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    flake-utils,
    nixpkgs,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in {
        packages = {
          sccache-dist = pkgs.callPackage ./lib/mkDerivationSccacheDist.nix {};
          sccache = pkgs.callPackage ./lib/mkDerivationSccache.nix {};
        };
      }
    )
    // {
      nixosModules = {
        sccache = {pkgs, ...}: {
          imports = [(import ./module_sccache.nix)];
          nixpkgs.overlays = [
            (_final: prev: {
              inherit (self.packages.${prev.system}) sccache;
            })
          ];
        };

        sccache_dist_scheduler = {pkgs, ...}: {
          imports = [(import ./module_sccache_dist_scheduler.nix)];
          nixpkgs.overlays = [
            (_final: prev: {
              inherit (self.packages.${prev.system}) sccache-dist;
            })
          ];
        };

        sccache_dist_build_server = {pkgs, ...}: {
          imports = [(import ./module_sccache_dist_build_server.nix)];
          nixpkgs.overlays = [
            (_final: prev: {
              inherit (self.packages.${prev.system}) sccache-dist;
            })
          ];
        };

        default = {...}: {
          imports = [
            self.nixosModules.sccache
            self.nixosModules.sccache_dist_scheduler
            self.nixosModules.sccache_dist_build_server
          ];
        };
      };
      # For backwards compatibility
      nixosModule = self.nixosModules.default;
    };
}
