let
  packages = (import ./nix { }).packages;
  inherit (packages) mkImage toAmazonImages filterImages amiFilter;
in rec {
  images = {
    jormungandr = mkImage "jormungandr-v1" {
      host-modules = [
        # ./container-modules/jormungandr-performance.nix
      ];
      container-modules = [
        # ./container-modules/container-common.nix
        # ./container-modules/jormungandr-container.nix
      ];
      extra-containers = [
        {
          name = "jormungandr-set-1";
          entryFile = "./container-modules/jormungandr.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 125;
          containerNameStartNum = 1;
          ipStartAddr = 1;
          callPackageSetupName = "jormungandr.nix";
        }
        {
          name = "jormungandr-set-2";
          entryFile = "./container-modules/jormungandr.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 125;
          containerNameStartNum = 126;
          ipStartAddr = 126;
          callPackageSetupName = "jormungandr.nix";
        }
      ];
    };
    cardano-node = mkImage "cardano-node-v1" {
      container-modules = [ ./container-modules/jormungandr-container.nix ];
    };
  };

  amis = toAmazonImages (filterImages amiFilter images);
}
