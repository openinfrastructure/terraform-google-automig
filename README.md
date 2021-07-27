Auto Managed Instance Group
===

This terraform module manages a regional instance group with auto healing and
auto scaling enabled.  The intended purpose as a generic, re-usable starting
point for network services.  This module has been used to implement multinic
ECMP IP routing and an HTTP forward proxy.

The common bits have been extracted out.  The idea is you need only pass in a
basic shell script to setup whatever network service you need.  For example,
the forward proxy is a fairly simple shell script passed into the generic
module:

<details><summary>forward proxy</summary>
<p>

```
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
```

</p>
</details>

Health Checks
==

There are two types of health checks configured to handle the two use cases of
auto healing and taking an instance out of service.

 1. Managed Instance Group auto-healing checks.
 2. Load Balancing traffic distribution checks.

The MIG auto-healing health checks will come into nic0.  Stop the `hc-traffic`
service unit file to take the instance out of rotation.

A basic HTTP server is included for health and traffic checking.  Replace the
health check port and path with your workloads health check endpoint for more
robust health checking of the workload.

Helper Scripts
==

Helper scripts are included in the [scripts](scripts/) directory.

`rolling_update`
---

Use this script after applying changes to the instance template used by the
managed instance group.  The helper script performs a [Rolling
Update][rolling-update] which replaces each instance in the vpc-link group with
a new instance.
