{ lib, pkgs, ... }:
let
  packages = (import ./nix { }).packages;
  inherit (packages) pp requireEnv;
  inherit (lib) elemAt mapAttrs' mapAttrsToList splitString recursiveUpdate;
  inherit (builtins) fromJSON readFile mapAttrs unsafeDiscardStringContext
                     replaceStrings concatLists attrNames attrValues foldl'
                     genList listToAttrs removeAttrs;

  uuid = requireEnv "PERF_UUID";

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

  userDataEphemeralSetup = ''
    #!/run/current-system/sw/bin/bash
    # The cmds issued in this script need to exist in the path attr of the ec2-apply-data service.
    # This script should work on any ec2 instance which has an EBS nvme0n1 root vol and additional
    # non-EBS local nvme[1-9]n1 ephemeral block storage devices.
    set -x
    mapfile -t DEVS < <(find /dev -maxdepth 1 -regextype posix-extended -regex ".*/nvme[1-9]n1")
    mdadm --create --verbose --auto=yes /dev/md0 --level=0 --raid-devices="$${#DEVS[@]}" "$${DEVS[@]}"
    mkfs.ext4 /dev/md0
    if [ -d /var/lib/containers ]; then
      mv /var/lib/containers /var/lib/containers-backup
    fi
    mkdir -p /var/lib/containers
    mount /dev/md0 /var/lib/containers
    if [ -d /var/lib/containers-backup ]; then
      mv /var/lib/containers-backup/* /var/lib/containers/
    fi
    set +x
  '';

  mkInstance = { instance_type ? "r5.2xlarge"
               , root_block_device ? { volume_size = 1000; volume_type = "gp2"; }
               , spot_price ? null
               , tags ? null
               , wait_for_fulfillment ? true
               , ... }@config:
    name: securityGroups: region: count:
  let
    spotName = "${name}-${toString count}-${region}-${uuid}";
    amiName = amiNames.${name};
  in {
    name = spotName;
    value = {
      inherit instance_type root_block_device
              spot_price wait_for_fulfillment;

      ami = images."${amiName}-${region}".ami_id;
      security_groups = map (sg: sg + "-${region}-${uuid}") securityGroups;
      provider = regionToProvider region;
      provisioner."local-exec" = provSpotCmd region spotName;
      tags = if (tags != null) then tags else { Name = "${name}-${uuid}"; };
    } // removeAttrs config
      [ "instance_type" "root_block_device" "spot_price" "tags" "wait_for_fulfillment" ];
  };

  # Sizing Notes:
  #
  # Due to dbus limits, 256 is currently the largest number of containers per host
  # until the dbus limit is addressed.
  #
  # For cardano-node v1.7.0 on staging-shelley with recent state, at ~100 MB RAM per
  # node initially, 256 MB/node should give sufficient memory for short load runtimes
  # so min 64 GB RAM -- r5d.2xlarge should also be plenty sufficient here (64 GB RAM)
  # instance_type = "r5d.2xlarge";
  #
  # For 256 jormungandr containers @ v0.8.13 on QA with recent state,
  # r5.8xlarge provides sufficient memory for 256 containers
  # instance_type = "r5d.8xlarge";
  #
  # For temporary client load that which does not require persistent state, ec2
  # instances with a small gp2 root volume and nvme secondary volumes offer very high
  # IOPS for cheap.  For instance, RAID0 striping an r5d.4xlarge instance with
  # 2x300 GB NVME ephemeral local storage provides a 600 GB vol that yields
  # ~120 kIOPS read and 40 kIOPS write with fio:
  #
  # nix run nixpkgs.fio -c fio --randrepeat=1 --ioengine=libaio --direct=1
  #    --gtod_reduce=1 --name=test --filename=test --bs=4k --iodepth=64
  #    --size=1G --readwrite=randrw --rwmixread=75
  #
  # For use cases where ephemeral instance storage can't be used, 1 TiB gp2 for
  # short term load tests will cost 1000*0.1*12/365 = ~$3.29/day/node
  # and will supply 3000 IOPS sustained.  For higher persistent storage disk IO
  # tests, io1 could be used for higher sustained IOPS.  A 1 TiB io1 disk provisioned
  # at 10 kIOPS will cost (1000*0.125 + 1E4*0.065)*(12/365) = ~$25.48/day/node.
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
        instance_type = "r5d.8xlarge";
        root_block_device = { volume_size = 100; volume_type = "gp2"; };
        user_data = userDataEphemeralSetup;
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
    #    instance_type = "r5d.2xlarge";
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
      name = "${sg}-${region}-${uuid}";
      value = (import (./. + "/resources/sg/${sg}.nix"))
        { inherit region uuid; provider = regionToProvider region; };
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
