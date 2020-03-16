{ pkgs, config, lib, ... }: let
  sources = import ../nix/sources.nix;
in {
  imports = [
    # Example niv "template" repo to import for nixos services
    # Add a niv source pin to your repo of interest and update
    # the name references in this file as needed
    #
    (sources.template + "/nixos")
    ./container-common.nix
  ];

  # Example customized template module configuration
  # Rename and modify this file as needed
  #
  environment.variables.TEMPLATE_VAR = "XYZ";
  networking.firewall.allowedTCPPorts = [ 8080 ];

  systemd.services.template = {
    enable = true;
    serviceConfig = {
      MemoryMax = "1G";
    };
  };
}
