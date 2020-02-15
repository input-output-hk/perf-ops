with { pkgs = import ./nix { }; };
let
  terraform =
    pkgs.terraform.withPlugins (plugins: with plugins; [ aws null nixos ]);
in pkgs.mkShell {
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
