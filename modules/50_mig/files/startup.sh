#! /bin/bash
#
# Copyright 2021 Open Infrastructure Services, LLC
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

set -u

# Return a string payload for logging
payload() {
  local payload
  # One time fetch of instance_id, /etc/google_instance_id may not exist yet.
  if [[ -z "${INSTANCE_ID:-}" ]]; then
    local tmpfile
    tmpfile="$(mktemp)"
    curl -s -S -f -o "$tmpfile" -H Metadata-Flavor:Google metadata/computeMetadata/v1/instance/id
    INSTANCE_ID="$(<"$tmpfile")"
  fi

  payload='{"vm": "'"${HOSTNAME%%.*}"'", "message": "'"$*"'"'
  payload="${payload}, \"instance_id\": \"${INSTANCE_ID}\"}"
  echo "${payload}"
}

error() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::error "$@"
  else
    echo "$@" >&2
  fi
}

info() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::info "$@"
  else
    echo "$@"
  fi
}

debug() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    stdlib::debug "$@"
  else
    echo "$@"
  fi
}

cmd() {
  if [[ -n "${STARTUP_SCRIPT_STDLIB_INITIALIZED:-}" ]]; then
    DEBUG=1 stdlib::cmd "$@"
  else
    "$@"
  fi
}

# Write a sysctl value in a manner compatible with the google-compute-engine
# package which sets values in /etc/sysctl.d/60-gce-network-security.conf
# /etc/sysctl.d/98-gce-startup.conf is used to take precedence.
setup_sysctl() {
  local sysctl_file sysctl_conf
  debug '# BEGIN # setup_sysctl() ...'
  sysctl_file="$(mktemp)"
  sysctl_conf="$(mktemp)"
  # shellcheck disable=SC2129
  echo 'net.ipv4.ip_forward=0' >> "$sysctl_file"
  install -o 0 -g 0 -m 0644 "$sysctl_file" '/etc/sysctl.d/98-gce-startup.conf'
  cmd systemctl restart systemd-sysctl.service
  debug '# END # setup_sysctl() ...'
}

# Configure two status check endpoints.  Port 9000 is used by the MIG for
# auto-ealing.  Port 9001 is used by the Load Balancer forwarding rule backend
# service to start or stop traffic forwarding to this instance.
#
# Take an instance out of rotation by stopping hc-traffic.
# Start the auto-healing process by stopping hc-health
setup_status_api() {
  # Install status API
  local status_file status_unit1 status_unit2
  status_file="$(mktemp)"
  echo '{status: "OK", host: "'"${HOSTNAME}"'"}' > "${status_file}"
  install -v -o 0 -g 0 -m 0755 -d /var/lib/status
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/lib/status/status.json
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/lib/status/healthz
  install -v -o 0 -g 0 -m 0644 "${status_file}" /var/lib/status/healthz.json

  status_unit1="$(mktemp)"
  cat <<EOF >"${status_unit1}"
[Unit]
Description=hc-health auto-healing endpoint (Instance is auto-healed if this unit is stopped)
After=network.target

[Service]
Type=simple
User=nobody
Restart=always
WorkingDirectory=/var/lib/status
ExecStart=@/usr/bin/python3 "/usr/bin/python3" "-m" "http.server" "9000"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "${status_unit1}" /etc/systemd/system/hc-health.service

  status_unit2="$(mktemp)"
  cat <<EOF >"${status_unit2}"
[Unit]
Description=hc-traffic load-balancing endpoint (Instance is taken out of service if this unit is stopped)
After=network.target

[Service]
Type=simple
User=nobody
Restart=always
WorkingDirectory=/var/lib/status
ExecStart=@/usr/bin/python3 "/usr/bin/python3" "-m" "http.server" "9001"
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
  install -m 0644 -o 0 -g 0 "${status_unit2}" /etc/systemd/system/hc-traffic.service

  systemctl daemon-reload
  systemctl restart hc-health.service
  systemctl restart hc-traffic.service
  systemctl enable hc-health.service
  systemctl enable hc-traffic.service
}

main() {
  local jobs

  info "BEGIN: Startup for ${HOSTNAME}"

  if ! setup_sysctl; then
    error "Failed to setup sysctl, aborting."
    exit 1
  fi

  if ! setup_status_api; then
    error "Failed to configure status API endpoints, aborting."
    exit 2
  fi

  info "CHECKPOINT: Online and ready ${HOSTNAME}"

  # Nice to have packages
  # yum -y install tcpdump mtr tmux

  info "END: Startup for ${HOSTNAME}"
  return 0
}

# To make this easier to execute interactively during development, load stdlib
# from the metadata server.  When the instance boots normally stdlib will load
# this script via startup-script-custom.  As a result, only use this function
# outside of the normal startup-script behavior, e.g. when developing and
# testing interactively.
load_stdlib() {
  local tmpfile
  tmpfile="$(mktemp)"
  if ! curl --silent --fail -H 'Metadata-Flavor: Google' -o "${tmpfile}" \
    http://metadata/computeMetadata/v1/instance/attributes/startup-script; then
    error "Could not load stdlib from metadata instance/attributes/startup-script"
    return 1
  fi

  # shellcheck disable=1090
  source "${tmpfile}"
}

# If the script is being executed directly, e.g. when running interactively,
# initialize stdlib.  Note, when running via the google_metadata_script_runner,
# this condition will be false because the stdlib sources this script via
# startup-script-custom.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  TMPDIR="/tmp/startup"
  [[ -d "${TMPDIR}" ]] || mkdir -p "${TMPDIR}"
  load_stdlib
  stdlib::init
  stdlib::load_config_values
fi

main "$@"

# Execute an user-defined startup script if present, otherwise do nothing.
curl -H "Metadata-Flavor: Google" --silent --fail http://metadata.google.internal/computeMetadata/v1/instance/attributes/startup-script-user | bash

# vim:sw=2
