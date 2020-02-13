{ pkgs ?  import ./nix {}
, makeWrapper ? pkgs.makeWrapper
, awscli ? pkgs.awscli
, nix ? pkgs.nix
}: pkgs.crystal.buildCrystalPackage {
  name = "upload";
  version = "0.0.1";
  src = pkgs.lib.cleanSource ./.;
  crystalBinaries.upload.src = "./upload.cr";

  buildInputs = [ makeWrapper ];

  postInstall = ''
    wrapProgram $out/bin/upload \
      --set PATH ${pkgs.lib.makeBinPath [ awscli nix ]}
  '';
}
