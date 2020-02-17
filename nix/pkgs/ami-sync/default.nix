{ pkgs ?  import ./nix {}
, makeWrapper ? pkgs.makeWrapper
, awscli ? pkgs.awscli
, gnutar ? pkgs.gnutar
, gzip ? pkgs.gzip
, qemu ? pkgs.qemu
, nix ? pkgs.nix
}: pkgs.crystal.buildCrystalPackage {
  name = "ami-sync";
  version = "0.0.1";
  src = pkgs.lib.cleanSource ./.;
  crystalBinaries.ami-sync.src = "./ami-sync.cr";

  buildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/ami-sync \
      --set PATH ${pkgs.lib.makeBinPath [ awscli gnutar gzip qemu nix ]}
  '';
}
