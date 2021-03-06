{ region, uuid, provider }: {
  name = "allow-egress-${region}-${uuid}";
  description = "Allow default egress in ${region} for perf-ops uuid ${uuid}";
  provisioner."local-exec".command = "sleep 5";
  inherit provider;
  egress = [{
    description = "allow-egress";
    from_port = 0;
    to_port = 0;
    protocol = "-1";
    cidr_blocks = [ "0.0.0.0/0" ];

    ipv6_cidr_blocks = null;
    prefix_list_ids = null;
    security_groups = null;
    self = null;
  }];
}
