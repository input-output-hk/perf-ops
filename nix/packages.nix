{ lib, sources }:
let
  inherit (builtins) typeOf trace attrNames toString toJSON mapAttrs any getEnv;
  inherit (lib) splitString optional optionals filterAttrs;
  pkgs = import sources.nixpkgs { };
  eval-config = import (sources.nixpkgs + "/nixos");
  makeDiskImage = import (sources.nixpkgs + "/nixos/lib/make-disk-image.nix");
in rec {
  pp = v: trace (toJSON v) v;

  requireEnv = name:
    let value = getEnv name;
    in if value == "" then
      abort "${name} environment variable is not set"
    else
      value;

  toAmazonImage = v: v.config.system.build.amazonImage;
  toAmazonImages = mapAttrs (k: v: toAmazonImage v);
  filterImages = selected: images:
    filterAttrs (imageName: v: filterFn selected imageName) images;
  amiFilter = requireEnv "AMI_FILTER";
  filterFn = selected: imageName:
    if amiFilter == "all" then
      true
    else if amiFilter == "default" then
       let usedImages = (import ../config.nix { inherit lib pkgs; }).variable.usedImages.default;
       in any (filterNames: imageName == filterNames) usedImages
    else
      any (filterNames: imageName == filterNames) (splitString " " selected);

  mkImage = name:
    { host-modules ? [ ], container-modules ? [ ], extra-containers ? [ ] }:
    let
      internalMkImage = vmType:
        eval-config {
          configuration = { ... }: {
            imports = [ ../modules/containers.nix ../modules/ssh.nix ]
              ++ host-modules ++ optionals (vmType == "ami") [
                (sources.nixpkgs
                  + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
                {
                  amazonImage = {
                    name = name;
                    sizeMB = 16384;
                  };
                  systemd.services."apply-ec2-data".path = with pkgs; [
                    # If a bash ec2 user-data script is executing, add
                    # required command packages to the path here
                    coreutils
                    e2fsprogs
                    gnugrep
                    gnused
                    gnutar
                    kmod
                    mdadm
                    utillinux
                  ];
                  systemd.services."apply-ec2-data".preStart = ''
                    userData="/etc/ec2-metadata/user-data"
                    [ -s "$userData" ] || { echo "ec2 user-data not found..."; exit 0; }
                    if head -n 1 "$userData" | grep -q bash; then
                      echo "Running bash script in ec2 user-data..."
                      cp "$userData" /root
                      chmod u+x "/root/user-data"
                      "/root/user-data"
                    else
                      echo "ec2 user-data does not appear to be bash..."
                    fi
                  '';
                }
              ] ++ optional (vmType == "vm") ({
                virtualisation = {
                  graphics = false;
                  memorySize = 8 * 1024;
                  qemu.networkingOptions = [
                    "-net nic,netdev=user.0,model=virtio"
                    "-netdev user,id=user.0,hostfwd=tcp:127.0.0.1:2201-:22"
                  ];
                };
                services.openssh.enable = true;
                services.mingetty.autologinUser = "root";
              }) ++ optional (vmType == "qemuFull") ({
                fileSystems."/".device = "/dev/disk/by-label/nixos";
                boot.initrd.availableKernelModules = [
                  "xhci_pci"
                  "ehci_pci"
                  "ahci"
                  "usbhid"
                  "usb_storage"
                  "sd_mod"
                  "virtio_balloon"
                  "virtio_blk"
                  "virtio_pci"
                  "virtio_ring"
                ];
                boot.kernelParams = [ "console=ttyS0,115200" ];
                boot.loader = {
                  grub = {
                    version = 2;
                    device = "/dev/vda";
                  };
                  timeout = 0;
                };
                services.openssh.enable = true;
                services.mingetty.autologinUser = "root";
                programs.bash.shellInit = "${pkgs.coreutils}/bin/stty cols 220 rows 50";
              });
            services.performance-containers.moduleList = container-modules;
            services.performance-containers.extraContainers = extra-containers;
          };
        };
    in (internalMkImage "ami") // {
      vm = (internalMkImage "vm").vm;
      qemuFull = let
        qemuFullImage = makeDiskImage rec {
          inherit pkgs;
          config = (internalMkImage "qemuFull").config;
          lib = pkgs.lib;
          diskSize = 32000;
          format = "qcow2-compressed";
        };
      in pkgs.writeShellScript "qemu-full" ''
        export PATH=${pkgs.qemu_kvm}/bin:$PATH
        qemu-img create -f qcow2 -b ${qemuFullImage}/nixos.qcow2 disk.qcow2
        qemu-kvm -cpu kvm64 \
          -name nixos -m 8192 -smp 2 \
          -device virtio-rng-pci \
          -drive index=0,id=drive1,file=disk.qcow2,cache=writeback,werror=report,if=virtio \
          -nographic
      '';
    };
}
