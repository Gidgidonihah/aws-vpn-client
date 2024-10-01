#!/usr/bin/env bash

set -e


SCRIPT_NAME=$(basename "$0")
HELP=$(cat <<EOF
Usage: $SCRIPT_NAME [-x EXECUTABLE] [-c config] config

Connect to an AWS VPN.

Options:
  -h    Print this help message
  -x    Path to patched OpenVPN executable
  -c    Config name. Matching .conf file must be found in ./config.
          May also be supplied positionally, but will not be used if both are supplied.
  -a    Ensure that AWS CLI is authenticated via sso

Example(s):
   $SCRIPT_NAME -x /usr/local/bin/openvpn-patched stag
EOF
)
usage() {
  echo "$HELP" 1>&2;
  if [ "$#" == 1 ]; then
    echo "\n$1";
  fi
  exit 1;
}

while getopts ":hx:c:a" OPTION; do
    case $OPTION in
      h) usage ;;
      x) OVPN_BIN=$OPTARG;;
      c) CONFIG_NAME=$OPTARG ;;
      a) AWS_LOGIN=true ;;
      :) usage "Error: '-$OPTARG' requires an argument" ;;
      *) usage "Error: '-$OPTARG' is not a valid option" ;;
    esac
done

# Shift past the parsed options
shift $((OPTIND-1))

# Ensure we have a config supplied
CONFIG_NAME=${CONFIG_NAME:=$1}
if [ -z "$CONFIG_NAME" ]; then
  echo "$HELP" 1>&2;
  echo
  echo "Error: A config name is required." >&2
  exit 1
fi

# Ensure we have an executable. Assume openvpn is patched if not supplied.
OVPN_BIN=${OVPN_BIN:="openvpn"}

# Ensure we have a config file
OVPN_CONF="configs/$CONFIG_NAME.conf"
if [[ ! -f "$OVPN_CONF" ]]; then
  echo "Error: Configuration file $OVPN_CONF not found."
  exit 1
fi

# Get the VPN hostname/port/protocol
VPN_HOST=$(cat $OVPN_CONF | grep 'remote ' | cut -d ' ' -f2)
PORT=$(cat $OVPN_CONF | grep 'remote ' | cut -d ' ' -f3)
PROTOCOL=$(cat $OVPN_CONF | grep 'proto ' | cut -d ' ' -f2)

# Make sure we clean everything up upon exit
cleanup() {
    echo "Cleaning up..."
    rm -f saml-response.txt
    rm -f "$TMP_CONF"
}
trap cleanup EXIT

# Copy and filter lines from OVPN_CONF to TMP_CONF
# This will remove any of the following lines if present
# Inspect your ovpn config and remove the following lines if present
# - `auth-user-pass` (we dont want to show user prompt)
# - `auth-federate` (propietary AWS keyword)
# - `auth-retry interact` (do not retry on failures)
# - `remote` (already handled in CLI and can cause conflicts with it)
# - `remote-random-hostname` (already handled in CLI and can cause conflicts with it)
TMP_CONF=$(mktemp)
patterns=(
  "^auth-user-pass"
  "^auth-federate"
  "^auth-retry.interact"
  "^remote"
  "^remote-random-hostname"
)
# Join the array elements into a single string, separated by '|'
STRIPPED_LINES=$(IFS='|'; echo "${patterns[*]}")
grep -Ev $STRIPPED_LINES "$OVPN_CONF" > "$TMP_CONF"


# Start the go server to handle capturing the SAML response
./aws-saml-response-server > /dev/null 2>&1 &
SERVER_PID=$!
echo "Go server process started with PID $SERVER_PID"
quit_server() {
    # Kill the Go process
    kill $SERVER_PID || echo "Go process with PID $SERVER_PID not found"
    echo "Go process with PID $SERVER_PID has been killed"
}

wait_file() {
  local file="$1"; shift
  local wait_seconds="${1:-10}"; shift # 10 seconds as default timeout
  until test $((wait_seconds--)) -eq 0 -o -f "$file" ; do sleep 1; done
  ((++wait_seconds))
}

open_url() {
    URL=$1
    echo "Opening browser and wait for the response file..."
    unameOut="$(uname -s)"
    case "${unameOut}" in
        Linux*)     xdg-open "$URL";;
        Darwin*)    open "$URL";;
        *)          echo "Could not determine 'open' command for this OS"; exit 1;;
    esac
}

aws_login_if_required() {
    if [ ${AWS_LOGIN:=false} == true ]; then
        LOGIN=$(aws sts get-caller-identity &> /dev/null&&echo 'success'||echo 'fail')
        if [ $LOGIN != 'success' ]; then
            echo "Logging into AWS..."
            aws sso login
        fi
    fi

}

# create random hostname prefix for the vpn gw
RAND=$(openssl rand -hex 12)

# Resolve manually hostname to IP, as we have to keep persistent ip address
SRV=$(dig a +short "${RAND}.${VPN_HOST}"|head -n1)

# Get the login URL
echo "Getting SAML redirect URL from the AUTH_FAILED response (host: ${SRV}:${PORT})"
OVPN_OUT=$($OVPN_BIN --config "${TMP_CONF}" --verb 3 \
     --proto "$PROTOCOL" --remote "${SRV}" "${PORT}" \
     --auth-user-pass <( printf "%s\n%s\n" "N/A" "ACS::35001" ) \
    2>&1 | grep AUTH_FAILED,CRV1)

# Open the login URL in a browser
open_url $(echo "$OVPN_OUT" | grep -Eo 'https://.+')

# Wait for the saml-response file to show up, saved from the go server
wait_file "saml-response.txt" 30 || {
  quit_server
  echo "SAML Authentication time out"
  exit 1
}
quit_server

# Ensure aws-cli is authenticated if required
aws_login_if_required

# Get SID from the reply
VPN_SID=$(echo "$OVPN_OUT" | awk -F : '{print $7}')

echo "Running OpenVPN with sudo. Enter password if requested"
sudo bash -c "$OVPN_BIN --config "${TMP_CONF}" \
    --verb 3 --auth-nocache --inactive 3600 \
    --proto "$PROTOCOL" --remote $SRV $PORT \
    --script-security 2 \
    --route-up '/usr/bin/env rm saml-response.txt' \
    --auth-user-pass <( printf \"%s\n%s\n\" \"N/A\" \"CRV1::${VPN_SID}::$(cat saml-response.txt)\" )"
