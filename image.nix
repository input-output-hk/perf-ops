let
  sources = import ../nix/sources.nix;
  eval-config = import (sources.nixpkgs + "/nixos/lib/eval-config.nix");
  nixpkgs = sources.nixpkgs;
  pkgs = import ../nix { };
  inherit (pkgs) lib;
in {
  ami = (eval-config {
    system = "x86_64-linux";
    modules = [
      (nixpkgs + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
      {
        imports = [
          ./modules/containers.nix
          ./modules/ssh.nix
        ];
        amazonImage.name = "jormungandr-v1";

        services.performance-containers = {
          moduleList = [
            ./container-modules/jormungandr-container.nix
          ];
        };
      }
    ];
  }).config.system.build.amazonImage;
}
