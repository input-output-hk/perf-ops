{ sources }:
let
  inherit (builtins) typeOf trace attrNames toString toJSON;
  eval-config = import (sources.nixpkgs + "/nixos/lib/eval-config.nix");
in {
  pp = v: trace (toJSON v) v;

  requireEnv = name:
    let value = __getEnv name;
    in if value == "" then
      abort "${name} environment variable is not set"
    else
      value;

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
