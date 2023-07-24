#! /bin/sh

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

#############################################################################

###
# Fedora Linux
###

# release version
RELEASEVER=38

# minor version 
RELEASEVER_MIN="1.6"

# architecture
RELEASE_ARCH="x86_64"

# checksum of the Fedora-Server-netinst ISO for integrity of download
RELEASE_SHA256="192af621553aa32154697029e34cbe30152a9e23d72d55f31918b166979bbcf5"

# the use of a caching proxy is recommended for repeated builds
#PROXY_URL="http://proxy:3128/"

# set to a close mirror when using a proxy server
REPO_URL="https://download.fedoraproject.org/pub/fedora/linux/"

###
# QEMU
###

# the number of vCPUs to use for building the custom Live-Linux
VCPUS=8

###
# Live-Linux
###

# default GRUB timeout when booting
GRUB_TIMEOUT=3

# the (default) keyboard layout to use
OS_KEYBOARD="de"

# the language
OS_LANG="de_DE.UTF-8"

# the time zone
OS_TZ="Europe/Berlin"

###
# OpenRoberta-Connector
###

# release, cf. https://github.com/OpenRoberta/openroberta-connector/releases
ORC_VERSION="v1.6.3"

# preconfigured custom IP addresses
# 127.0.0.1 for localhost (Live-Linux)
# 192.168.1.2 could be the IP of a local server
#             e.g., realized with a Raspberry Pi
#             cf. https://www.open-roberta.org/lokale-installation/
ORC_CUSTOM_ADDRESSES="127.0.0.1 192.168.1.2"

###
# OpenRoberta-Lab
###

# release, cf. https://github.com/OpenRoberta/openroberta-lab/releases
ORL_VERSION="5.1.3"

# the URL to open in a browser
ORL_URL="http://localhost/"
# cf. https://www.open-roberta.org/lokale-installation/
#ORL_URL="http://orlab/"
# with an internet connection
#ORL_URL="https://lab.open-roberta.org/"

###
# debugging and more
###

# install all dependencies
INSTALL_TOOLS="true"

# only generate the resulting kickstart file
ONLY_KS_FLAT="false"

# cleanup when completing
CLEANUP="true"

#############################################################################

# you can overwrite the above variables in an .env file
if [ -f "./.env" ]
then
  . ./.env
fi

# you can provide WiFi credentials (WIFI_INTERFACE, WIFI_SSID, WIFI_PASSWORD)
# in a .secrets file
if [ -f "./.secrets" ]
then
  . ./.secrets
fi

#############################################################################

LABEL="OpenRoberta"
TITLE="$LABEL Live Linux - based on Fedora Linux"
VOLID="Roberta"

KS_NAME=$(dirname $0)/fedora-live-$LABEL.ks
KS_FLAT_FILE=$(mktemp)

LORAX_TMPL_DIR=$(mktemp -d --suffix=_lorax-templates)

INST_ISO_NAME="Fedora-Server-netinst-$RELEASE_ARCH-$RELEASEVER-$RELEASEVER_MIN.iso"
INST_ISO_URL="${REPO_URL}releases/$RELEASEVER/Server/$RELEASE_ARCH/iso/$INST_ISO_NAME"
INST_ISO_PATH=/tmp/$INST_ISO_NAME

UPDATES_URL="${REPO_URL}updates/$RELEASEVER/Everything/$RELEASE_ARCH/"

BUILD_ISO_NAME="Fedora-$LABEL-Live-$RELEASE_ARCH-$RELEASEVER.iso"

#############################################################################

if [ "$INSTALL_TOOLS" = "true" ]
then
  sudo dnf install -y \
    livecd-tools \
    spin-kickstarts pykickstart \
    qemu virt-install \
  || exit 4
fi

#############################################################################

ksflatten -c "$KS_NAME" -o "$KS_FLAT_FILE" \
|| exit 1
sed -i'' "$KS_FLAT_FILE" \
  -e "s/\(keyboard\ \).*/\1\'$OS_KEYBOARD\'/" \
  -e "s/\(lang\ \).*/\1$OS_LANG/" \
  -e "s/\(timezone \).*/\1$(echo $OS_TZ | sed -e 's/\//\\\//g')/" \
  -e "s/^\(url --\).*/\1url=\"$(echo $UPDATES_URL | sed -e 's/\//\\\//g')\"/" \
  -e "s/\(ORC_VERSION=\).*/\1\"$ORC_VERSION\"/" \
  -e "s/\(ORL_URL=\).*/\1\"$(echo $ORL_URL | sed -e 's/\//\\\//g')\"/" \
  -e "s/\(WIFI_INTERFACE=\).*/\1\"$WIFI_INTERFACE\"/" \
  -e "s/\(WIFI_SSID=\).*/\1\"$(echo $WIFI_SSID | sed -e 's/\//\\\//g')\"/" \
  -e "s/\(WIFI_PASSWORD=\).*/\1\"$(echo $WIFI_PASSWORD | sed -e 's/\//\\\//g')\"/" \
|| exit 2
# workaround: remove @x86-baremetal-tools package
sed -i'' "$KS_FLAT_FILE" -e "s/^\(@x86-baremetal-tools\)/#\1/" \
|| exit 3

if [ "$ONLY_KS_FLAT" != "false" ]
then
  echo "prepared flattened kickstart file: $KS_FLAT_FILE"
  exit 0
fi

#############################################################################

cp -a /usr/share/lorax/templates.d/*/live $LORAX_TMPL_DIR/ \
|| exit 5
for FILE in $LORAX_TMPL_DIR/live/config_files/x86/*
do
  sed -i'' $FILE \
    -e 's/\(set default\).*/\1="0"/' \
    -e "s/\(set timeout\).*/\1=$GRUB_TIMEOUT/" \
  || exit 6
done

#############################################################################

if [ -n "$PROXY_URL" ]
then
  PROXY_OPT="--proxy=$PROXY_URL"
  export https_proxy=$PROXY_URL
fi

#############################################################################

curl -C - --retry 5 -L \
  -o $INST_ISO_PATH \
  $INST_ISO_URL \
&& \
echo "SHA256 ($INST_ISO_PATH) = $RELEASE_SHA256" | sha256sum -c - \
|| exit 7

#############################################################################

sudo livemedia-creator \
  --ks $KS_FLAT_FILE \
  --volid "$VOLID" \
  --project "$TITLE" \
  --make-iso \
  --iso-only \
  --iso-name $BUILD_ISO_NAME \
  --releasever $RELEASEVER \
  --lorax-templates=$LORAX_TMPL_DIR \
  $PROXY_OPT \
  --iso $INST_ISO_PATH \
  --vcpus $VCPUS \
  --resultdir build \
|| exit 8

#############################################################################

if [ "$CLEANUP" = "true" ]
then
  rm -f $KS_FLAT_FILE
  if [ -d "$LORAX_TMPL_DIR" ]
  then
    rm -rf $LORAX_TMPL_DIR/
  fi
fi
