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


while [ ! -f /etc/genesis_init.txt ]; do sleep 1; done
JITSI_HOST=$(< /etc/genesis_init.txt)
if [[ -z "$JITSI_HOST" ]]; then
    echo "Error: JITSI_HOST is empty, /etc/genesis_init.txt may be empty or missing." >&2
    exit 1
fi
echo "Config found: host is $JITSI_HOST"

if dpkg -s jitsi-meet &>/dev/null; then
    echo 'jitsi-meet is is alredy installed, looks like we already bootstrapped, exit.'
    exit 0
fi

JITSI_MEET_CONFIGS=/etc/jitsi/meet/*.js
export DEBIAN_FRONTEND=noninteractive

debconf-set-selections <<< \
    "jicofo jitsi-videobridge/jvb-hostname string $JITSI_HOST"
debconf-set-selections <<< \
    "jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate"
apt-get -y --install-recommends install jitsi-meet prosody


sed -i "s/___JITSI_FQDN___/$JITSI_HOST/" $JITSI_MEET_CONFIGS

cat >> /etc/jitsi/meet/$JITSI_HOST-config.js <<EOF

// whiteboard
config.whiteboard = {
  enabled: true,
  collabServerBaseUrl: 'https://$JITSI_HOST',
};

config.dynamicBrandingUrl = '/static/branding.json';
EOF

rsync -a /opt/jitsi/static/ /usr/share/jitsi-meet/

# Jitsi itself uses ssl to internal communications (at least jvb->prosody)
ln -sf /etc/jitsi/meet/*.crt /usr/local/share/ca-certificates/
update-ca-certificates -f

# Use it ONLY for testing purposes!
# https://www.enablesecurity.com/blog/slack-webrtc-turn-compromise-and-bug-bounty/#how-to-fix-an-open-turn-relay-to-address-this-vulnerability
# sed -i 's/^denied-peer-ip=/# denied-peer-ip=/' /etc/turnserver.conf

systemctl restart jicofo.service prosody.service jitsi-videobridge2.service coturn.service

