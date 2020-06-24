{ pkgs, config, lib, ... }: let
  sources = import ../nix/sources.nix;
  default = import ../nix {};
  trustedPeers = default.jormungandrLib.environments.qa.trustedPeers;
  jormungandrPkgs = default.jormungandrLib.packages.v0_9_0;
in {
  imports = [
    (sources.jormungandr-nix + "/nixos")
    ./container-common.nix
  ];
  disabledModules = [ "services/networking/jormungandr.nix" ];

  system.extraDependencies = with default; [
    stdenv
    busybox
    jormungandrPkgs.jcli
    janalyze
    sendFunds
    checkTxStatus
  ];

  environment.variables.JORMUNGANDR_RESTAPI_URL = "http://127.0.0.1:3001/api";

  networking.firewall.allowedTCPPorts = [ 3000 ];

  systemd.services.jormungandr = {
    serviceConfig = {
      MemoryMax = "1.9G";
    };
  };

  services.jormungandr = {
    enable = true;
    environment = "qa";
    withBackTraces = true;
    package = jormungandrPkgs.jormungandr;
    jcliPackage = jormungandrPkgs.jcli;
    listenAddress = "/ip4/0.0.0.0/tcp/3000";
    rest.listenAddress = "127.0.0.1:3001";
    logger = {
      level = "info";
      output = "journald";
    };
    inherit trustedPeers;
  };
}
