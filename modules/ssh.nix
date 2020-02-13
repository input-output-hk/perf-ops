{ config, ... }: {
  imports = [ ./ssh-keys.nix ];
  users.users."root" = {
    openssh.authorizedKeys.keys = config.services.ssh-keys.devOps;
  };
}
