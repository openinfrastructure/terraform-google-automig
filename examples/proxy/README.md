Forward Proxy Example
===

This example builds upon the basic example by adding a custom startup script
which configures a forward http proxy on each instance.

Cloud Logging
===

The Proxy example has the Google Cloud [Ops Agent][ops-agent] integrated.  Find
the proxy logs using the following query:

```
resource.type="gce_instance"
log_name:"logs/vhostlog"
jsonPayload.method="CONNECT"
```

[ops-agent]: https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent
