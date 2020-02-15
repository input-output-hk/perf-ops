let
  packages = (import ./nix { }).packages;
  inherit (packages) mkImage toAmazonImages filterImages;
in rec {
  images = {
    jormungandr = mkImage "jormungandr-v1" {
      container-modules = [ ./container-modules/jormungandr-container.nix ];
    };
  };

  amis = toAmazonImages (filterImages ["jormungandr"] images);
}
