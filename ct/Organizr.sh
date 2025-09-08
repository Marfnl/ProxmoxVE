#!/usr/bin/env bash
# Organizr - ProxmoxVE Helper-Scripts style LXC installer (Debian 12, Nginx + PHP-FPM)

# Use official helpers (you can point this to your fork while testing)
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

APP="Organizr"
var_tags="${var_tags:-dashboard}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-12}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors
start

# ---- create & prep the container ----
default_container_setup
create_container
start_container
container_network_wait

# ---- provision inside the CT ----
pushd_container
update_os
install_packages \
  nginx git unzip \
  php8.2-fpm php8.2-cli php8.2-common \
  php8.2-curl php8.2-mbstring php8.2-zip php8.2-xml \
  php8.2-sqlite3 php8.2-ldap php8.2-gd php8.2-bcmath php8.2-gmp

mkdir -p /var/www/organizr
if [ ! -d /var/www/organizr/.git ]; then
  git clone https://github.com/causefx/Organizr /var/www/organizr
else
  (cd /var/www/organizr && git pull --ff-only)
fi
chown -R www-data:www-data /var/www/organizr
find /var/www/organizr -type d -print0 | xargs -0 chmod 755
find /var/www/organizr -type f -print0 | xargs -0 chmod 644

PHP_FPM_POOL="/etc/php/8.2/fpm/pool.d/www.conf"
sed -i 's|^;*listen.mode =.*|listen.mode = 0660|' "$PHP_FPM_POOL"
sed -i 's|^user = .*|user = www-data|' "$PHP_FPM_POOL"
sed -i 's|^group = .*|group = www-data|' "$PHP_FPM_POOL"
systemctl enable --now php8.2-fpm

cat >/etc/nginx/sites-available/organizr <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root /var/www/organizr;
    index index.php index.html;

    error_page 400 401 403 404 405 408 500 502 503 504 /?error=$status;

    location / { try_files $uri $uri/ /index.php?$args; }
    location /api/v2 { try_files $uri /api/v2/index.php$is_args$args; }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_read_timeout 300s;
    }

    client_max_body_size 25m;
    sendfile on;
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/organizr /etc/nginx/sites-enabled/organizr
nginx -t && systemctl enable --now nginx

motd_ssh "Organizr installed at http://<container-ip>/ — finish setup in the browser."
popd_container

description "Organizr on Debian ${var_version} (Nginx + PHP-FPM). Web root: /var/www/organizr"
msg_ok "All done! ${APP} LXC is ready."
trap_cleanup
