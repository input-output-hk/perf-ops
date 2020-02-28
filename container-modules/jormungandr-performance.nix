{ lib, ... }: {
  amazonImage.sizeMB = 1024 * 3;
  services.performance-containers.containerList = map (n: {
    containerName = "j${lib.fixedWidthNumber 3 n}";
    guestIp = "10.254.1.${toString n}";
  }) (lib.range 1 50);
}
