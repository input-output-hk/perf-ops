{ config, lib, pkgs, name, ... }:
let
  cfg = config.services.performance-containers;
in with lib;
{
  options = {
    services.performance-containers = {
      moduleList = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = " This parameter allows container module customization.";
        example = "[ ./container-modules/jormungandr-container.nix ];";
      };

      containerList = mkOption {
        type = types.listOf types.attrs;
        default = [
          { containerName = "c001"; guestIp = "10.254.1.1"; }
          { containerName = "c002"; guestIp = "10.254.1.2"; }
        ];
        description = ''
          This parameter allows container customization on a per server basis.  If
          left as a default empty list, a predefined and fixed deployment of
          containers will pushed to each host which includes this module.  If this
          option is provided a list of attributes, each representing a
          container, this list of containers will be used instead of the predefined
          list. Note that container names cannot be more than 7 characters.
        '';
        example = ''
          [ { containerName = "c001"; guestIp = "10.254.1.1"; }
            { containerName = "c002"; guestIp = "10.254.1.2"; } ];
        '';
      };
    };
  };

  config = let
    createPerformanceContainer = { containerName                        # The desired container name
                               , hostIp ? "10.254.0.1"                  # The IPv4 host virtual eth nic IP
                               , guestIp ? "10.254.1.1"                 # The IPv4 container guest virtual eth nic IP
                               }: {
      name = containerName;
      value = {
        autoStart = true;
        privateNetwork = true;
        hostAddress = hostIp;
        localAddress = guestIp;
        config = {
          imports = cfg.moduleList;
        };
      };
    };
  in {
    environment.systemPackages = [ pkgs.nixos-container ];
    networking.nat.enable = true;
    networking.nat.internalInterfaces = [ "ve-+" ];
    networking.nat.externalInterface = "eth0";

    containers = builtins.listToAttrs (map createPerformanceContainer cfg.containerList);
  };
}
