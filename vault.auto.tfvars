#For Ubuntu, set unzip_command to "sudo apt-get install -y curl unzip"
#For RHEL, set unzip_command to "sudo yum -y install unzip"
unzip_command = "sudo apt-get install -y curl unzip"

instance_type_vault  = "t2.micro"
instance_type_consul = "t2.micro"

key_name = "assareh-ec2"
vault_name_prefix = "assareh-benchmark-vault"
consul_name_prefix = "assareh-benchmark-consul"
vpc_id = "vpc-0097d6746d25d62fb"
subnets = "subnet-0383033a3075d74f7"

elb_internal = true
public_ip = false

vault_nodes = "3"
consul_nodes = "3"

# This downloads Vault Enterprise by default
vault_download_url = "https://releases.hashicorp.com/vault/1.4.2+ent/vault_1.4.2+ent_linux_arm64.zip"

# This downloads Consul Enterprise by default
consul_download_url = "https://releases.hashicorp.com/consul/1.7.3/consul_1.7.3_linux_amd64.zip"

# Used to auto-join Consul servers into cluster
auto_join_tag = "assareh-benchmark-cluster"

# These are only needed for HashiCorp SEs
owner = "assareh@hashicorp.com"
ttl = "3"
