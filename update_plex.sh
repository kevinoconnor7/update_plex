#!/bin/bash
set -euf -o pipefail

util::cleanup() {
  echo $'  \e[39m[**]\e[0m Cleaning up...'
  if [[ -n ${DOWNLOAD_FILE_NAME+x} && -f "${DOWNLOAD_FILE_NAME}" ]]; then
    rm -f "${DOWNLOAD_FILE_NAME}" || true
  fi
  echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'
}

util::trapped_err() {
  exit_code="$?"
  echo -n $'  \e[39m[\e[1;31m!!\e[39m]\e[0m Last command failed with exit code: \e[1;31m' >&2
  echo -n "${exit_code}" >&2
  echo $'\e[0m' >&2
  exit $exit_code
}

util::is_plex_running() {
  STATUS=$(systemctl show -p SubState plexmediaserver | sed 's/SubState=//g')
  if [[ "${STATUS}" != "running" ]]; then
    return 1
  fi
  return 0
}

trap util::trapped_err ERR
trap util::cleanup EXIT

if ! [ -x "$(command -v jq)" ]; then
  echo $'  \e[39m[\e[1;31m!!\e[39m]\e[0m \e[1;35mjq\e[0m is not installed.' >&2
  exit 1
fi

: "${PLEX_DISTRO:=debian}"
: "${PLEX_BUILD:=linux-x86_64}"
PLEX_RELEASES_URL="https://plex.tv/api/downloads/5.json"
if [[ -z "${PLEX_TOKEN:=}" ]]; then
  echo $'  \e[39m[\e[33m!!\e[39m]\e[0m \e[35mPLEX_TOKEN\e[0m is not set. We will check for public releases.' >&2
else
  PLEX_RELEASES_URL="${PLEX_RELEASES_URL}?channel=plexpass"
fi
JQ_SELECTOR=".computer.Linux.releases[] | select(.build == \"${PLEX_BUILD}\" and .distro == \"${PLEX_DISTRO}\")"

DOWNLOAD_FILE_NAME="$(mktemp -t plex_XXXXXXXXXX.deb)"
SCRIPT_DIR=$(dirname -- "$(readlink -f -- "$0")")
CHECKSUM_FILE="$SCRIPT_DIR/.plex_update_checksum"

echo $'  \e[39m[**]\e[0m Downloading update manifest...'
MANIFEST=$(curl -sSL \
  -H "X-Plex-Token: ${PLEX_TOKEN}" \
  "${PLEX_RELEASES_URL}")
echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'

NEW_CHECKSUM=$(echo "${MANIFEST}" | jq -r "${JQ_SELECTOR}.checksum")

if [ -z "${NEW_CHECKSUM}" ]; then
  echo $'  \e[39m[\e[1;31m!!\e[39m]\e[0m Failed to parse new update checksum' >&2
  exit 1
fi

LAST_CHECKSUM=$(cat "${CHECKSUM_FILE}" 2>/dev/null || true)
if [ "${NEW_CHECKSUM}" == "${LAST_CHECKSUM}" ]; then
  echo $'  \e[39m[\e[32m++\e[39m]\e[0m We already have the latest update!' >&2
  exit 0
fi

echo $'  \e[39m[**]\e[0m Downloading latest update...'
PLEX_DOWNLOAD_URL=$(echo "${MANIFEST}" | jq -r "${JQ_SELECTOR}.url")

curl -sSLo "${DOWNLOAD_FILE_NAME}" "${PLEX_DOWNLOAD_URL}" >/dev/null
echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'

echo $'  \e[39m[**]\e[0m Installing latest update...'
dpkg -i --refuse-downgrade "${DOWNLOAD_FILE_NAME}"
echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'

echo $'  \e[39m[**]\e[0m Saving checksum...'
echo "${NEW_CHECKSUM}" >"${CHECKSUM_FILE}"
echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'


echo $'  \e[39m[**]\e[0m Checking if Plex is running now...'
if ! util::is_plex_running; then
  echo $'  \e[39m[&&]\e[0m Waiting for startup...'
  sleep 5
  if ! util::is_plex_running; then
    echo $'  [\e[1;33m!!\e[0m] Plex hasn\'t started. Sending start command...'
    systemctl start plexmediaserver
  fi
fi
echo $'  \e[39m[\e[32m++\e[39m]\e[0m Done'

exit 0