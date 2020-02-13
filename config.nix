{ lib, pkgs, ... }:
let
  inherit (import ./image.nix) ami;
	images = (__fromJSON (__readFile ./state.json)).images;
	amiName = lib.elemAt (lib.splitString "/" (__unsafeDiscardStringContext (import ./image.nix).ami.outPath)) 3;
  passive = {
    ami = images."${amiName}-eu-west-1".ami_id;
    #spot_price = "0.00";                                # Default is on-demand price
    instance_type = "t3a.small";
    security_groups = [ "allow-ssh" "allow-egress" ];
	  root_block_device.volume_size = 4;
    tags = {
      Name = "passive";
    };
  };
in {
  resource.aws_spot_instance_request.passive = passive;
  resource.aws_security_group = {
    sg-egress = import ./resources/sg/sg-egress.nix;
    sg-ssh = import ./resources/sg/sg-ssh.nix;
  };
  provider.aws.region = "eu-west-1";

  # configure admin ssh keys
  users.admins.manveru.publicKey = "${lib.fileContents ./tf_key.pub}";

  # configure provisioning private Key to be used when running provisioning on the machines
  provisioner.privateKeyFile = toString ./tf_key;
}
