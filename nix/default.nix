{ sources ? import ./sources.nix, system ? __currentSystem }:
with {
  overlay = self: super: {
    inherit (import sources.niv { }) niv;
    inherit (import sources.cardano-wallet { gitrev = sources.cardano-wallet.rev; }) cardano-wallet-jormungandr;
    inherit (import sources.nixpkgs-unstable {}) crystal;
    packages = self.callPackages ./packages.nix { };
    inherit (import sources.iohk-nix { }) jormungandrLib;
    jormungandrEnv = self.jormungandrLib.environments.${self.globals.environment};
    globals = import ../globals.nix;
    terranix = self.callPackage sources.terranix {};
    terraform = super.terraform.withPlugins (plugins: with plugins; [ aws null nixos ]);

    inherit ((import sources.jormungandr-nix { inherit (self.globals) environment; }).scripts)
      janalyze sendFunds delegateStake createStakePool checkTxStatus;
    inherit (self.jormungandrLib.packages.master) jormungandr jcli;

    explorerFrontend = (import sources.jormungandr-nix {}).explorerFrontend;

    nixops = (import (sources.nixops-core + "/release.nix") {
      nixpkgs = super.path;
      p = (p:
        let
          pluginSources = with sources; [ nixops-packet nixops-libvirtd ];
          plugins = map (source: p.callPackage (source + "/release.nix") { })
            pluginSources;
        in [ p.aws ] ++ plugins);
    }).build.${system};
  };
};
import sources.nixpkgs {
  overlays = [ overlay ];
  inherit system;
  config = { };
}
