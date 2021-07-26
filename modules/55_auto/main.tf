# Copyright 2020 Google, LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

data "google_compute_zones" "available" {
  project = var.project_id
  region  = var.region
}

locals {
  zones    = data.google_compute_zones.available.names
  # Unique suffix for regional resources
  r_suffix = substr(sha1(var.region), 0, 6)
}

# Manage the regional Managed Instance Group
module "mig" {
  source = "../50_mig"

  image_project = var.image_project
  image_name    = var.image_name
  image_family  = var.image_family
  machine_type  = var.machine_type
  num_instances = var.num_instances
  preemptible   = var.preemptible

  startup_script = var.startup_script

  project_id  = var.project_id
  name_prefix = var.name_prefix
  region      = var.region
  zones       = local.zones

  nic0_project = var.project_id
  nic0_network = var.nic0_network
  nic0_subnet  = var.nic0_subnet

  autoscale          = var.autoscale
  utilization_target = var.utilization_target
  max_replicas       = var.max_replicas

  hc_self_link          = google_compute_health_check.health.self_link
  service_account_email = var.service_account_email
}

# The "health" health check is used for auto-healing with the MIG.  The
# timeouts are longer to reduce the risk of removing an otherwise healthy
# instance.
resource google_compute_health_check "health" {
  project = var.project_id
  name    = "${var.name_prefix}-hc-${local.r_suffix}"

  check_interval_sec  = 10
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 3

  http_health_check {
    port         = var.health_check_port
    request_path = var.health_check_path
  }
}

# The "traffic" health check is used by the load balancer.  The instance will
# be taken out of service if the health check fails and other instances have
# passing traffic checks.  This check is more agressive so that the a
# preemptible instance is able to take itself out of rotation within the 30
# second window provided for shutdown.
resource google_compute_health_check "traffic" {
  project = var.project_id
  name    = "${var.name_prefix}-tc-${local.r_suffix}"

  check_interval_sec  = 3
  timeout_sec         = 2
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 9001
    request_path = "/status.json"
  }
}

resource "google_compute_region_backend_service" "nic0" {
  provider = google-beta
  project  = var.project_id

  name                  = "${var.name_prefix}-${local.r_suffix}-0"
  network               = var.nic0_network
  region                = var.region
  load_balancing_scheme = "INTERNAL"

  dynamic "backend" {
    for_each = module.mig.instance_groups
    content {
      group = backend.value
    }
  }

  # Note this is the traffic health check, not the auto-healing check
  health_checks = [google_compute_health_check.traffic.id]
}

# Reserve an address so we have a well known address to configure for the ilb
resource "google_compute_address" "ilb" {
  name         = "${var.name_prefix}-${local.r_suffix}-ilb"
  project      = var.project_id
  region       = var.region
  subnetwork   = var.nic0_subnet
  address_type = "INTERNAL"
}

resource google_compute_forwarding_rule "ilb" {
  name    = "${var.name_prefix}-${local.r_suffix}-ilb"
  project = var.project_id
  region  = var.region

  ip_address      = google_compute_address.ilb.address
  backend_service = google_compute_region_backend_service.nic0.id
  network         = var.nic0_network
  subnetwork      = var.nic0_subnet

  load_balancing_scheme = "INTERNAL"
  all_ports             = true
  allow_global_access   = true
}
