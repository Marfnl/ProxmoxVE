#!/usr/bin/env bash
# DEV import (use your fork/branch while testing)
source <(curl -s https://raw.githubusercontent.com/Marfnl/ProxmoxVE/refs/heads/feature/blackbox-exporter/misc/build.func)
#source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)
# Copyright (c) 2021-2025 community-scripts ORG
# Author: Andy Grunwald (andygrunwald)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/prometheus-pve/prometheus-pve-exporter

banner_ascii() {
  clear
  cat <<"EOF"
  ____                               _                   _                         
 |  _ \ _ __ ___   ___ _ __ ___  ___| |_ _ __ _   _  ___| |_ ___  _ __  _   _ ___ 
 | |_) | '__/ _ \ / __| '__/ _ \/ __| __| '__| | | |/ __| __/ _ \| '_ \| | | / __|
 |  __/| | | (_) | (__| | |  __/\__ \ |_| |  | |_| | (__| || (_) | |_) | |_| \__ \
 |_|   |_|  \___/ \___|_|  \___||___/\__|_|   \__,_|\___|\__\___/| .__/ \__,_|___/
                                                                |_|               
  ____  _            _            __  __                    _                      _            
 | __ )| | ___   ___| | _____ _ _|  \/  | ___  _ __  _   _ | | _____  _ __   __ _| |_ ___  ___ 
 |  _ \| |/ _ \ / __| |/ / _ \ '__| |\/| |/ _ \| '_ \| | | || |/ / _ \| '_ \ / _` | __/ _ \/ __|
 | |_) | | (_) | (__|   <  __/ |  | |  | | (_) | | | | |_| ||   < (_) | | | | (_| | ||  __/\__ \
 |____/|_|\___/ \___|_|\_\___|_|  |_|  |_|\___/|_| |_|\__,_||_|\_\___/|_| |_|\__,_|\__\___||___/
EOF
}

APP="Prometheus-PVE-Exporter"
var_tags="${var_tags:-monitoring}"
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512}"
var_disk="${var_disk:-2}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

banner_ascii
header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources
  if [[ ! -f /etc/systemd/system/prometheus-pve-exporter.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit 1
  fi

  msg_info "Stopping ${APP}"
  systemctl stop prometheus-pve-exporter
  msg_ok "Stopped ${APP}"

  export PVE_VENV_PATH="/opt/prometheus-pve-exporter/.venv"
  export PVE_EXPORTER_BIN="${PVE_VENV_PATH}/bin/pve_exporter"

  if [[ ! -d "$PVE_VENV_PATH" || ! -x "$PVE_EXPORTER_BIN" ]]; then
    PYTHON_VERSION="3.12" setup_uv
    msg_info "Migrating to uv/venv"
    rm -rf "$PVE_VENV_PATH"
    mkdir -p /opt/prometheus-pve-exporter
    cd /opt/prometheus-pve-exporter
    $STD uv venv "$PVE_VENV_PATH"
    $STD "$PVE_VENV_PATH/bin/python" -m ensurepip --upgrade
    $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade pip
    $STD "$PVE_VENV_PATH/bin/python" -m pip install prometheus-pve-exporter
    msg_ok "Migrated to uv/venv"
  else
    msg_info "Updating Prometheus Proxmox VE Exporter"
    PYTHON_VERSION="3.12" setup_uv
    $STD "$PVE_VENV_PATH/bin/python" -m pip install --upgrade prometheus-pve-exporter
    msg_ok "Updated Prometheus Proxmox VE Exporter"
  fi
  local service_file="/etc/systemd/system/prometheus-pve-exporter.service"
  if ! grep -q "${PVE_VENV_PATH}/bin/pve_exporter" "$service_file"; then
    msg_info "Updating systemd service"
    cat <<EOF >"$service_file"
[Unit]
Description=Prometheus Proxmox VE Exporter
Documentation=https://github.com/znerol/prometheus-pve-exporter
After=syslog.target network.target

[Service]
User=root
Restart=always
Type=simple
ExecStart=${PVE_VENV_PATH}/bin/pve_exporter \\
    --config.file=/opt/prometheus-pve-exporter/pve.yml \\
    --web.listen-address=0.0.0.0:9221
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF
    $STD systemctl daemon-reload
    msg_ok "Updated systemd service"
  fi

  msg_info "Starting ${APP}"
  systemctl start prometheus-pve-exporter
  msg_ok "Started ${APP}"

  msg_ok "Updated Successfully"
  exit 0
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:9221${CL}"
