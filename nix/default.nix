{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
    inherit (import sources.nixpkgs-unstable {}) crystal terraform;
    packages = self.callPackages ./packages.nix { inherit sources; };
    terranix = self.callPackage sources.terranix {};
    ami-sync = self.callPackage ./pkgs/ami-sync {};
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
