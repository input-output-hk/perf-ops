let
  sources = import ../nix/sources.nix;
  pkgs = import sources.nixpkgs {};
  lib = pkgs.lib;
in with lib; {
  containers.@name@ = {
    privateNetwork = true;
    autoStart = true;
    hostAddress = "@hostAddress@";
    localAddress = "@network@.@ipaddr@";

    config =  mkMerge [
      (import ./cardano-node.nix)
      ({ pkgs, config, lib, ... }:
        {
          systemd.services.cardano-node = {
            serviceConfig.MemoryMax = "3.5G";
            path = with pkgs; [ gnutar gzip ];
            preStart = ''
              (( @useRecentState@ == 0 )) && exit 0
              [ -f ${config.services.cardano-node.stateDir}/.setup-complete ] && exit 0
              if find @out@ -maxdepth 1 -name "recent-state.tgz" > /dev/null; then
                echo "Found recent state, restoring..."
                tar -zxvf "$(find @out@ -maxdepth 1 -name "recent-state.tgz" -printf "%p")" \
                  -C ${config.services.cardano-node.stateDir}
                echo "Restored."
                touch ${config.services.cardano-node.stateDir}/.setup-complete
              fi
            '';
          };
        }
      )
    ];
  };
}
