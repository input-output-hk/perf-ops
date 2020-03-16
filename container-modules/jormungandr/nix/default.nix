{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
    inherit (import sources.iohk-nix { }) jormungandrLib;
    jormungandrEnv = self.jormungandrLib.environments.qa;

    inherit ((import sources.jormungandr-nix { environment = "qa"; }).scripts)
      janalyze sendFunds delegateStake createStakePool checkTxStatus;
    inherit (self.jormungandrLib.packages.master) jormungandr jcli;
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
