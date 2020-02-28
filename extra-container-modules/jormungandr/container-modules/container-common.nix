{ pkgs, lib, config, ... }:
with lib; {
  environment.systemPackages = with pkgs; [
    bat fd git lsof ripgrep tcpdump tree vim
  ];

  nix.optimise.automatic = mkDefault false;
  documentation.enable = false;
  documentation.doc.enable = false;
  documentation.info.enable = false;
  documentation.man.enable = false;
  documentation.nixos.enable = false;
}
