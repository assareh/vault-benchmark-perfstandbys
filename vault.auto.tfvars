#For Ubuntu, set unzip_command to "sudo apt-get install -y curl unzip"
#For RHEL, set unzip_command to "sudo yum -y install unzip"
unzip_command = "sudo apt-get install -y curl unzip"

instance_type_vault  = "m5.large"
instance_type_consul = "m5.large"

key_name           = "assareh-ec2"
vault_name_prefix  = "assareh-benchmark-vault"
consul_name_prefix = "assareh-benchmark-consul"

elb_internal = true
public_ip    = true

vault_nodes  = "3"
consul_nodes = "3"

# This downloads Vault Enterprise by default
vault_download_url = "https://releases.hashicorp.com/vault/1.4.2+ent/vault_1.4.2+ent_linux_amd64.zip"

# This downloads Consul Enterprise by default
consul_download_url = "https://releases.hashicorp.com/consul/1.7.3+ent/consul_1.7.3+ent_linux_amd64.zip"

# Used to auto-join Consul servers into cluster
auto_join_tag = "assareh-benchmark-cluster"

# These are only needed for HashiCorp SEs
ttl   = "-1"
