#!/bin/bash

################################################################################
# Copyright (c) 2014, 2015 Genome Research Ltd.
#
# Author: Matthew Rahtz <matthew.rahtz@sanger.ac.uk>
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
################################################################################

# exit automatically on non-0 exit of any command
set -o errexit
# exit on unset variable
set -o nounset

function usage
{
    echo "Usage: $0 create/recreate/destroy <image name> <container name>" >&2
    echo >&2
    echo "  Starts a (detached) Docker container from the given image," >&2
    echo "  sets its hostname to <container name>, " >&2
    echo "  bridges its interface to br0," >&2
    echo "  and starts a DHCP client on its network interface." >&2
    echo >&2
    echo "  'recreate' first checks whether a container already exists," >&2
    echo "  and destroys it if it does, before creating." >&2
    echo >&2
    echo "NOTE: the image should be set up to run a service," >&2
    echo "otherwise the container will exit immediately from being" >&2
    echo "started in detached mode" >&2
}

function escape
{
    local raw_name=$1
    # replace anything other than a-z, A-Z, 0-9, or '-' with an underscore
    local escaped_name=$(sed 's/[^a-zA-Z0-9-]/_/g' <<< "$raw_name")
    echo "$escaped_name"
}

function check_environment
{
    if [[ $USER != "root" ]]; then
        echo "Error: must be run as root" >&2
        exit 1
    fi

    if ! which docker > /dev/null; then
        echo "Error: docker not installed" >&2
        exit 1
    fi
    if ! which brctl > /dev/null; then
        echo "Error: brctl not installed" >&2
        exit 1
    fi
    if ! which nsenter > /dev/null; then
        echo "Error: nsenter not installed" >&2
        exit 1
    fi
    if ! brctl show | grep -q '^br0\s'; then
        echo "Error: bridge br0 doesn't exist" >&2
        exit 1
    fi
    if ! which dhcpcd > /dev/null; then
        echo "Error: dhcpcd not installed" >&2
        exit 1
    fi
}

function clean_up
{
    rm -f "/var/run/netns/$CONTAINER_NAME"
}

# create a container with no networking,
# manually create a pair of interfaces,
# bridge the host-side with the host adapter,
# move the other one into the container's namespace,
# and run dhcpcd on the container-side one
function create_container
{
    local image_name=$1
    local container_name=$2

    # can't just use hostname because of length restriction
    local iface=$(mktemp --dry-run XXXX)

    trap '{
        rm -f "/var/run/netns/$container_name"
        ip link del "veth-$iface-0"
    }' ERR SIGINT

    echo "Creating container..."
    local container_id=$(\
        # command is specified in Dockerfile
        docker run \
            --name="$container_name" --hostname="$container_name" \
            --detach \
            --net=none "$image_name"
    )
    if [[ $container_id == "" ]]; then
        echo "Error: failed to create container" >&2
        exit 1
    fi
    local pid=$(docker inspect -f '{{.State.Pid}}' "$container_id")

    echo "Creating network namespace..."
    # create a network namespace
    mkdir -p /var/run/netns
    ln -sfn "/proc/$pid/ns/net" "/var/run/netns/$container_name"

    # create a two-ended network interface
    ip link add "veth-$iface-0" type veth peer name "veth-$iface-1"
    brctl addif br0 "veth-$iface-0"
    # veth-0 stays in the main namespace
    ip link set "veth-$iface-0" up
    # veth-1 is placed in the container's namespace
    ip link set "veth-$iface-1" netns "$container_name"

    echo "Waiting for DHCP..."
    # dhcpcd preferable to dhclient because dhclient's apparmor profile
    # prevents it from reading dhclient.conf from anywhere but /etc/,
    # and there's no other way to specify hostname
    # nsenter used instead of 'ip netns exec' because that also
    # sets up a mount namespace for the process which inherits
    # the aufs mounts, which can cause conflicts later on
    # when they're unmounted in the 'main' namespace
    # --nontp: don't touch /etc/ntp.conf or restart NTP server
    nsenter --net=/var/run/netns/"$container_name" \
        dhcpcd-bin \
        --nontp \
        --pidfile="/var/run/dhcpcd-$container_name.pid" \
        --hostname="$container_name" \
        "veth-$iface-1"

    echo "Container $container_name created successfully"
}

function destroy_container
{
    local container_name=$1

    if ! docker inspect "$container_name" &> /dev/null; then
        echo "Error: container '$container_name' doesn't exist" >&2
        exit 1
    fi

    # turn off errexit for just this function
    # to clean up as much as possible
    set +e
    err=false

    # as long as dhcpcd isn't holding onto the interface,
    # it'll be removed automatically when the namespace is removed
    dhcpcd_pidfile="/var/run/dhcpcd-$container_name.pid"
    if [[ -e $dhcpcd_pidfile ]]; then
        read pid < "$dhcpcd_pidfile"
        kill "$pid" || err=true
        # wait for dhcpcd to really exit
        while [[ -e $dhcpcd_pidfile ]]; do
            sleep 0.5
        done
    fi

    docker kill "$container_name" > /dev/null || err=true
    # wait for the container to be stopped
    docker wait "$container_name" > /dev/null || err=true
    docker rm "$container_name" > /dev/null || err=true
    rm -f "/var/run/netns/$container_name" || err=true

    if $err; then
        echo "Error while destroying container '$container_name'"
    else
        echo "Container '$container_name' destroyed successfully"
    fi

    set -o errexit
}

if [[ $# != 3 ]]; then
    echo "Error: wrong number of arguments" >&2
    usage
    exit 1
fi
readonly MODE=$1
readonly IMAGE_NAME=$2
readonly RAW_CONTAINER_NAME=$3
if [[ $RAW_CONTAINER_NAME == "" ]]; then
    echo "Error: empty container name specified" >&2
    usage
    exit 1
fi
readonly CONTAINER_NAME=$(escape "$RAW_CONTAINER_NAME")

check_environment

case $MODE in
    create)
        create_container "$IMAGE_NAME" "$CONTAINER_NAME"
        ;;
    destroy)
        destroy_container "$CONTAINER_NAME"
        ;;
    recreate)
        if docker inspect "$CONTAINER_NAME" &> /dev/null; then
            destroy_container "$CONTAINER_NAME"
        fi
        create_container "$IMAGE_NAME" "$CONTAINER_NAME"
        ;;
    '')
        usage
        exit 1
        ;;
    *)
        echo "Error: invalid mode '$MODE'" >&2
        usage
        exit 1
        ;;
esac
