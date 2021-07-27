# Copyright 2020 Open Infrastructure Services, LLC
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

data "google_project" "project" {
  project_id = var.project_id
}

# Manage the regional MIG formation
module "proxy" {
  source = "../../modules/55_auto"

  name_prefix   = "proxy"
  num_instances = 1

  project_id   = var.project_id
  nic0_project = var.project_id
  nic0_network = "default"
  nic0_subnet  = "default"
  region       = "us-west1"

  # Configure Apache2 as a forward http proxy on 3128
  startup_script    = file("${path.module}/files/startup.sh")
  health_check_port = 3128
  health_check_path = "/healthz"

  service_account_email = "${data.google_project.project.number}-compute@developer.gserviceaccount.com"
}
