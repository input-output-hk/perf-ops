{
  containers.CONTAINER_NAME = {
    privateNetwork = true;
    autoStart = true;
    hostAddress = "HOST_ADDRESS";
    localAddress = "NETWORK.IPADDR";

    config = { pkgs, config, lib, ... }: let
      sources = import ../nix/sources.nix;
      iohkNix = import sources.iohk-nix {};
      selectedEnv = "shelley_staging";
    in
    {
      imports = [
        (sources.cardano-node + "/nix/nixos")
        ./container-common.nix
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

      systemd.services.cardano-node = {
        serviceConfig.MemoryMax = "3.5G";
        path = with pkgs; [ gnutar gzip ];
        preStart = ''
          [ -f ${config.services.cardano-node.stateDir}/.setup-complete ] && exit 0
          if ls -1 /nix/store/*-cardano-node-containers/recent-state.tgz > /dev/null; then
            echo "Found recent state, restoring..."
            tar -zxvf "$(ls -1 /nix/store/*-cardano-node-containers/recent-state.tgz | tr -d '\n')" \
              -C ${config.services.cardano-node.stateDir}
            echo "Restored."
            touch ${config.services.cardano-node.stateDir}/.setup-complete
          fi
        '';
      };
    };
  };
}
