{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
    inherit (import sources.cardano-wallet { gitrev = sources.cardano-wallet.rev; }) cardano-wallet-jormungandr;
    inherit (import sources.nixpkgs-unstable {}) crystal terraform;
    inherit (import sources.iohk-nix { }) jormungandrLib;
    packages = self.callPackages ./packages.nix { inherit sources; };
    jormungandrEnv = self.jormungandrLib.environments.itn_rewards_v1;
    terranix = self.callPackage sources.terranix {};
    ami-sync = self.callPackage ./pkgs/ami-sync {};

    inherit ((import sources.jormungandr-nix { environment = "itn_rewards_v1"; }).scripts)
      janalyze sendFunds delegateStake createStakePool checkTxStatus;
    inherit (self.jormungandrLib.packages.master) jormungandr jcli;
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
