{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
