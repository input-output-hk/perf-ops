with { pkgs = import ./nix { }; };
pkgs.mkShell {
  buildInputs = with pkgs; [
    cacert
    crystal
    niv
    openssl
    zip
    nix
    awscli
    terranix
    terraform
    ami-sync
  ];
}
