#!/usr/bin/env bash

# Copyright 2025 Genesis Corporation
#
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

set -eu
set -x
set -o pipefail

[[ "$EUID" == 0 ]] || exec sudo -s "$0" "$@"

LUA="5.3"
JDK="17"

# Update the system
apt update
apt upgrade -y

apt install -y apt-transport-https curl gnupg2

# Install jitsi
curl https://download.jitsi.org/jitsi-key.gpg.key | \
    gpg --dearmor -o /usr/share/keyrings/jitsi-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/" | \
    tee /etc/apt/sources.list.d/jitsi-stable.list > /dev/null
apt update

apt-get -y install openjdk-$JDK-jre-headless lua$LUA libnginx-mod-stream nginx nodejs

# Download, but don't install
apt-get -y --install-recommends install --download-only jitsi-meet prosody

cat >>/etc/systemd/system.conf <<EOF

DefaultLimitNOFILE=524288
DefaultLimitNPROC=65000
DefaultTasksMax=65000
EOF

# Excalidraw
apt install -y npm
adduser excalidraw --system --group --disabled-password --shell /bin/bash \
    --home /home/excalidraw
su -l excalidraw <<EOF
    git clone https://github.com/jitsi/excalidraw-backend.git
    cd excalidraw-backend
    echo -n "PORT=3002" >.env.production
    sed -i '/collectDefaultMetrics/ i \    createServer: false,' src/index.ts

    npm install
    npm run build
EOF

cat >/etc/systemd/system/excalidraw.service <<EOF
[Unit]
Description=Excalidraw backend
After=network-online.target

[Service]
User=excalidraw
Group=excalidraw
WorkingDirectory=/home/excalidraw/excalidraw-backend
ExecStart=npm start
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable excalidraw.service

mkdir -p /etc/jitsi/meet/jaas/
cat >/etc/jitsi/meet/jaas/excalidraw.conf <<EOF
    location = /socket.io/ {
        proxy_pass http://127.0.0.1:3002/socket.io/?\$args;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        tcp_nodelay on;
    }
EOF
