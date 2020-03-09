{ pkgs, config, lib, ... }: let
  sources = import ../nix/sources.nix;
  iohkNix = import sources.iohk-nix {};
  cfg = config.services.cardano-node;
  selectedEnv = "shelley_staging";
in
{
  imports = [
    (sources.cardano-node + "/nix/nixos")
    ./container-common.nix
  ];

  networking.firewall = {
    allowedTCPPorts = [ cfg.port ];
  };

  services.cardano-node = {
    enable = true;
    extraArgs = [ "+RTS" "-N2" "-A10m" "-qg" "-qb" "-M3G" "-RTS" ];
    environment = selectedEnv;
    nodeConfig = iohkNix.cardanoLib.environments."${selectedEnv}".nodeConfig // {
      hasPrometheus = [ "0.0.0.0" 12798 ];
    };
    topology = iohkNix.cardanoLib.mkEdgeTopology {
      inherit (cfg) port;
      edgeHost = iohkNix.cardanoLib.environments."${selectedEnv}".relaysNew;
      edgeNodes = [];
    };
  };
}
