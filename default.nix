let
  packages = (import ./nix { }).packages;
  inherit (packages) mkImage toAmazonImages filterImages amiFilter;
in rec {
  images = {
    jormungandr = mkImage "jormungandr-v1" {
      host-modules = [
      ];
      container-modules = [
        ./container-modules/jormungandr/modules/jormungandr.nix
      ];
      extra-containers = [
        {
          name = "jormungandr-set-1";
          entryFolder = "jormungandr";
          entryFile = "container-wrapper.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 2;
          #containerCount = 125;
          containerNameStartNum = 1;
          ipStartAddr = 1;
          useRecentState = true;
        }
        {
          name = "jormungandr-set-2";
          entryFolder = "jormungandr";
          entryFile = "container-wrapper.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 2;
          #containerCount = 125;
          containerNameStartNum = 126;
          ipStartAddr = 126;
          useRecentState = false;
        }
      ];
    };
    cardano-node = mkImage "cardano-node-v1" {
      host-modules = [
      ];
      container-modules = [
        ./container-modules/cardano-node/modules/cardano-node.nix
      ];
      extra-containers = [
        {
          name = "cardano-node-set-1";
          entryFolder = "cardano-node";
          entryFile = "container-wrapper.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 2;
          #containerCount = 125;
          containerNameStartNum = 1;
          ipStartAddr = 1;
          useRecentState = true;
        }
        {
          name = "cardano-node-set-2";
          entryFolder = "cardano-node";
          entryFile = "container-wrapper.nix";
          containerNamePrefix = "a";
          hostAddress = "10.254.0.1";
          network = "10.254.1";
          containerCount = 2;
          #containerCount = 125;
          containerNameStartNum = 126;
          ipStartAddr = 126;
          useRecentState = false;
        }
      ];
    };
  };

  amis = toAmazonImages (filterImages amiFilter images);
}
