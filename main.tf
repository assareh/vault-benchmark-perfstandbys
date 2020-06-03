provider "acme" {
  server_url = "https://acme-staging-v02.api.letsencrypt.org/directory"
}

resource "tls_private_key" "private_key" {
  algorithm = "RSA"
}

resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.private_key.private_key_pem
  email_address   = "assareh@hashicorp.com"
}

resource "acme_certificate" "certificate" {
  account_key_pem           = acme_registration.reg.account_key_pem
  common_name               = trimsuffix(aws_route53_record.andy-hashidemos-io-CNAME.name, ".")
  subject_alternative_names = [aws_elb.vault.dns_name]

  dns_challenge {
    provider = "route53"
  }
}

data "aws_route53_zone" "selected" {
  name = "andy.hashidemos.io."
}

resource "aws_route53_record" "andy-hashidemos-io-CNAME" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "vault.${data.aws_route53_zone.selected.name}"
  type    = "CNAME"
  records = [aws_elb.vault.dns_name]
  ttl     = "60"
}

# resource "aws_iam_server_certificate" "elb_cert" {
#   name_prefix       = "assareh-cert-"
#   certificate_body  = acme_certificate.certificate.certificate_pem
#   certificate_chain = "${acme_certificate.certificate.certificate_pem}+${acme_certificate.certificate.issuer_pem}"
#   private_key       = acme_certificate.certificate.private_key_pem

#   lifecycle {
#     create_before_destroy = true
#   }
# }

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

data "template_file" "install_vault" {
  template = file("${path.module}/scripts/install_vault_server.sh.tpl")

  vars = {
    install_unzip       = var.unzip_command
    vault_download_url  = var.vault_download_url
    consul_download_url = var.consul_download_url
    vault_config        = var.vault_config
    consul_config       = var.consul_client_config
    tag_value           = var.auto_join_tag
  }
}

data "template_file" "install_consul" {
  template = file("${path.module}/scripts/install_consul_server.sh.tpl")

  vars = {
    install_unzip       = var.unzip_command
    consul_download_url = var.consul_download_url
    consul_config       = var.consul_server_config
    tag_value           = var.auto_join_tag
    consul_nodes        = var.consul_nodes
  }
}

resource aws_vpc "benchmarking" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "assareh-benchmarking-vpc"
  }
}

resource aws_subnet "subnet_a" {
  vpc_id            = aws_vpc.benchmarking.id
  availability_zone = "us-west-2a"
  cidr_block        = "10.0.1.0/24"

  tags = {
    name = "assareh-benchmarking-subnet_a"
  }
}

resource aws_subnet "subnet_b" {
  vpc_id            = aws_vpc.benchmarking.id
  availability_zone = "us-west-2b"
  cidr_block        = "10.0.2.0/24"

  tags = {
    name = "assareh-benchmarking-subnet_b"
  }
}

resource aws_subnet "subnet_c" {
  vpc_id            = aws_vpc.benchmarking.id
  availability_zone = "us-west-2c"
  cidr_block        = "10.0.3.0/24"

  tags = {
    name = "assareh-benchmarking-subnet_c"
  }
}

resource aws_subnet "subnet_d" {
  vpc_id            = aws_vpc.benchmarking.id
  availability_zone = "us-west-2d"
  cidr_block        = "10.0.4.0/24"

  tags = {
    name = "assareh-benchmarking-subnet_d"
  }
}

resource aws_internet_gateway "hashicat" {
  vpc_id = aws_vpc.benchmarking.id

  tags = {
    Name = "assareh-internet-gateway"
  }
}

resource aws_route_table "hashicat" {
  vpc_id = aws_vpc.benchmarking.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hashicat.id
  }
}

resource aws_route_table_association "subnet_a" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.hashicat.id
}

resource aws_route_table_association "subnet_b" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.hashicat.id
}

resource aws_route_table_association "subnet_c" {
  subnet_id      = aws_subnet.subnet_c.id
  route_table_id = aws_route_table.hashicat.id
}

resource aws_route_table_association "subnet_d" {
  subnet_id      = aws_subnet.subnet_d.id
  route_table_id = aws_route_table.hashicat.id
}

resource aws_security_group "hashicat" {
  name = "assareh-security-group"

  vpc_id = aws_vpc.benchmarking.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["76.93.151.110/32"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }

  tags = {
    Name = "assareh-security-group"
  }
}

resource "aws_security_group_rule" "benchmark_internal_icmp" {
  security_group_id        = aws_security_group.hashicat.id
  type                     = "ingress"
  from_port                = 8
  to_port                  = 0
  protocol                 = "icmp"
  source_security_group_id = aws_security_group.vault.id
}

resource aws_instance "hashicat" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_vault
  key_name                    = var.key_name
  associate_public_ip_address = true
  subnet_id                   = aws_subnet.subnet_d.id
  vpc_security_group_ids      = [aws_security_group.hashicat.id]

  tags = {
    Name  = "assareh-hashicat-instance",
    owner = var.owner,
    ttl   = var.ttl
  }
}

// We launch Vault into an ASG so that it can properly bring them up for us.
resource "aws_autoscaling_group" "vault" {
  name                 = aws_launch_configuration.vault.name
  launch_configuration = aws_launch_configuration.vault.name

  #   min_size = "${var.vault_nodes}"
  min_size                  = 1
  max_size                  = var.vault_nodes
  desired_capacity          = var.vault_nodes
  health_check_grace_period = 15
  health_check_type         = "EC2"
  vpc_zone_identifier       = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
  load_balancers            = [aws_elb.vault.id]

  tags = [
    {
      key                 = "Name"
      value               = var.vault_name_prefix
      propagate_at_launch = true
    },
    {
      key                 = "ConsulAutoJoin"
      value               = var.auto_join_tag
      propagate_at_launch = true
    },
    {
      key                 = "owner"
      value               = var.owner
      propagate_at_launch = true
    },
    {
      key                 = "ttl"
      value               = var.ttl
      propagate_at_launch = true
    },
  ]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_launch_configuration" "vault" {
  name_prefix                 = var.vault_name_prefix
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_vault
  key_name                    = var.key_name
  security_groups             = [aws_security_group.vault.id]
  user_data                   = data.template_file.install_vault.rendered
  associate_public_ip_address = var.public_ip
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  root_block_device {
    volume_type = "io1"
    volume_size = 50
    iops        = "2500"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "consul" {
  name                      = aws_launch_configuration.consul.name
  launch_configuration      = aws_launch_configuration.consul.name
  min_size                  = var.consul_nodes
  max_size                  = var.consul_nodes
  desired_capacity          = var.consul_nodes
  health_check_grace_period = 15
  health_check_type         = "EC2"
  vpc_zone_identifier       = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
  load_balancers            = [aws_elb.consul.id]

  tags = [
    {
      key                 = "Name"
      value               = var.consul_name_prefix
      propagate_at_launch = true
    },
    {
      key                 = "ConsulAutoJoin"
      value               = var.auto_join_tag
      propagate_at_launch = true
    },
    {
      key                 = "owner"
      value               = var.owner
      propagate_at_launch = true
    },
    {
      key                 = "ttl"
      value               = var.ttl
      propagate_at_launch = true
    },
  ]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_autoscaling_group.vault]
}

resource "aws_launch_configuration" "consul" {
  name_prefix                 = var.consul_name_prefix
  image_id                    = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type_consul
  key_name                    = var.key_name
  security_groups             = [aws_security_group.vault.id]
  user_data                   = data.template_file.install_consul.rendered
  associate_public_ip_address = var.public_ip
  iam_instance_profile        = aws_iam_instance_profile.instance_profile.name
  root_block_device {
    volume_type = "io1"
    volume_size = 100
    iops        = "5000"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_iam_instance_profile" "instance_profile" {
  name_prefix = var.vault_name_prefix
  role        = aws_iam_role.instance_role.name
}

resource "aws_iam_role" "instance_role" {
  name_prefix        = var.vault_name_prefix
  assume_role_policy = data.aws_iam_policy_document.instance_role.json
}

data "aws_iam_policy_document" "instance_role" {
  statement {
    effect = "Allow"
    actions = [
      "sts:AssumeRole",
    ]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "${var.vault_name_prefix}-auto-discover-cluster"
  role   = aws_iam_role.instance_role.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
    ]

    resources = ["*"]
  }
}

// Security group for Vault
resource "aws_security_group" "vault" {
  name        = "${var.vault_name_prefix}-sg"
  description = "Vault servers"
  vpc_id      = aws_vpc.benchmarking.id
}

resource "aws_security_group_rule" "vault_ssh" {
  security_group_id = aws_security_group.vault.id
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["76.93.151.110/32"]
}

resource "aws_security_group_rule" "vault_external_egress_star" {
  security_group_id = aws_security_group.vault.id
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault_internal_icmp" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8
  to_port                  = 0
  protocol                 = "icmp"
  source_security_group_id = aws_security_group.vault.id
}

resource "aws_security_group_rule" "vault_external_egress" {
  security_group_id = aws_security_group.vault.id
  type              = "egress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "vault_internal_egress" {
  security_group_id        = aws_security_group.vault.id
  type                     = "egress"
  from_port                = 8200
  to_port                  = 8600
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

resource "aws_security_group_rule" "vault_elb_access" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8200
  to_port                  = 8200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault_elb.id
}

resource "aws_security_group_rule" "consul_elb_access" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault_elb.id
}

resource "aws_security_group_rule" "vault_cluster" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8201
  to_port                  = 8201
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

// This rule allows Consul RPC.
resource "aws_security_group_rule" "consul_rpc" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8300
  to_port                  = 8300
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

// This rule allows Consul Serf TCP.
resource "aws_security_group_rule" "vault_consul_serf_tcp" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8301
  to_port                  = 8302
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

// This rule allows Consul Serf UDP.
resource "aws_security_group_rule" "vault_consul_serf_udp" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8301
  to_port                  = 8302
  protocol                 = "udp"
  source_security_group_id = aws_security_group.vault.id
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "consul_dns_tcp" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8600
  to_port                  = 8600
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

// This rule allows Consul DNS.
resource "aws_security_group_rule" "consul_dns_udp" {
  security_group_id        = aws_security_group.vault.id
  type                     = "ingress"
  from_port                = 8600
  to_port                  = 8600
  protocol                 = "udp"
  source_security_group_id = aws_security_group.vault.id
}

// Launch the ELB that is serving Vault. This has proper health checks
// to only serve healthy, unsealed Vaults.
resource "aws_elb" "vault" {
  name                        = "${var.vault_name_prefix}-elb"
  connection_draining         = true
  connection_draining_timeout = 400
  internal                    = var.elb_internal
  subnets                     = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
  security_groups             = [aws_security_group.vault_elb.id]

  listener {
    instance_port     = 8200
    instance_protocol = "tcp"
    lb_port           = 8200
    #lb_protocol       = "https"
    lb_protocol       = "tcp"
    #ssl_certificate_id = aws_iam_server_certificate.elb_cert.arn
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    target              = var.vault_elb_health_check
    interval            = 15
  }
}

// Launch the ELB that is serving Consul. This has proper health checks
// to only serve healthy, unsealed Consuls.
resource "aws_elb" "consul" {
  name                        = "${var.consul_name_prefix}-elb"
  connection_draining         = true
  connection_draining_timeout = 400
  internal                    = var.elb_internal
  subnets                     = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id, aws_subnet.subnet_c.id]
  security_groups             = [aws_security_group.vault_elb.id]

  listener {
    instance_port     = 8500
    instance_protocol = "tcp"
    lb_port           = 8500
    lb_protocol       = "tcp"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    target              = var.consul_elb_health_check
    interval            = 15
  }
}

resource "aws_security_group" "vault_elb" {
  name        = "${var.vault_name_prefix}-elb"
  description = "Vault ELB"
  vpc_id      = aws_vpc.benchmarking.id
}

resource "aws_security_group_rule" "vault_elb_http" {
  security_group_id = aws_security_group.vault_elb.id
  type              = "ingress"
  from_port         = 8200
  to_port           = 8200
  protocol          = "tcp"
  cidr_blocks       = ["76.93.151.110/32"]
}

resource "aws_security_group_rule" "consul_elb_http" {
  security_group_id = aws_security_group.vault_elb.id
  type              = "ingress"
  from_port         = 8500
  to_port           = 8500
  protocol          = "tcp"
  cidr_blocks       = ["76.93.151.110/32"]
}

resource "aws_security_group_rule" "vault_elb_egress_to_vault" {
  security_group_id        = aws_security_group.vault_elb.id
  type                     = "egress"
  from_port                = 8200
  to_port                  = 8200
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

resource "aws_security_group_rule" "vault_elb_egress_to_consul" {
  security_group_id        = aws_security_group.vault_elb.id
  type                     = "egress"
  from_port                = 8500
  to_port                  = 8500
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vault.id
}

