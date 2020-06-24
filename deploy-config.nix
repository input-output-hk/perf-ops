{ userDataScripts }:
{
  # Sizing Notes:
  #
  # Due to dbus limits, 256 is currently the largest number of containers per host
  # until the dbus limit is addressed.
  #
  # In general, the ec2 host server sizing for the load client containers
  # will need to be tuned for your use case.  The following notes, however,
  # provide some examples and guidance as a starting point.
  #
  # For cardano-node v1.8.0 on staging-shelley with recent state, at ~100 MB RAM per
  # node initially, 256 MB/node should give sufficient memory for short load runtimes
  # so min 64 GB RAM -- r5d.2xlarge should also be plenty sufficient here (64 GB RAM)
  # instance_type = "r5d.2xlarge";
  #
  # For jormungandr containers @ v0.9.0 on QA with recent state,
  # r5.8xlarge provides sufficient memory for 200 containers
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
  # r5d class instances are routinely available from Ohio, Virginia, Oregon, and
  # Ireland, but may have capacity issues in other regions.
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

  exampleDeploy1 = {
    name = "jormungandr";
    customConfig = {
      instance_type = "r5d.8xlarge";
      root_block_device = { volume_size = 100; volume_type = "gp2"; };
      user_data = userDataScripts.ephemeralSetup;
    };
    regions = {
      "eu-west-1" = 1;        # Initial deploy region and test image quantity
      #"eu-west-1" = 15;      # Regions with sufficient r5d capacity
      #"us-west-2" = 15;
      #"us-east-1" = 15;
      #"us-east-2" = 15;
      #"us-west-1" = 0;       # Additional regions which may have r5d capacity
      #"eu-central-1" = 0;
      #"eu-west-2" = 0;
      #"ca-central-1" = 0;
      #"ap-northeast-1" = 0;
      #"ap-southeast-1" = 0;
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
}
