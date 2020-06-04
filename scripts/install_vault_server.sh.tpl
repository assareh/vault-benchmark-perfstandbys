#!/usr/bin/env bash
set -e

# Install packages
${install_unzip}

# Download Vault into some temporary directory
curl -L "${vault_download_url}" > /tmp/vault.zip

# Unzip it
cd /tmp
sudo unzip vault.zip
sudo mv vault /usr/local/bin
sudo chmod 0755 /usr/local/bin/vault
sudo chown root:root /usr/local/bin/vault
sudo setcap cap_ipc_lock=+ep /usr/local/bin/vault

ADDRESS=$(ifconfig ens5 | grep -E -o "(25[0-4]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-4]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-4]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-4]|2[0-4][0-9]|[01]?[0-9][0-9]?)" | head -n 1)

# Setup the configuration
cat <<EOF >/tmp/vault-config
listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault/"
}

seal "awskms" {
  region     = "us-west-2"
  kms_key_id = "${kms_id}"
}

telemetry {
  dogstatsd_addr   = "localhost:8125"
  disable_hostname = true
}

cluster_addr = "https://$ADDRESS:8201"
api_addr = "http://$ADDRESS:8200"

ui=true
EOF
sudo mkdir /etc/vault.d
sudo mv /tmp/vault-config /etc/vault.d/vault-config.json

# Setup the init script
cat <<EOF >/tmp/systemd
[Unit]
Description=Vault Agent
Requires=consul.service
After=consul.service

[Service]
Restart=on-failure
EnvironmentFile=/etc/vault.d/vault-config.json
PermissionsStartOnly=true
ExecStartPre=/sbin/setcap 'cap_ipc_lock=+ep' /usr/local/bin/vault
ExecStart=/usr/local/bin/vault server -config /etc/vault.d $FLAGS
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
User=root
Group=root
LimitMEMLOCK=infinity
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/systemd /etc/systemd/system/vault.service
sudo chmod 0664 /etc/systemd/system/vault.service

# Download Consul into some temporary directory
curl -L "${consul_download_url}" > /tmp/consul.zip

# Unzip it
cd /tmp
sudo unzip consul.zip
sudo mv consul /usr/local/bin
sudo chmod 0755 /usr/local/bin/consul
sudo chown root:root /usr/local/bin/consul

# Setup the configuration
cat <<EOF >/tmp/consul-config
${consul_config}
EOF
IP_ADDRESS=$(curl http://instance-data/latest/meta-data/local-ipv4)
sed -i "s/IP_ADDRESS/$IP_ADDRESS/g" /tmp/consul-config
sed -i "s/TAG_VALUE/${tag_value}/g" /tmp/consul-config
sudo mkdir /etc/consul.d
sudo mv /tmp/consul-config /etc/consul.d/consul-config.json

# Setup the init script
cat <<EOF >/tmp/systemd
[Unit]
Description=Consul Agent
Requires=network-online.target
After=network-online.target

[Service]
Restart=on-failure
EnvironmentFile=/etc/consul.d/consul-config.json
ExecStart=/usr/local/bin/consul agent -config-dir /etc/consul.d $FLAGS
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGTERM
User=root
Group=root
LimitNOFILE=8192

[Install]
WantedBy=multi-user.target
EOF

sudo mv /tmp/systemd /etc/systemd/system/consul.service
sudo chmod 0664 /etc/systemd/system/consul.service

sudo mkdir -pm 0755 /opt/consul/data

# Start Consul
sudo systemctl enable consul
sudo systemctl start consul

# Start Vault
sudo systemctl enable vault
sudo systemctl start vault

# Telegraf
# add the influxdata signing key
curl -sL https://repos.influxdata.com/influxdb.key | sudo apt-key add -
# configure a package repo
source /etc/lsb-release
echo "deb https://repos.influxdata.com/$${DISTRIB_ID,,} $${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/influxdb.list
# install Telegraf and start the daemon
sudo apt-get update && sudo apt-get install telegraf
sudo systemctl enable telegraf
sudo systemctl start telegraf

sudo wget https://raw.githubusercontent.com/tradel/vault-consul-monitoring/master/vault/telegraf.conf
sudo mv telegraf.conf /etc/telegraf/.
sudo systemctl restart telegraf

# Load bash profile
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> /home/ubuntu/.profile