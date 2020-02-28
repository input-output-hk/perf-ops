#!/usr/bin/env nix-shell
#!nix-shell -I nixpkgs=./nix -p awscli -p qemu -p crystal -i crystal

require "json"
require "option_parser"

module Shell
  def sh!(cmd, *args)
    puts "$ #{cmd} #{args.to_a.join(" ")}"
    output = IO::Memory.new
    Process.run(cmd, args, output: output, error: STDERR).tap do |status|
      raise "#{cmd} #{args} failed" unless status.success?
    end
    output.to_s.strip
  end

  def sh(cmd, *args)
    puts "$ #{cmd} #{args.to_a.join(" ")}"
    output = IO::Memory.new
    status = Process.run(cmd, args, output: output, error: STDERR)
    output.to_s.strip if status.success?
  end
end
extend Shell

class ImageInfo

  include Shell

  # TODO: use http://169.254.169.254/latest/dynamic/instance-identity/document to get HOME_REGION

  BUCKET      = "iohk-amis"
  HOME_REGION = "eu-west-1"
  REGIONS     = %w[eu-west-1 eu-central-1 us-east-1 us-west-1 ap-southeast-1 ap-northeast-1]
  # REGIONS     = %w[
  #   eu-west-1 eu-west-2 eu-west-3 eu-central-1
  #   us-east-1 us-east-2 us-west-1 us-west-2
  #   ca-central-1
  #   ap-southeast-1 ap-southeast-2 ap-northeast-1 ap-northeast-2
  #   ap-south-1
  #   sa-east-1
  # ]

  JSON.mapping(
    label: String,
    system: String,
    logical_bytes: String,
    file: String,
  )

  property nix_path : String? = nil

  # Round to the next GB
  def logical_gigabytes
    ((logical_bytes.to_u64 - 1) / 1024 / 1024 / 1024 + 1).ceil.to_u64
  end

  def amazon_arch
    case system
    when "aarch64-linux"
      "arm64"
    when "x86_64-linux"
      "x86_64"
    else
      raise "unknown system '#{system}'"
    end
  end

  def name
    file.split("/")[3]
  end

  def description
    "NixOS #{label} #{system}"
  end

  def state_key(region)
    "#{name}-#{region}"
  end

  def self.from_nix_path(path : String)
    from_json(File.read(File.join(path, "/nix-support/image-info.json")))
  end

  def self.prepare(ami)
    pp! ami
    if path = sh("nix-build", "--no-out-link", "./.", "-A", "amis.#{ami}")
      ImageInfo.from_nix_path(path)
    else
      raise "Couldn't build image"
    end
  end

  def upload_all!
    home_image_id = upload_image HOME_REGION

    (REGIONS - [HOME_REGION]).each do |region|
      copied_image_id = copy_to_region region, HOME_REGION, home_image_id.not_nil!
    end
  end

  def s3_name
    file.lstrip("/")
  end

  def s3_url
    "s3://#{BUCKET}/#{s3_name}"
  end

  def with_image(region)
    Registry.new("state.json").open do |images|
      yield images[state_key(region)]
    end
  end

  def upload_image(region)
    upload_image_import(region)
    upload_image_snapshot(region)
    upload_image_deregister(region)
    upload_image_register(region)
  end

  def upload_image_snapshot(region)
    with_image region do |image|
      return if image.snapshot_id

      puts "Waiting for import"

      image.snapshot_id = wait_for_import(region, image.task_id.not_nil!)
    end
  end

  def upload_image_deregister(region)
    deregister_by_name(region)
  end

  # TODO: handle already existing image and allow setting name based on image hash
  def upload_image_register(region)
    with_image region do |image|
      ebs = {
        "SnapshotId"          => image.snapshot_id,
        "VolumeSize"          => logical_gigabytes,
        "DeleteOnTermination" => true,
        "VolumeType"          => "gp2",
      }

      block_device_mappings = [
        {"DeviceName" => "/dev/xvda", "Ebs" => ebs},
        {"DeviceName" => "/dev/sdb", "VirtualName" => "ephemeral0"},
        {"DeviceName" => "/dev/sdc", "VirtualName" => "ephemeral1"},
        {"DeviceName" => "/dev/sdd", "VirtualName" => "ephemeral2"},
        {"DeviceName" => "/dev/sde", "VirtualName" => "ephemeral3"},
      ].to_json

      ami_id_output = sh! "aws", "ec2", "register-image",
        "--name", name,
        "--description", description,
        "--region", region,
        "--architecture", amazon_arch,
        "--block-device-mappings", block_device_mappings,
        "--root-device-name", "/dev/xvda",
        "--sriov-net-support", "simple",
        "--ena-support",
        "--virtualization-type", "hvm"

      result = RegisterImageResult.from_json(ami_id_output)
      image.ami_id = result.image_id
      puts "#{region} AMI ID: #{image.ami_id.to_s}"
      image.ami_id
    end
  end

  def deregister_by_name(region)
    output = sh "aws", "ec2", "describe-images",
      "--region", region,
      "--filters", "Name=name,Values=\"#{name}\""

    images = Hash(String, Array(ImageDescription)).from_json(output.to_s)

    images["Images"].each do |image|
      puts "deregister #{image.image_id} in #{region}"
      sh! "aws", "ec2", "deregister-image",
        "--region", region,
        "--image-id", image.image_id
    end
  end

  def wait_for_import(region, task_id)
    puts "waiting for import task #{task_id} to be completed"

    loop do
      output = sh! "aws", "ec2", "describe-import-snapshot-tasks",
        "--region", region,
        "--import-task-ids", task_id

      tasks = ImportSnapshotTasks.from_json(output)
      task = tasks.import_snapshot_tasks.first.snapshot_task_detail

      case task.status
      when "active"
        puts "%3s/100 : %s" % [task.progress, task.status_message]
        sleep 10
      when "completed"
        return task.snapshot_id
      else
        raise "unexpected snapshot import status for #{task_id}: #{task.inspect}"
      end
    end
  end

  def upload_image_import(region)
    with_image region do |image|
      puts "Checking for image on S3"
      return if task_id = image.task_id

      check_for_image(region)

      puts "Importing image from S3 path #{s3_url}"

      task_id_output = sh! "aws", "ec2", "import-snapshot",
        "--region", region,
        "--disk-container", {
        "Description" => "nixos-image-#{label}-#{system}",
        "Format"      => "vhd",
        "UserBucket"  => {
          "S3Bucket" => BUCKET,
          "S3Key"    => s3_name,
        },
      }.to_json

      if task_id = task_id_output
        image.task_id = ImportResult.from_json(task_id).import_task_id
      end
    end
  end

  def check_for_image(region)
    return if sh "aws", "s3", "ls", "--region", region, s3_url
    puts "Image missing from aws, uploading"
    sh "aws", "s3", "cp", "--region", region, file, s3_url
  end

  def copy_to_region(region, from_region, from_ami_id)
    pp! :copy_to_region, region, from_region, from_ami_id
    with_image region do |image|
      pp! image
      return if ami_id = image.ami_id
      ami_id_output = sh! "aws", "ec2", "copy-image",
        "--region", region,
        "--source-region", from_region,
        "--source-image-id", from_ami_id,
        "--name", name,
        "--description", description

      image.ami_id = RegisterImageResult.from_json(ami_id_output).image_id
      puts "#{region} AMI ID: #{image.ami_id.to_s}"
    end
  end

  class RegisterImageResult
    JSON.mapping(
      image_id: {type: String, key: "ImageId"}
    )
  end

  class ImportResult
    JSON.mapping(
      import_task_id: {type: String, key: "ImportTaskId"}
    )
  end

  class ImportSnapshotTasks
    class SnapshotTaskDetail
      JSON.mapping(
        status: {type: String, key: "Status"},
        progress: {type: String?, key: "Progress"},
        status_message: {type: String?, key: "StatusMessage"},
        snapshot_id: {type: String?, key: "SnapshotId"}
      )
    end

    class SnapshotTask
      JSON.mapping(
        snapshot_task_detail: {
          type: SnapshotTaskDetail,
          key:  "SnapshotTaskDetail",
        }
      )
    end

    JSON.mapping(
      import_snapshot_tasks: {
        type: Array(SnapshotTask),
        key:  "ImportSnapshotTasks",
      }
    )
  end
end

class Registry
  class Images
    JSON.mapping(images: Hash(String, State))

    def []?(key)
      @images[key]?
    end

    def [](key)
      @images[key] ||= State.new(nil, nil, nil)
    end

    def []=(key, value)
      @images[key] = value
    end
  end

  class State
    JSON.mapping(
      task_id: String?,
      snapshot_id: String?,
      ami_id: String?
    )

    def initialize(@task_id, @snapshot_id, @ami_id)
    end
  end

  getter path : String

  def initialize(@path)
    File.write(@path, %({"images":{}})) unless File.file?(@path)
  end

  def open
    images = Images.from_json(File.read(@path))
    yield images
  ensure
    File.write(@path, images.to_pretty_json)
  end
end

class ImageDescription
  JSON.mapping(
    virtualization_type: {type: String, key: "VirtualizationType"},
    description: {type: String, key: "Description"},
    hypervisor: {type: String, key: "Hypervisor"},
    ena_support: {type: Bool, key: "EnaSupport"},
    sriov_net_support: {type: String, key: "SriovNetSupport"},
    image_id: {type: String, key: "ImageId"},
    state: {type: String, key: "State"},
    architecture: {type: String, key: "Architecture"},
    image_location: {type: String, key: "ImageLocation"},
    root_device_type: {type: String, key: "RootDeviceType"},
    owner_id: {type: String, key: "OwnerId"},
    root_device_name: {type: String, key: "RootDeviceName"},
    creation_date: {type: String, key: "CreationDate"},
    public: {type: Bool, key: "Public"},
    image_type: {type: String, key: "ImageType"},
    name: {type: String, key: "Name"},
  )

  def self.deregister_all
    ImageInfo::REGIONS.each do |region|
      output = IO::Memory.new
      Process.run("aws",
        ["ec2", "describe-images",
         "--region", region,
         "--filters", "Name=description,Values=\"NixOS 19.09pre-git x86_64-linux\"",
        ], output: output, error: STDERR
      )

      images = Hash(String, Array(ImageDescription)).from_json(output.to_s)

      images["Images"].each do |image|
        puts "deregister #{image.image_id} in #{region}"
        Process.run("aws",
          ["ec2", "deregister-image",
           "--image-id", image.image_id,
           "--region", region,
          ], error: STDERR, output: STDOUT)
      end
    end
  end
end

config = Hash(String, String).new

OptionParser.parse ARGV do |o|
  o.on("--name NAME",
    "name(s) of the nix ami attr(s) in default.nix as a string, space delimited for multiple; " \
    "defaults to .envrc $AMI_FILTER behavior if not declared") \
    {|v| config["name"] = v }
end

if config.empty?
  puts "Using $AMI_FILTER env default for AMI attrs"
  nixJson = sh("nix-instantiate", "--json", "--strict", "--eval", "-E", "__attrNames (import ./.).amis")
  amis = Array(String).from_json(nixJson.to_s)
else
  puts "Using name arg from CLI for AMI attrs"
  amis = config["name"].split
end

puts "To process: #{pp amis}"
puts
amis.each do |ami|
  image = ImageInfo.prepare(ami)

  puts <<-INFO

  Image Details:
    Name: #{image.name}
    Description: #{image.description}
    Size: #{image.logical_gigabytes}GB
    System: #{image.system}
    Amazon Arch: #{image.amazon_arch}
  INFO

  image.upload_all!
  puts
end
