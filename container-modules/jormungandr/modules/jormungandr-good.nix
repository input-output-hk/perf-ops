{
  containers.@name@ = {
    privateNetwork = true;
    autoStart = true;
    hostAddress = "@hostAddress@";
    localAddress = "@network@.@ipaddr@";

    config = { pkgs, config, lib, ... }:
      let
        sources = import ../nix/sources.nix;
        default = import ../nix {};
        trustedPeers = __fromJSON (__readFile ./trusted_peers.json);
        jormungandrPkgs = default.jormungandrLib.environments.qa.packages;
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

        systemd.services.jormungandr = {
          path = with pkgs; [ gnutar gzip ];
          preStart = ''
            [ -f /var/lib/${config.services.jormungandr.stateDir}/.setup-complete ] && exit 0
            if ls -1 @out@/recent-state.tgz > /dev/null; then
              echo "Found recent state, restoring..."
              tar -zxvf "$(ls -1 @out@/recent-state.tgz | tr -d '\n')" \
                -C /var/lib/${config.services.jormungandr.stateDir}
              echo "Restored."
              touch /var/lib/${config.services.jormungandr.stateDir}/.setup-complete
            fi
          '';
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
    };
  };
}
