#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/prometheus/blackbox_exporter

APP="Prometheus Blackbox Exporter"
var_tags="${var_tags:-prometheus;monitoring;exporter}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-4}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"  # ICMP may require privileged; default unprivileged

header_info "$APP"
variables
color
catch_errors

# --- Preflight (like the originals) ---
check_container_storage       # ensure selected storage has room for var_disk
check_container_resources     # sanity-check CPU/RAM inputs

update_script() {
  header_info
  check_container_storage
  check_container_resources

  if ! dpkg -s prometheus-blackbox-exporter &>/dev/null; then
    msg_error "No ${APP} installation found!"
    exit 1
  fi

  msg_info "Updating ${APP}"
  $STD apt-get update
  $STD apt-get install -y --no-install-recommends prometheus-blackbox-exporter
  $STD systemctl restart prometheus-blackbox-exporter
  msg_ok "Updated ${APP}"
  exit 0
}

start
build_container

# --- Install inside the LXC ---
post_install() {
  msg_info "Installing Prometheus Blackbox Exporter"
  $STD apt-get update
  $STD apt-get install -y --no-install-recommends prometheus-blackbox-exporter ca-certificates curl
  msg_ok "Installed Prometheus Blackbox Exporter"

  msg_info "Configuring Blackbox Exporter"
  # Minimal config: only HTTP 2xx (you can add tcp/icmp/dns later)
  cat >/etc/prometheus/blackbox-exporter.yml <<'EOF'
modules:
  http_2xx:
    prober: http
EOF

  # Bind to all interfaces on 9115 and use our config file
  $STD sed -i 's|^ARGS=.*|ARGS="--config.file=/etc/prometheus/blackbox-exporter.yml --web.listen-address=0.0.0.0:9115"|' \
    /etc/default/prometheus-blackbox-exporter

  $STD systemctl daemon-reload
  $STD systemctl enable --now prometheus-blackbox-exporter

  # Quick health check (non-fatal)
  if ! curl -fsS http://127.0.0.1:9115/metrics >/dev/null; then
    msg_warn "Blackbox Exporter not yet responding on :9115 — check 'journalctl -u prometheus-blackbox-exporter'"
  fi
  msg_ok "Configured Blackbox Exporter"
}

description() {
  echo -e "${BL}${APP}${CL}
  - Port:    ${YW}9115${CL}
  - Service: ${YW}prometheus-blackbox-exporter${CL}
  - Config:  ${YW}/etc/prometheus/blackbox-exporter.yml${CL}
  - Note: ICMP probes may fail in unprivileged LXC; recreate privileged if you need 'icmp'.

Add this to Prometheus (replace BLACKBOX_LXC_IP):
${YW}- job_name: 'blackbox-http'
  metrics_path: /probe
  params:
    module: [http_2xx]
  static_configs:
    - targets:
      - https://example.org
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: BLACKBOX_LXC_IP:9115${CL}
"
}

post_install
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} LXC is ready.${CL}"
echo -e "${INFO}${YW} Try:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9115/metrics${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9115/probe?module=http_2xx&target=https://example.org${CL}"
