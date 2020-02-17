{ lib, sources }:
let
  inherit (builtins) typeOf trace attrNames toString toJSON mapAttrs any getEnv;
  inherit (lib) splitString;
  eval-config = import (sources.nixpkgs + "/nixos/lib/eval-config.nix");
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
    lib.filterAttrs (imageName: v: filterFn selected imageName) images;
  amiFilter = requireEnv "AMI_FILTER";
  filterFn = selected: imageName:
    if amiFilter == "all" then true
    else any (filterNames: imageName == filterNames) (splitString " " selected);


  mkImage = name:
    { container-modules ? [ ], host-modules ? [ ] }:
    eval-config {
      system = "x86_64-linux";
      modules = [
        (sources.nixpkgs + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
        {
          imports = [ ../modules/containers.nix ../modules/ssh.nix ]
            ++ host-modules;
          amazonImage.name = name;
          services.performance-containers.moduleList = container-modules;
        }
      ];
    };
}
