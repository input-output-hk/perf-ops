{ lib, pkgs, ... }:
let
  packages = (import ./nix { }).packages;
  inherit (packages) pp requireEnv;
  inherit (lib) elemAt nameValuePair mapAttrs' mapAttrsToList splitString
                recursiveUpdate;
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

  userDataScripts = {
    # The cmds issued in these scripts need to exist in the path attr of the ec2-apply-data service.
    ephemeralSetup = ''
      #!/run/current-system/sw/bin/bash
      # This script should work on any ec2 instance which has an EBS nvme0n1 root vol and additional
      # non-EBS local nvme[1-9]n1 ephemeral block storage devices, ex: c5, g4, i3, m5, r5, x1, z1.
      set -x
      mapfile -t DEVS < <(find /dev -maxdepth 1 -regextype posix-extended -regex ".*/nvme[1-9]n1")
      [ "$${#DEVS[@]}" -eq "0" ] && { echo "No additional NVME found, exiting."; exit 0; }
      if [ -d /var/lib/containers ]; then
        mv /var/lib/containers /var/lib/containers-backup
      fi
      mkdir -p /var/lib/containers
      if [ "$${#DEVS[@]}" -gt "1" ]; then
        mdadm --create --verbose --auto=yes /dev/md0 --level=0 --raid-devices="$${#DEVS[@]}" "$${DEVS[@]}"
        mkfs.ext4 /dev/md0
        mount /dev/md0 /var/lib/containers
      elif [ "$${#DEVS[@]}" -eq "1" ]; then
        mkfs.ext4 "$${DEVS[@]}"
        mount "$${DEVS[@]}" /var/lib/containers
      fi
      if [ -d /var/lib/containers-backup ]; then
        mv /var/lib/containers-backup/* /var/lib/containers/
      fi
      set +x
    '';
  };

  mkInstance = { instance_type ? "r5.2xlarge"
               , root_block_device ? { volume_size = 1000; volume_type = "gp2"; }
               , spot_price ? null
               , tags ? null
               , wait_for_fulfillment ? true
               , timeouts ? { create = "20s"; }
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
    } // removeAttrs config [
      "instance_type"
      "root_block_device"
      "spot_price"
      "tags"
      "wait_for_fulfillment"
      "timeouts"
    ];
  };

  deployConfig = import ./deploy-config.nix { inherit userDataScripts; };

  # Make all security-group region permutations
  mkSecGroups = { ... }@deployGroup: concatLists
    (map (sg: mkRegionSecGroups sg deployGroup.regions) deployGroup.securityGroups);

  # Create each security group resource with deployment uuid
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
  # according to the deployConfig attrset
  resource.aws_spot_instance_request = listToAttrs (concatLists
    (mapAttrsToList (n: v: mkDeployGroup v) deployConfig));

  # Create all unique required securityGroup-region permutations
  # according to the deployConfig attrset
  resource.aws_security_group = listToAttrs (concatLists
    (mapAttrsToList (n: v: mkSecGroups v) deployConfig));

  # Provide an exposed attr containing all utilized images and regions that other
  # components of this repo may need to be aware of: .envrc, ami-sync
  variable = {
    usedImages = {
      type = "list(string)";
      default = mapAttrsToList (n: v: v.name) deployConfig;
    };
    usedRegions = {
      type = "map";
      default = mapAttrs' (n: v: nameValuePair v.name (attrNames v.regions)) deployConfig;
    };
  };
}
