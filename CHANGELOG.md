v1.4.0 - 2021-08-31
===

 * Run iperf2 and iperf3 servers on proxy example to measure throughput to the
   proxies.  This is intended to determine which GCP region is best to use from
   a given on-prem data center when multiple interconnects are available.

v1.3.0 - 2021-08-23
===

 * Integrate Google Cloud [Ops Agent][ops-agent] to log proxy access logs to
   cloud logging with structured logs.

v1.2.0 - 2021-08-10
===

 * Enable HTTP CONNECT proxy for outbound https on port 443

v1.1.0 - 2021-08-10
===

 * Allow consumers to specify the tags input variable.

v1.0.2 - 2021-07-26
===

 * Block access to metadata service

v1.0.1 - 2021-07-26
===

 * Use `allow-health-checks` tag in accordance with docs

v1.0.0 - 2021-07-26
===

 * Initial release with HTTP Forward Proxy example

[ops-agent]: https://cloud.google.com/stackdriver/docs/solutions/agents/ops-agent
