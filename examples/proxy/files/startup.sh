#! /bin/bash
#
# Configure Apache 2 as a forward proxy


if ! [[ -e /var/www/html/healthz ]]; then
  apt -qq -y update
  apt -qq -y install apache2 tcpdump lsof

  cat <<'EOF' >/etc/apache2/mods-available/proxy.conf
<IfModule mod_proxy.c>
Listen 3128
<VirtualHost *:3128>
  ServerAdmin webmaster@localhost
  DocumentRoot /var/www/html

  # Prevent health check spamming the logs
  SetEnvIf Request_URI "^/healthz$" nolog

  ErrorLog ${APACHE_LOG_DIR}/proxy_error.log
  CustomLog ${APACHE_LOG_DIR}/proxy_access.log vhost_combined env=!nolog

  ProxyRequests On
  # Block access to the metadata server, otherwise clients could access workload
  # identity (service account) credentials
  ProxyBlock metadata.google.internal metadata.google metadata 169.254.169.254

  <Proxy *>
    AddDefaultCharset off
    # This is an open proxy.  Control access with the VPC firewall.
    # Require local
  </Proxy>

  # Enable the handling of HTTP/1.1 "Via:" headers
  ProxyVia On
</VirtualHost>
</IfModule>
EOF

  a2enmod proxy
  a2enmod proxy_http
  a2enmod proxy_connect
  a2enmod proxy_balancer
  a2enmod lbmethod_byrequests

  # For the health check
  echo OK | tee /var/www/html/healthz

  sudo systemctl enable apache2
  sudo systemctl restart apache2
fi

# Ops Agent to send access and error logs to Cloud Logging
if ! [[ -e /etc/systemd/system/multi-user.target.wants/google-cloud-ops-agent.service ]]; then
  curl -sS -o /tmp/ops-agent.sh https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
  bash /tmp/ops-agent.sh --also-install

  cat <<'EOF' >/etc/google-cloud-ops-agent/config.yaml
logging:
  receivers:
    accesslog:
      type: files
      include_paths:
        - /var/log/apache*/access.log
    vhostlog:
      type: files
      include_paths:
        - /var/log/apache*/*_access.log
    errorlog:
      type: files
      include_paths:
        - /var/log/apache*/*error.log
  processors:
    accesslog:
      type: parse_regex
      field: message
      regex: '^(?<client>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$'
      time_key: time
      time_format: "%d/%b/%Y:%H:%M:%S %z"
    vhostlog:
      type: parse_regex
      field: message
      regex: '^(?<host>[^ ]*) (?<client>[^ ]*) [^ ]* (?<user>[^ ]*) \[(?<time>[^\]]*)\] "(?<method>\S+)(?: +(?<path>[^\"]*?)(?: +\S*)?)?" (?<code>[^ ]*) (?<size>[^ ]*)(?: "(?<referer>[^\"]*)" "(?<agent>[^\"]*)")?$'
      time_key: time
      time_format: "%d/%b/%Y:%H:%M:%S %z"
    errorlog:
      type: parse_regex
      field: message
      regex: '^\[[^ ]* (?<time>[^\]]*)\] \[(?<level>[^\]]*)\](?: \[pid (?<pid>[^\]]*)\])?( \[client (?<client>[^\]]*)\])? (?<message>.*)$'
      time_key: time
      time_format: "%b %d %H:%M:%S.%L %Y"
  service:
    pipelines:
      default_pipeline:
        receivers: []
      accesslog_pipeline:
        receivers: [accesslog]
        processors: [accesslog]
      vhostlog_pipeline:
        receivers: [vhostlog]
        processors: [vhostlog]
      errorlog_pipeline:
        receivers: [errorlog]
        processors: [errorlog]
EOF
  systemctl restart google-cloud-ops-agent
fi

setup_iperf2_server() {
  local svcfile
  apt install -y -qq iperf
  svcfile="$(mktemp)"
  cat <<EOF>"$svcfile"
[Unit]
Description=iperf server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/iperf --server --interval 5
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/iperf2-server.service
  systemctl daemon-reload
  systemctl start iperf2-server
  systemctl enable iperf2-server
}

setup_iperf3_server() {
  local svcfile
  apt install -y -qq iperf3
  svcfile="$(mktemp)"
  cat <<EOF>"$svcfile"
[Unit]
Description=iperf3 server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/iperf3 --server --interval 5
Restart=on-abort

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "$svcfile" /etc/systemd/system/iperf3-server.service
  systemctl daemon-reload
  systemctl start iperf3-server
  systemctl enable iperf3-server
}


if ! [[ -e /etc/systemd/system/iperf2-server.service ]]; then
  setup_iperf2_server
fi

if ! [[ -e /etc/systemd/system/iperf3-server.service ]]; then
  setup_iperf3_server
fi
