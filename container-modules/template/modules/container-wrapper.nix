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

      # Import the template module
      # Modify and rename the template nix file as needed
      #
      (import ./template.nix)
      ({ pkgs, config, lib, ... }:
        {
          # Define a systemd service to utilize fresh state
          # Modify or delete as needed
          #
          systemd.services.template = {
            path = with pkgs; [ gnutar gzip ];
            preStart = ''
              (( @useRecentState@ == 0 )) && exit 0
              [ -f /var/lib/${config.services.template.stateDir}/.setup-complete ] && exit 0
              if find @out@ -maxdepth 1 -name "recent-state.tgz" > /dev/null; then
                echo "Found recent state, restoring..."
                tar -zxvf "$(find @out@ -maxdepth 1 -name "recent-state.tgz" -printf "%p")" \
                  -C /var/lib/${config.services.template.stateDir}
                echo "Restored."
                touch /var/lib/${config.services.template.stateDir}/.setup-complete
              fi
            '';
          };
        }
      )
    ];
  };
}
