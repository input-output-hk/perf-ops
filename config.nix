{ lib, pkgs, ... }:
let
  inherit (builtins) fromJSON readFile mapAttrs unsafeDiscardStringContext replaceStrings
                     concatLists attrNames attrValues foldl' genList listToAttrs;
  packages = (import ./nix { }).packages;
  pp = packages.pp;
  images = (fromJSON (readFile ./state.json)).images;
  amis = (import ./.).amis;
  amiNames = mapAttrs (name: ami:
    lib.elemAt (lib.splitString "/" (unsafeDiscardStringContext ami.outPath)) 3) amis;

  regionToProvider = region: "aws.${replaceStrings ["-"] [""] region}";

  mkInstance = region: count: name: amiName: let
    spotName = "${name}-${toString count}-${region}";
  in {
    name = spotName;
    value = {
      ami = images."${amiName}-${region}".ami_id;
      provider = regionToProvider region;

      # spot_price = "0.00"; # Default is on-demand price
      instance_type = "r5.8xlarge";

      # Use 1 TiB for short term load tests; this will cost 1000*0.1*12/365 = ~$3.29/day/node
      # and will supply 3000 IOPS sustained; otherwise EBS burst cache risks expiring.
      # For high disk IO tests, io1 could be used for higher sustained IOPS or NVMe/SSD vols
      root_block_device.volume_size = 1000;

      security_groups = map (sg: sg + "-${region}") securityGroups;
      tags = { Name = name; };
      wait_for_fulfillment = true;
      provisioner."local-exec" = {
        command = ''
          aws --region ${region} ec2 describe-spot-instance-requests \
            --spot-instance-request-ids ''${aws_spot_instance_request.${spotName}.id} \
            --query 'SpotInstanceRequests[0].Tags' > tmp-$$-tags.json;
          aws --region ${region} ec2 create-tags \
            --resources ''${aws_spot_instance_request.${spotName}.spot_instance_id} \
            --tags file://tmp-$$-tags.json;
          rm -f tmp-$$-tags.json;
        '';
      };
    };
  };

  regions = {
    "eu-west-1" = 1;
    #"eu-west-1" = 8;
    #"eu-central-1" = 8;
    #"us-east-1" = 8;
    #"us-west-1" = 8;
    #"ap-southeast-1" = 8;
    # "ap-northeast-1" = 1;  # Capacity not available
  };

  securityGroups = [ "allow-ssh" "allow-egress" ];

  mkRegionSecGroups = sg: map (region:
    {
      name = "${sg}-${region}";
      value = (import (./. + "/resources/sg/${sg}.nix"))
        { inherit region; provider = regionToProvider region; };
    }
  ) (attrNames regions);

  applyCount = region: count:
    lib.mapAttrs' (name: amiName: (mkInstance region count name amiName))
    amiNames;
in {
  resource.aws_spot_instance_request = foldl' lib.recursiveUpdate { }
    (concatLists (attrValues (mapAttrs (region: count:
      let counts = genList (i: i + 1) count;
      in map (applyCount region) counts) regions)));

  resource.aws_security_group = listToAttrs (concatLists
    (map (sg: mkRegionSecGroups sg) securityGroups));
}
