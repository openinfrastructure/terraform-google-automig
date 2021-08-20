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

## Ops Agent apache2 configuration: This isn't ready because it doesn't result in structured logs.

# Ops Agent configuration
