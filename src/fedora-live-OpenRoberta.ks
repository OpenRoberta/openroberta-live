# Copyright 2023 Google LLC
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

%include /usr/share/spin-kickstarts/fedora-live-workstation.ks 

# Keyboard layouts
keyboard 'de'

# System language
lang de_DE.UTF-8

# System timezone
timezone Europe/Berlin

# Use network installation
url --url="https://download.fedoraproject.org/pub/fedora/linux/updates/37/Everything/x86_64/"

# Disk partitioning information
# cf. https://bugzilla.redhat.com/show_bug.cgi?id=1695796
part / --size=16384

%packages
# a JRE is required for Open Roberta Connector
java-17-openjdk
# for running the Open Roberta Lab in a container
podman
%end

%post
LIVE_USER="liveuser"

WIFI_INTERFACE="wlp0s12f0"
WIFI_SSID="OpenRoberta"
WIFI_PASSWORD=""

ORC_VERSION="v1.6.3"
ORC_CUSTOM_ADDRESSES="127.0.0.1 192.168.1.2"
ORC_NAME="OpenRobertaConnector"
ORC_PATH="/usr/local/lib/$ORC_NAME"
ORC_DESCRIPTION="Open Roberta Connector"
ORC_BINARIES="${ORC_NAME}Linux-$ORC_VERSION.tar.gz"
ORC_RELEASE_URL="https://github.com/OpenRoberta/openroberta-connector/releases/download/$ORC_VERSION/$ORC_BINARIES"

ORL_NAME="OpenRobertaLab"
ORL_PATH="/usr/local/lib/$ORC_NAME"
ORL_DESCRIPTION="Open Roberta Lab"
ORL_VERSION="5.1.1"
ORL_URL="http://localhost/"
# using $ORL_DESCRIPTION container image
ORL_IMAGE="docker.io/openroberta/standalone:$ORL_VERSION"
# not using a binary release
#ORL_BINARIES="openrobertalab_binaries.zip"
#ORL_RELEASE_URL="https://github.com/OpenRoberta/openroberta-lab/releases/download/ORA-$ORL_VERSION/openrobertalab_binaries.zip"

if [ -n "$WIFI_INTERFACE" -a -n "$WIFI_SSID" -a -n "$WIFI_PASSWORD" ]
then
  NW_CONFIG=/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection
  touch $NW_CONFIG
  chmod 600 $NW_CONFIG
  cat > $NW_CONFIG << EOF
[connection]
id=$WIFI_SSID
uuid=544ff9ee-3f2f-42ba-a08f-8628a9ea4c53
type=wifi
interface-name=$WIFI_INTERFACE
timestamp=1679515013

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PASSWORD

[ipv4]
method=auto

[ipv6]
addr-gen-mode=stable-privacy
method=auto

[proxy]
EOF
  restorecon $NW_CONFIG
fi

if [ -n "$ORC_RELEASE_URL" ]
then
  cd $(dirname $ORC_PATH)
  curl -LO $ORC_RELEASE_URL
  tar xzf $ORC_BINARIES --no-same-owner
  rm -f $ORC_BINARIES
fi

cat > /usr/share/applications/$ORC_NAME.desktop << EOF
[Desktop Entry]
Name=$ORC_DESCRIPTION
Exec=java -jar -Dfile.encoding=utf-8 $ORC_PATH/$ORC_NAME.jar
Path=$ORC_PATH
Icon=$ORC_PATH/OR.png
Terminal=false
Type=Application
Categories=Development;
X-GNOME-Autostart-enabled=true
EOF

if [ -n "$ORL_IMAGE" ]
then
  podman pull $ORL_IMAGE
  cat >> /etc/systemd/system/$ORL_NAME.service << EOF
[Unit]
Description=Podman container-$ORL_NAME.service
Documentation=man:podman-generate-systemd(1)
Wants=network-online.target
After=network-online.target
RequiresMountsFor=%t/containers

[Service]
Environment=PODMAN_SYSTEMD_UNIT=%n
Restart=always
TimeoutStopSec=70
ExecStart=/usr/bin/podman run \
        --cidfile=%t/%n.ctr-id \
        --cgroups=no-conmon \
        --rm \
        --sdnotify=conmon \
        --replace \
        --name=$ORL_NAME \
        --pull=never \
        -p 80:1999 \
        -d $ORL_IMAGE
ExecStop=/usr/bin/podman stop \
        --ignore -t 10 \
        --cidfile=%t/%n.ctr-id
ExecStopPost=/usr/bin/podman rm \
        -f \
        --ignore -t 10 \
        --cidfile=%t/%n.ctr-id
Type=notify
NotifyAccess=all

[Install]
WantedBy=default.target
EOF
  systemctl daemon-reload
  systemctl enable $ORL_NAME.service
elif [ -n "$ORL_RELEASE_URL" ]
then
  cd $(dirname $ORL_PATH)
  curl -LO $ORL_RELEASE_URL
  tar xzf $ORL_BINARIES --no-same-owner
  rm -f $ORL_BINARIES
fi

cat > /usr/share/applications/$ORL_NAME.desktop << EOF
[Desktop Entry]
Name=$ORL_NAME
GenericName=$ORL_DESCRIPTION
Comment=Opening local $ORL_DESCRIPTION in browser
# not using --kiosk mode as we may need to also use $ORC_DESCRIPTION
# and Alt-Tab to switch windows may not be obvious
Exec=firefox $ORL_URL
Icon=$ORC_PATH/OR.png
Terminal=false
Type=Application
Categories=Development;WebBrowser;
X-GNOME-Autostart-enabled=true
EOF

# don't present welcome dialog
echo "X-GNOME-Autostart-enabled=false" >> /etc/xdg/autostart/liveinst-setup.desktop

cat >> /etc/rc.d/init.d/livesys << EOF
# add live user to dialout group for $ORC_DESCRIPTION
usermod -aG dialout $LIVE_USER
# remove live user from wheel for security reasons
usermod -rG wheel $LIVE_USER

# remove any autostarting applications (such as welcome)
rm -f ~$LIVE_USER/.config/autostart/*
# autostart Open Roberta applications for $LIVE_USER
mkdir -p ~$LIVE_USER/.config/autostart
cp /usr/share/applications/{$ORC_NAME,$ORL_NAME}.desktop ~$LIVE_USER/.config/autostart/
chown $LIVE_USER:$LIVE_USER ~$LIVE_USER/.config/autostart/{$ORC_NAME,$ORL_NAME}.desktop

mkdir ~$LIVE_USER/$ORC_NAME
for ORC_CUSTOM_ADDRESS in $ORC_CUSTOM_ADDRESSES
do
  echo "\$ORC_CUSTOM_ADDRESS" >> ~$LIVE_USER/$ORC_NAME/customaddresses.txt
done
chown -R $LIVE_USER:$LIVE_USER ~$LIVE_USER/$ORC_NAME

restorecon -R ~$LIVE_USER/.config/autostart/ ~$LIVE_USER/$ORC_NAME/

# for Calliope mini: set the Downloads folder to the USB mount path
# to ease development in the browser
rmdir ~$LIVE_USER/Downloads
ln -sf /run/media/$LIVE_USER/MINI ~$LIVE_USER/Downloads
EOF
%end
