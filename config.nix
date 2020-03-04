{ lib, pkgs, ... }:
let
  inherit (builtins) fromJSON readFile mapAttrs unsafeDiscardStringContext replaceStrings
                     concatLists attrNames attrValues foldl' genList listToAttrs;
  inherit (lib) elemAt mapAttrs' mapAttrsToList splitString recursiveUpdate;

  packages = (import ./nix { }).packages;
  pp = packages.pp;
  images = (fromJSON (readFile ./state.json)).images;
  amis = (import ./.).amis;
  amiNames = mapAttrs (name: ami:
    elemAt (splitString "/" (unsafeDiscardStringContext ami.outPath)) 3) amis;

  regionToProvider = region: "aws.${replaceStrings ["-"] [""] region}";

  provSpotCmd = region: spotName: {
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

  mkInstance = { instance_type ? "r5.2xlarge"
                    , root_block_device ? { volume_size = 1000; }
                    , spot_price ? null
                    , tags ? null
                    , wait_for_fulfillment ? true
                    , ... }@config:
    name: securityGroups: region: count:
  let
    spotName = "${name}-${toString count}-${region}";
    amiName = amiNames.${name};
  in {
    name = spotName;
    value = {
      inherit instance_type root_block_device
              spot_price wait_for_fulfillment;

      ami = images."${amiName}-${region}".ami_id;
      security_groups = map (sg: sg + "-${region}") securityGroups;
      provider = regionToProvider region;
      provisioner."local-exec" = provSpotCmd region spotName;
      tags = if (tags != null) then tags else { Name = name; };
    };
  };

  # Sizing Notes:
  #
  # Due to dbus limits, 256 is currently the largest number of containers per host
  # until the dbus limit is addressed.
  #
  # For cardano-node v1.7.0 on staging-shelley with recent state, at ~100 MB RAM per
  # node initially, 256 MB/node should give sufficient memory for short load runtimes
  # so min 64 GB RAM -- r5.2xlarge should also be plenty sufficient here (64 GB RAM)
  # instance_type = "r5.2xlarge";
  #
  # For 256 jormungandr containers @ v0.8.13 on QA with recent state,
  # r5.8xlarge provides sufficient memory for 256 containers
  # instance_type = "r5.8xlarge";
  #
  # Use 1 TiB for short term load tests; this will cost 1000*0.1*12/365 = ~$3.29/day/node
  # and will supply 3000 IOPS sustained; otherwise EBS burst cache risks expiring.
  # For high disk IO tests, io1 could be used for higher sustained IOPS or NVMe/SSD vols
  #
  # Spot price defaults to a maximum of on-demand price for cost per hour
  # spot_price = "X.YZ";
  #
  # Using the deploy mapping below, multiple load clusters, each with their own
  # machine definitions, regions and security groups can be declared.  This could be used
  # to create, for instance, a jormungandr or node population with both syncronized and
  # unsyncronized clients to mimic real world load better.

  deployMapping = {
    exampleDeploy1 = {
      name = "jormungandr";
      customConfig = {
        instance_type = "r5.8xlarge";
      };
      regions = {
        "eu-west-1" = 1;
      };
      securityGroups = [
        "allow-ssh"
        "allow-egress"
      ];
    };

    #exampleDeploy2 = {
    #  name = "cardano-node";
    #  customConfig = {
    #    instance_type = "r5.2xlarge";
    #  };
    #  regions = {
    #    "eu-west-1" = 1;
    #    "eu-central-1" = 1;
    #  };
    #  securityGroups = [
    #    "allow-ssh"
    #    "allow-egress"
    #  ];
    #};
  };

  # Given an attr set with attrs of regions and list of sg names,
  # map each security group over all regions in the region attr set
  mkSecGroups = { ... }@deployGroup: concatLists
    (map (sg: mkRegionSecGroups sg deployGroup.regions) deployGroup.securityGroups);

  # Given a security group and a region attrset,
  # map the regions over the sg
  mkRegionSecGroups = sg: regions: map (region:
    {
      name = "${sg}-${region}";
      value = (import (./. + "/resources/sg/${sg}.nix"))
        { inherit region; provider = regionToProvider region; };
    }
  ) (attrNames regions);

  # Make deployment group instances with respective custom config
  # regions and security groups
  mkDeployGroup = { name, customConfig ? {}, regions, securityGroups, ... }:
    concatLists ((attrValues (mapAttrs (region: count: let
      counts = genList (i: i + 1) count;
      mkDeployGroupCount = mkInstance customConfig name securityGroups region;
    in
      map mkDeployGroupCount counts) regions)));

in {
  # Create all unique required instance permutations
  # according to the deployMapping attrset
  resource.aws_spot_instance_request = listToAttrs (concatLists
    (mapAttrsToList (n: v: mkDeployGroup v) deployMapping));

  # Create all unique required securityGroup-region permutations
  # according to the deployMapping attrset
  resource.aws_security_group = listToAttrs (concatLists
    (mapAttrsToList (n: v: mkSecGroups v) deployMapping));
}
