{ config, lib, pkgs, name, ... }:
let
  cfg = config.services.performance-containers;
  sources = import ../nix/sources.nix;
  extra-container = pkgs.callPackage sources.extra-container {};
  fixNum = i: lib.fixedWidthString 3 "0" (toString i);
in with lib; {
  options = {
    services.performance-containers = {
      moduleList = mkOption {
        type = types.listOf types.path;
        default = [ ];
        description = " This parameter allows container module customization.";
        example = "[ ./container-modules/jormungandr-container.nix ]";
      };

      containerList = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = ''
          This parameter allows container customization on a per server basis.
          Note that container names cannot be more than 7 characters.
        '';
        example = ''
          [ { containerName = "c001"; guestIp = "10.254.1.1"; }
            { containerName = "c002"; guestIp = "10.254.1.2"; } ]
        '';
      };

      extraContainers = mkOption {
        type = types.listOf types.attrs;
        default = [ ];
        description = ''
        '';
        example = ''
        '';
      };
    };
  };

  config = let
    createPerformanceContainer = { containerName # The desired container name
      , hostIp ? "10.254.0.1" # The IPv4 host virtual eth nic IP
      , guestIp ? "10.254.1.1" # The IPv4 container guest virtual eth nic IP
      }: {
        name = containerName;
        value = {
          autoStart = true;
          privateNetwork = true;
          hostAddress = hostIp;
          localAddress = guestIp;
          config = {
            imports = cfg.moduleList;

            # Prevent nixpkgs to get evaluated multiple times
            # workaround for https://github.com/NixOS/nixpkgs/issues/65690
            nixpkgs.pkgs = lib.mkForce pkgs;
          };
        };
      };
    extraContainerServices = { name
                             , entryFile
                             , containerNamePrefix
                             , hostAddress
                             , network
                             , containerCount
                             , containerNameStartNum
                             , ipStartAddr
                             , callPackageSetupName
                             }@arg:
    let
      containerPackage = pkgs.callPackage (../extra-container-modules + "/${arg.callPackageSetupName}")
                           { inherit extra-container; };
    in {
      name = arg.name;
      value = {
        services."${arg.name}" = {
          wantedBy = [ "multi-user.target" ];
          path = with pkgs; [ coreutils nix gnugrep gnutar gzip curl rsync ];
          environment = {
            NIX_PATH = "/root/.nix-defexpr/channels:nixpkgs=/run/current-system/nixpkgs";
          };
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            ENTRYFILE="${arg.entryFile}"
            NAME="${arg.containerNamePrefix}"
            HOST_ADDRESS="${arg.hostAddress}"
            NETWORK="${arg.network}"
            IPADDR="${toString arg.ipStartAddr}"
            SRCDIR="${containerPackage}"
            # Sleep delay for qemu startup
            sleep 10
            for i in {${fixNum arg.containerNameStartNum}..${fixNum (arg.containerNameStartNum + arg.containerCount)}}; do
              "${containerPackage}"/create-extra-container.sh \
                "$ENTRYFILE" "''${NAME}''${i}" "$HOST_ADDRESS" "$NETWORK" "$IPADDR" "$SRCDIR"
              IPADDR=$(( IPADDR + 1 ))
            done
          '';
        };
      };
    };
    extraSet = __foldl' (a: v: lib.recursiveUpdate a v) {}
      (__attrValues (__listToAttrs (map (a: extraContainerServices a) cfg.extraContainers)));
  in {
    environment.systemPackages = with pkgs; [
      nixos-container extra-container
      bat fd git lsof ps_mem ripgrep tcpdump tree vim
    ];

    # Speed up container eval
    documentation.enable = false;
    documentation.doc.enable = false;
    documentation.info.enable = false;
    documentation.man.enable = false;
    documentation.nixos.enable = false;

    # Add host and container auto metrics and alarming
    services.netdata = {
      enable = true;
      config = {
        global = {
          "default port" = "19999";
          "bind to" = "*";
          "history" = "86400";
          "error log" = "syslog";
          "debug log" = "syslog";
        };
      };
    };

    boot.kernel.sysctl = {
      # Fix "Failed to allocate directory watch: Too many open files"
      # or "Insufficent watch descriptors available."
      "fs.inotify.max_user_instances" = 8192;
      #"kern.maxprocperuid" = 65536;
      #"kern.maxproc" = 65536;
      # Fix full PIDs, check with `lsof -n -l | wc -l` (default 32768)
      "kernel.pid_max" = 4194303; # 64-bit max
      # Avoid losing packets on a busy interface
      "net.core.netdev_max_backlog" = 100000;
      "net.core.netdev_budget" = 50000;
      "net.core.netdev_budget_usecs" = 5000;
    };

    networking.nat.enable = true;
    networking.nat.internalInterfaces = [ "ve-+" ];
    networking.nat.externalInterface = "eth0";

    nix = rec {
      # If our hydra is down, don't wait forever
      extraOptions = ''
        connect-timeout = 10
        http2 = true
        show-trace = true
      '';

      # Use all cores
      buildCores = 0;

      nixPath = [ "nixpkgs=/run/current-system/nixpkgs" ];

      # Use our hydra builds and cachix cache
      trustedBinaryCaches = [ "https://cache.nixos.org" "https://hydra.iohk.io" "https://iohk.cachix.org" ];
      binaryCaches = trustedBinaryCaches;
      binaryCachePublicKeys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
        "iohk.cachix.org-1:DpRUyj7h7V830dp/i6Nti+NEO2/nhblbov/8MW7Rqoo="
      ];
    };

    system.extraSystemBuilderCmds = ''
      ln -sv ${(import ../nix { }).path} $out/nixpkgs
    '';

    # Create containers
    containers = mkIf (__length cfg.containerList != 0)
      (builtins.listToAttrs (map createPerformanceContainer cfg.containerList));

    # Create systemd services for extra-containers with extraSet
    systemd = mkMerge [
      { enableCgroupAccounting = true; }
      extraSet
    ];
  };
}
