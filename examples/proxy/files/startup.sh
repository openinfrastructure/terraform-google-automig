#! /bin/bash
#
# Configure Apache 2 as a forward proxy

apt -qq -y update
apt -qq -y install apache2

cat <<EOF >/etc/apache2/mods-available/proxy.conf
<IfModule mod_proxy.c>
Listen 3128
ProxyRequests On
<Proxy *>
  AddDefaultCharset off
  # This is an open proxy.  Control access with the VPC firewall.
  # Require local
</Proxy>

# Enable the handling of HTTP/1.1 "Via:" headers
ProxyVia On
</IfModule>
EOF

# For the health check
echo OK | tee /var/www/html/healthz

a2enmod proxy
a2enmod proxy_http
a2enmod proxy_balancer
a2enmod lbmethod_byrequests

sudo systemctl enable apache2
sudo systemctl restart apache2
