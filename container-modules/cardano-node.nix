{ pkgs, lib, config, ... }:
let
  sources = import ../nix/sources.nix;
  iohkNix = import sources.iohk-nix {};
  selectedEnv = "shelley_staging";
in
{
  imports = [
    (sources.cardano-node + "/nix/nixos")
  ];

  networking.firewall = {
    allowedTCPPorts = [ 3001 ];
  };

  services.cardano-node = {
    enable = true;
    extraArgs = [ "+RTS" "-N2" "-A10m" "-qg" "-qb" "-M3G" "-RTS" ];
    environment = selectedEnv;
    nodeConfig = iohkNix.cardanoLib.environments."${selectedEnv}".nodeConfig // {
      hasPrometheus = [ "0.0.0.0" 12798 ];
    };
  };
  systemd.services.cardano-node.serviceConfig.MemoryMax = "3.5G";

  # TODO remove next two line for next release cardano-node 1.7 release:
  #systemd.services.cardano-node.scriptArgs = toString cfg.nodeId;
  #systemd.services.cardano-node.preStart = ''
  #  if [ -d ${cfg.databasePath}-${toString cfg.nodeId} ]; then
  #    mv ${cfg.databasePath}-${toString cfg.nodeId} ${cfg.databasePath}
  #  fi
  #'';

  #services.dnsmasq = {
  #  enable = true;
  #  servers = [ "127.0.0.1" ];
  #};

  #networking.extraHosts = ''
  #    ${concatStringsSep "\n" (map (host: "${host.ip} ${host.name}") cardanoHostList)}
  #'';
}
