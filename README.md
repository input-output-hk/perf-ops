# Performance Operations (perf-ops) Repository

* The perf-ops repo exists to easily setup up software clients which can then be horizontally and vertically scaled for load testing purposes using AWS
* As an example, this repository enables the rapid deployment of 10,000+ customized load clients across a number of AWS ec2 hosting servers distributed around the world
* Initial AWS configuration of API keys, S3 buckets, IAM roles, trust permissions is beyond the scope of this document although some reference files exist in the examples directory

## Overview

* The perf-ops repo uses [nix](https://nixos.org/nix/) for declarative creation of AWS AMI images which are then deployed via [Terraform](https://www.terraform.io/); [Terranix](https://terranix.org/) is used as the linker between nix and Terraform
* A crystal compiled script is used to distribute AMI images to s3 and ec2 regions from a nix built vhd image
* The general tooling flow is:

```
       Terranix             Terraform
Nix  ------------>  JSON  ------------->   Deployed Resources
 |                                                 |
 |                                                 |
 |     ami-sync             ami-sync               |
 \--------------->   s3   ------------>   AMI   ---/

```

* The perf-ops repo is intended to be deployed from a system with [NixOS](https://nixos.org/) installed and [Lorri](https://nixos.org/nixos/options.html#lorri) enabled

# Instructions For Use

## Setting up .envrc

* After git cloning this repo into a new directory, the .envrc file for Lorri should be generated by copying it from the examples directory and then editing it appropriately:

```
$ git clone https://github.com/input-output-hk/perf-ops
$ cd perf-ops
$ cp examples/envrc-example.txt .envrc
$ vim .envrc
```

* In the .envrc file, ensure that the AWS access key and AWS secret access key variables are updated with the proper credentials.  The rest of the parameters in the file can be left at their defaults.  The comments in the .envrc file provide some guidance on other parameter values that can be used if special behavior is needed.

* After the .envrc file has been updated appropriately, it needs to be activated so Lorri will build the perf-ops environment properly:

```
$ direnv allow
$ cd ..
$ cd perf-ops

# The following executables should now be in the path: ami-sync, terranix and terraform
# If not, try `touch shell.nix` or temporarily use `nix-shell`
# and refer to the Lorri repo (https://github.com/target/lorri) for troubleshooting instructions
```

* A deployer specific UUID should now have been automatically created and available both from the shell env var `$PERF_UUID` and from the file `perf_uuid.txt`
* Terraform should be initialized so it creates a deployer state file and initializes required plugins:

```
$ terraform init
```

## Configuring a load client

* At this time, each host deployed using perf-ops can run a maximum of about 250 load clients before hitting a default dbus limit, assuming other constraints such as CPU, RAM and storage are sufficient for that number of load clients.  The dbus limit may be addressed at a later date.
* Load clients can be generated in nixos containers on AWS hosts using either standard container generation which requires evaluation on the deployer during image build time or by generating containers on the hosts during provisioning post-boot time using an [extra-container](https://github.com/erikarvstedt/extra-container) method.
* The issue with the former method container generation method mentioned is that a large number of containers tends to require a large amount of RAM and CPU time to generate the host image on the deployer.
* To address this, the perf-ops repo is configured to automatically build one standard nixos load client container to benefit from revealing any eval or build errors at image build time and to then build the rest of the load client containers per host at host provisioning post-boot time.
* To define a load client, a new directory under the container-modules subdirectory should be created with at least the minimum required files such as a load client [niv](https://github.com/nmattia/niv) pin directory and files, and a load client modules directory including `container-common.nix` and `container-wrapper.nix` modules.  The `container-modules/template` directory can be copied and modified as needed for this purpose.
* The structure of the template directory and/or other load client directories in the container-modules directory can be examined to see how the load client module should be wrapped, but from a high level perspective here is what should be done:
  * Call the load client module into `container-wrapper.nix`
  * Have the load client module import `container-common.nix`
  * Have the load client module utilize [niv](https://github.com/nmattia/niv) for source pins as needed
* If your SSH keys are not already included in the pre-defined keyset of the `modules/{ssh.nix,ssh-keys.nix}` files, you will need to modify those modules to include your SSH keys

## Configuring a load client image

* Once the container-modules directory for new the load client has been set up, this new load client can be used to declare an image in the `default.nix` file as an attribute set under the images attribute.  An example is:

```
  images = {

    # The `cardano-node` attr is referred to within the nix for the image
    # The `cardano-node-v1` is a more complete name that gets incorporated
    # into a hashed image name that is pushed to s3 and distributed to regions
    #
    cardano-node = mkImage "cardano-node-v1" {

      # Any special AWS host module customization can be included in this list
      #
      host-modules = [
      ];

      # By specifying the load client module in this list, one standard
      # container will be built by default to provide any errors encountered
      # in the load client at image built time
      #
      container-modules = [
        ./container-modules/cardano-node/modules/cardano-node.nix
      ];

      # By specifying the load client in this list of attributes,
      # extra-container load clients will be spawned on the host during
      # provisioning post-boot time.  Each attribute set declared here
      # will create a seperate service on the host which will spawn the
      # desired number of extra-container load clients.  Multiple services
      # can be used to declare different types of load or to build extra
      # containers in parallel and bring load online faster after host
      # provisioning.
      #
      extra-containers = [
        # Host service set 1
        #
        {
          # Name of the systemd service to create extra-containers
          name = "cardano-node-set-1";

          # Name of the folder under the container-modules dir
          entryFolder = "cardano-node";

          # The entry file for extra-containers to use
          # This should stay as `container-wrapper.nix`
          # unless you are doing something special
          entryFile = "container-wrapper.nix";

          # Prefix name for containers -- must be =< 4 chars
          containerNamePrefix = "a";

          # Full private host IP for container networking
          hostAddress = "10.254.0.1";

          # The private network (first 3 octets) for container guests
          network = "10.254.1";

          # The container count -- must be =< 250 due to current dbus limit
          containerCount = 250;

          # Starting container number; will be padded to 3 digits
          containerNameStartNum = 1;

          # Container guest starting IP, 4th octet
          ipStartAddr = 1;

          # This passes a var to the systemd service that can
          # be utilized to determine whether to provide existing
          # state to avoid full load client chain syncs.  See the
          # implementation in the cardano-node load client for
          # reference.
          useRecentState = true;
        }
      ];
  }
```

## Testing a load client image locally

* After the new load client image has been declared in `default.nix` as described above, a local image can be optionally built and tested by:

```
$ nix-build -A images.$IMAGE_NAME.qemuFull
```

* Doing this will create a result file which when run will launch a qemu instance with a console interface through the current shell.  If needed, the qemu parameters can be customized from the `nix/packages.nix` file (search `qemu-full`).

## Creating a deployment configuration

* Now that a load client and load client image have been created and declared, a deployment configuration can be made
* Deployment configurations are declared in `deploy-config.nix` where each attribute set in this file is its own deployment
* Multiple deployments can be defined so as to easily customize load
* For instance, one deployment could use an image with pre-synchronized chain clients which simulate steady-state load while another deployment could use clients requiring full chain sync simulating new network growth
* Each deployment can independently specify server type, regions, region-deployment count and security groups
* An example deployment config follows where two deployments would be used in tandem to simulate a pre-existing network of steady-state client load plus new network growth client load:

```
  # ...

  # The deployment attribute set names are not constrained and are for convienence
  #
  preSyncDeploy1 = {

    # This name must match an images attribute name in default.nix
    #
    name = "cardano-node-presync";

    # Here the server type to provision is specified as well as other options
    # see deploy-config.nix comments and config.nix code for details
    #
    customConfig = {
      instance_type = "r5d.2xlarge";
    };

    # Deploy to regions and the associated host server quantity are specified
    #
    regions = {
      "eu-west-1" = 1;
      "eu-central-1" = 1;
      "us-east-1" = 1;
    };

    # Security groups to include in the deployment are specified
    # Corresponding nix security group files with these names must exist in the
    # `resources/sg` directory
    securityGroups = [
      "allow-ssh"
      "allow-egress"
    ];
  };

  # An example of a second deployment using smaller machines, different deployment
  # regions, quantity, and AMI image
  fullSyncDeploy1 = {
    name = "cardano-node-fullsync";
    customConfig = {
      instance_type = "r5d.xlarge";
    };
    regions = {
      "eu-west-2" = 2;
      "us-east-1" = 2;
      "us-east-2" = 2;
    };
    securityGroups = [
      "allow-ssh"
      "allow-egress"
    ];
  };

  # ...
```

## Creating and distributing the AMI image

* Prior to terraform being able to spin up AWS ec2 resources, AMI images of interest must be available in each region where ec2 server resources will be launched
* Once the prior steps have been completed, this is as simple as executing the ami-sync compiled script with the sync option:

```
$ ami-sync --sync
```

* The ami-sync script will [re-]build the images that are declared in the deployment configuration file, `deploy-config.nix`, push them to the s3 `iohk-amis` bucket if they are not already there, and generate any required snapshots and AMI images in each region defined in deploy-config.nix if they do not already exist

* Unwanted AMI images, snapshots and s3 bucket items can be easily cleaned up once perf-ops testing is complete, either at a per-deployment level or a global perf-ops level.  See the ami-sync script help output for more details: `ami-sync --help`

* Note that typically at least a few minutes is required from the time the ami-sync script completes AMI distribution to the time they are actually usable in all regions.

## Generating Terraform JSON with Terranix

* Prior to utilizing terraform, terraform JSON needs to be generated from the nix.  This can be accomplished by running the following command:

```
$ terranix --with-nulls | tee config.tf.json
```

## Deploying the deployments

* Once the terraform JSON has been created and AMI images have been distributed and are available for use in each region of interest (typically < 15 minutes after ami-sync completes), terraform can be used to deploy resources with the command:

```
$ terraform apply
```

* Similarly, deployed resources such as ec2 instances and security groups can be destroyed with:

```
$ terraform destroy
```

* See the [Terraform documentation](https://www.terraform.io/docs/) for further details on terraform usage


## Reference Perf-Ops Repo Layout

* Items marked with * in the comment for a file indicate that file is not part of the committed repo, but rather created during use of perf-ops

```
.
├── .envrc                                 # The .envrc config file (see examples dir for template)*
├── config.nix                             # The nix setup file used by Terranix
├── config.tf.json                         # The Terranix generated JSON after running against config.nix*
├── container-modules                      # Guest-only container modules
│   └── template                           # An example load client directory
│       ├── modules                        # Example modules for the load client
│       │   ├── container-common.nix       # A standard nix file that each load client should import
│       │   ├── container-wrapper.nix      # A standard nix file each extra-container load client should use
│       │   └── template.nix               # The template load client module
│       └── nix                            # A standard niv directory for the load client
│           ├── default.nix                # Default nix file modified as needed for the template load client
│           ├── sources.json               # Niv pins modified as needed for the template load client
│           └── sources.nix                # Standard niv nix file
├── default.nix                            # Declarative config of perf-ops images
├── deploy-config.nix                      # Declarative config of perf-ops deployments
├── disk.qcow2                             # Local image state if built with the qemuFull attr*
├── examples
│   ├── envrc-example.txt                  # A template file for copying to .envrc in the root directory
│   ├── role-policy.json                   # Example role policy for setting up new AWS infra for perf-ops
│   └── trust-policy.json                  # Example trust policy for setting up new AWS infra for perf-ops
├── modules                                # Host-only modules
│   ├── containers.nix                     # A host module enabling large numbers of load clients on a host
│   ├── ssh-keys.nix                       # A host module for host ssh key access
│   └── ssh.nix                            # A host module for host ssh key access
├── nix                                    # A standard niv directory for the perf-ops deployer
│   ├── default.nix
│   ├── packages.nix
│   ├── pkgs
│   │   └── ami-sync                       # Perf-ops ami-sync utility dir (script, nix)
│   │       ├── ami-sync.cr
│   │       └── default.nix
│   ├── sources.json                       # Perf-ops niv pin state file
│   └── sources.nix                        # Perf-ops niv nix file
├── perf-uuid.txt                          # A per deployer UUID file typically generated by .envrc, direnv/Lorri*
├── providers.tf                           # A Terraform to AWS infrastructure mapping definition file
├── README.md                              # This file
├── resources                              # Supplementary nix resource files, such as security groups
│   └── sg                                 # Security group resource directory
│       ├── allow-egress.nix               # Basic egress security group
│       └── allow-ssh.nix                  # Basic ingress ssh security group
├── result                                 # Local nix-build output (ex: qemu run script from qemuFull attr build)*
├── shell.nix                              # Nix shell file
├── state.json                             # Perf-ops generated image state file*
├── terraform.tfstate                      # Terraform generated state file*
└── terraform.tfstate.backup               # Terraform generated state file*
```

## Notes

### Minimal monitoring

* [Netdata](https://github.com/netdata/netdata) is deployed on each AWS server host by default and produces a large quantity of metrics which can be helpful for tuning and troubleshooting.
* Netdata serves a metrics webpage at port 19999 by default and since this port is intentionally not opened by security group for public consumption, a forwarding tunnel can be set up to a monitoring machine with a command such as:

```
$ ssh -i $SSH_KEY -L 19999:127.0.0.1:19999 root@$HOST_IP
```

### Command and control

* [Parallel SSH](https://github.com/lilydjwg/pssh) can be utilized to issue commands to some or all hosts and/or their respective load clients in order to very quickly control load behavior.
* With an SSH agent loaded and appropriate ssh key added to the agent, some example pssh commands which can be customized for your use case as needed are:

```
# Count all running load containers on each host
pssh -v --hosts <(terraform refresh > /dev/null; terraform show -no-color | grep "public_ip " | awk '{ print $3 }' | tr -d '"') \
  --user root --par 60 --timeout 0 --inline -x "-o StrictHostKeyChecking=no -o ConnectTimeout=2 -o LogLevel=QUIET" \
  -- "nixos-container list | head -n -1 | xargs -I{} nixos-container status {} | sort | uniq -c | grep up"

# Start the load service of NNN containers on each host, where NNN is the numeric portion of the ending container name index per host
pssh -v --hosts <(terraform refresh > /dev/null; terraform show -no-color | grep "public_ip " | awk '{ print $3 }' | tr -d '"') \
  --user root --par 60 --timeout 0 --inline -x "-o StrictHostKeyChecking=no -o ConnectTimeout=2 -o LogLevel=QUIET" \
  -- 'for x in {001..NNN}; do nixos-container run a$x -- systemctl start cardano-node; done'
```
