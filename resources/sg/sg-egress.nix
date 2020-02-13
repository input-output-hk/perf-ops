{
  name = "allow-egress";
  description = "Allow default egress";
  egress = [{
    description = "allow-egress";
    from_port = 0;
    to_port = 0;
    protocol = "-1";
    cidr_blocks = [ "0.0.0.0/0" ];

    ipv6_cidr_blocks = "null";
    prefix_list_ids = "null";
    security_groups = "null";
    self = "null"; 
  }];
}
