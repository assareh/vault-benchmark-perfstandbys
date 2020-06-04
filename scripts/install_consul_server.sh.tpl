#!/usr/bin/env bash
set -e

# Install packages
${install_unzip}

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
sed -i "s/CONSUL_NODES/${consul_nodes}/g" /tmp/consul-config
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

# Setup the configuration
cat <<EOF >/tmp/telegraf-config
# Telegraf Configuration
#
# Accepts statsd connections on port 8125.
# Sends output to InfluxDB at http://statsbox:8086.

[global_tags]
  role = "consul-server"
  datacenter = "us-west-2"

[agent]
  interval = "10s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "10s"
  flush_jitter = "0s"
  precision = ""
  debug = false
  quiet = false
  logfile = ""
  hostname = ""
  omit_hostname = false

[[outputs.influxdb]]
  urls = ["http://${statsbox}:8086"] # required
  database = "telegraf" # required
  retention_policy = ""
  write_consistency = "any"
  timeout = "5s"
  username = "telegraf"
  password = "telegraf"

[[inputs.consul]]
  address = "localhost:8500"
  scheme = "http"

[[inputs.cpu]]
  percpu = true
  totalcpu = true
  collect_cpu_time = false

[[inputs.disk]]
  # mount_points = ["/"]
  # ignore_fs = ["tmpfs", "devtmpfs"]

[[inputs.diskio]]
  # devices = ["sda", "sdb"]
  # skip_serial_number = false

[[inputs.kernel]]
  # no configuration

[[inputs.linux_sysctl_fs]]
  # no configuration

[[inputs.mem]]
  # no configuration

[[inputs.net]]
  interfaces = ["ens*"]

[[inputs.netstat]]
  # no configuration

[[inputs.processes]]
  # no configuration

[[inputs.procstat]]
  pattern = "(consul|vault)"

[[inputs.swap]]
  # no configuration

[[inputs.system]]
  # no configuration

[[inputs.statsd]]
  protocol = "udp"
  service_address = ":8125"
  delete_gauges = true
  delete_counters = true
  delete_sets = true
  delete_timings = true
  percentiles = [90]
  metric_separator = "."
  parse_data_dog_tags = true
  allowed_pending_messages = 10000
  percentile_limit = 1000
EOF
sudo mv /tmp/telegraf-config /etc/telegraf/telegraf.conf
sudo systemctl restart telegraf
