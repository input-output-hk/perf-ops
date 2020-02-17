let
  packages = (import ./nix { }).packages;
  inherit (packages) mkImage toAmazonImages filterImages amiFilter;
in rec {
  images = {
    jormungandr = mkImage "jormungandr-v1" {
      container-modules = [ ./container-modules/jormungandr-container.nix ];
    };
    cardano-node = mkImage "cardano-node-v1" {
      container-modules = [ ./container-modules/jormungandr-container.nix ];
    };
  };

  amis = toAmazonImages (filterImages amiFilter images);
}
