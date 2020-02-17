use nix
watch_file nix/pkgs/ami-sync/ami-sync.cr

export AWS_ACCESS_KEY_ID="$SECRET"
export AWS_SECRET_ACCESS_KEY="$SECRET"

# Include a space separated string of default.nix attribute ami names here
# Any attr names not included here will not be built by `ami-sync`
# To build all names, set $AMI_FILTER to "all"
export AMI_FILTER="";

export NIX_PATH="nixpkgs=$(nix eval '(import ./nix {}).path')"
