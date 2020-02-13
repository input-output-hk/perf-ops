use nix

export NIXOPS_DEPLOYMENT=$DEPLOYMENT
export AWS_ACCESS_KEY_ID=$SECRET
export AWS_SECRET_ACCESS_KEY=$SECRET
export PACKET_API_KEY=$SECRET
export PACKET_PROJECT_ID=$PROJECT

export NIX_PATH="nixpkgs=$(nix eval '(import ./nix {}).path')"
