{ region, uuid, provider }: {
  name = "allow-ssh-${region}-${uuid}";
  description = "Allow ssh in ${region} for perf-ops uuid ${uuid}";
  provisioner."local-exec".command = "sleep 5";
  inherit provider;
  ingress = [{
    description = "allow-ingress-ssh";
    from_port = 22;
    to_port = 22;
    protocol = "tcp";
    cidr_blocks = [ "0.0.0.0/0" ];

    ipv6_cidr_blocks = null;
    prefix_list_ids = null;
    security_groups = null;
    self = null;
  }];
}
