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

variable "project_id" {
  description = "The project ID containing the managed resources"
  type        = string
}

variable "name_prefix" {
  description = "The name prefix to uss for managed resources, for example 'proxy'.  Intended for major version upgrades of the module."
  type        = string
  default     = "net"
}

variable "region" {
  description = "The region containing the managed resources"
  type        = string
}

variable "service_account_email" {
  description = "The service account used for workload identity"
  type        = string
}

variable "nic0_network" {
  description = "The VPC network nic0 is attached to."
  type        = string
}

variable "nic0_subnet" {
  description = "The name of the subnet the nic0 interface is attached to.  Do not specify as a fully qualified name."
  type        = string
}

variable "nic0_project" {
  description = "The project id which hosts the shared vpc network."
  type        = string
}

variable "num_instances" {
  description = "Number of instances per zonal managed instance group."
  type        = number
  default     = 1
}

variable "machine_type" {
  description = "The machine type of each.  Check the table for Maximum egress bandwidth - https://cloud.google.com/compute/docs/machine-types"
  type        = string
  default     = "n1-highcpu-2"
}

variable "image_project" {
  description = "The image project used with the MIG instance template"
  type        = string
  default     = "debian-cloud"
}

variable "image_name" {
  description = "The image name used with the MIG instance template.  If the value is the empty string, image_family is used instead."
  type        = string
  default     = ""
}

variable "image_family" {
  description = "Configures templates to use the latest non-deprecated image in the family at the point Terraform apply is run.  Used only if image_name is empty."
  type        = string
  default     = "debian-10"
}

variable "preemptible" {
  description = "Allows instance to be preempted. This defaults to false. See https://cloud.google.com/compute/docs/instances/preemptible"
  type        = bool
  default     = false
}

variable "autoscale" {
  description = "Enable autoscaling default configuration.  For advanced configuration, set to false and manage your own google_compute_autoscaler resource with target set to this module's instance_group.id output value."
  type        = bool
  default     = true
}

variable "utilization_target" {
  description = "The CPU utilization_target for the Autoscaler.  A n1-highcpu-2 instance sending at 10Gbps has CPU utilization of 22-24%."
  type        = number
  default     = 0.2 # 20% when using CPU Utilization
  # default   = 939524096 # 70% of 10Gbps when using `instance/network/sent_bytes_count`
  # default   = 161061273 # 60% of 2Gbps when using `instance/network/sent_bytes_count`
}

variable "max_replicas" {
  description = "The maximum number of instances when the Autoscaler scales out"
  type        = number
  default     = 4
}

variable "labels" {
  description = "Labels to apply to the compute instance resources managed by this module"
  type        = map
  default     = {}
}

variable "startup_script" {
  description = "Startup script executed after initilization intended for workload setup.  Must be a bash script."
  type        = string
  default     = ""
}
