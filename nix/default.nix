{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
    inherit (import sources.cardano-wallet { gitrev = sources.cardano-wallet.rev; }) cardano-wallet-jormungandr;
    inherit (import sources.nixpkgs-unstable {}) crystal;
    inherit (import sources.iohk-nix { }) jormungandrLib;
    packages = self.callPackages ./packages.nix { inherit sources; };
    jormungandrEnv = self.jormungandrLib.environments.${self.globals.environment};
    globals = import ../globals.nix;
    terranix = self.callPackage sources.terranix {};
    terraform = super.terraform.withPlugins (plugins: with plugins; [ aws null nixos ]);
    ami-sync = self.callPackage ./pkgs/ami-sync {};

    inherit ((import sources.jormungandr-nix { inherit (self.globals) environment; }).scripts)
      janalyze sendFunds delegateStake createStakePool checkTxStatus;
    inherit (self.jormungandrLib.packages.master) jormungandr jcli;
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
