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
      (import ./jormungandr.nix)
      ({ pkgs, config, lib, ... }:
        {
          systemd.services.jormungandr = {
            path = with pkgs; [ gnutar gzip ];
            preStart = ''
              (( @useRecentState@ == 0 )) && exit 0
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
        }
      )
    ];
  };
}
