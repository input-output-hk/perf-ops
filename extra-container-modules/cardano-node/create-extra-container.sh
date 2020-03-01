#!/run/current-system/sw/bin/bash
set -x
CONTAINER_FILE="$1"
CONTAINER_NAME="$2"
HOST_ADDRESS="$3"
NETWORK="$4"
IPADDR="$5"
SRCDIR="$6"

tmp="$(mktemp -d -t "${CONTAINER_NAME}"-XXXX)"

rsync -az --exclude *.tgz "${SRCDIR}/." "$tmp"/
pushd "$tmp" || exit 1

sed -i.bak -e "s/CONTAINER_NAME/${CONTAINER_NAME}/g" \
           -e "s/HOST_ADDRESS/${HOST_ADDRESS}/g"     \
           -e "s/NETWORK/${NETWORK}/g"               \
           -e "s/IPADDR/${IPADDR}/g" "$CONTAINER_FILE"

@extraContainer@ create "$CONTAINER_FILE" --start
popd || exit 1
rm -rf "$tmp"
set +x
exit 0
