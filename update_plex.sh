#!/bin/bash
set -euf -o pipefail

util::cleanup() {
	echo "Cleaning up..."
	rm -f "${DOWNLOAD_FILE_NAME}" || true
	echo "  Done"
}

util::gentle_exit() {
	echo $1 >&2
	util::cleanup
	exit 1
}

util::trapped_err() {
	exit_code="$?"
	echo "Last command failed with exit code: ${exit_code}" >&2
	util::cleanup
	exit "${exit_code}"
}

trap util::trapped_err ERR

if [[ -z "${PLEX_TOKEN}" ]]; then
	util::gentle_exit "Environment variable PLEX_TOKEN must be set."
fi

PLEX_DOWNLOAD_URL="https://plex.tv/downloads/latest/1?channel=8&build=linux-ubuntu-x86_64&distro=ubuntu&X-Plex-Token=${PLEX_TOKEN}"
DOWNLOAD_FILE_NAME="/tmp/plex_$(date +'%m_%d_%Y').pkg"
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$0")")
CHECKSUM_FILE="$SCRIPT_DIR/.plex_update_checksum"

echo "Downloading latest update..."
curl -sSLo "${DOWNLOAD_FILE_NAME}" "${PLEX_DOWNLOAD_URL}" >/dev/null
if [ $? -ne 0 ]; then
	util::gentle_exit "Failed to download latest update"
fi
echo "  Done!"

echo "Getting update file hash..."
DOWNLOAD_CHECKSUM=$(sha256sum $DOWNLOAD_FILE_NAME | head -c 64)
if [ $? -ne 0 ]; then
	util::gentle_exit "Failed to get checksum"
fi
echo "  Done!"

echo "Checking if we have the latest update..."
LAST_CHECKSUM=$(cat "${CHECKSUM_FILE}" 2>/dev/null || true)
if [ "${DOWNLOAD_CHECKSUM}" == "${LAST_CHECKSUM}" ]; then
	echo "We already have the latest update"
	util::cleanup
	exit 0
fi
echo "  Done"

echo "Installing latest update"
dpkg -i "${DOWNLOAD_FILE_NAME}"
if [ $? -ne 0 ]; then
	util::gentle_exit "Failed to install update"
fi
echo "  Done"

echo "Saving checksum"
echo "${DOWNLOAD_CHECKSUM}" >"${CHECKSUM_FILE}"
if [ $? -ne 0 ]; then
	echo "Failed to save update checksum"
	util::cleanup
	exit 0
fi
echo "  Done"

echo -n "Waiting for startup..."
sleep 5
echo " Done"

STATUS=$(systemctl show -p SubState plexmediaserver | sed 's/SubState=//g')
if [[ "${STATUS}" != "running" ]]; then
	echo -n "Starting service 'plexmediaserver'..."
	systemctl start plexmediaserver
	echo " Done"
fi

util::cleanup
exit 0
