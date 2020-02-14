{ mkImage ? (import ./nix { }).packages.mkImage }: rec {
  images = {
    jormungandr = mkImage "jormungandr-v1" {
      container-modules = [ ./container-modules/jormungandr-container.nix ];
    };
  };

  amis = __mapAttrs (k: v: v.config.system.build.amazonImage) images;
}
