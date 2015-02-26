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

set -o errexit

function usage
{
    echo "Usage: $0 create/recreate/destroy" \
         " <container name prefix> <image name> <branch name>" >&2
    echo "Run from within a Git repository (bare or otherwise) " \
         "containing CFEngine configuration" >&2
    echo >&2
    echo "Creates a Docker container named " \
         "<container name prefix>-<branch name>" >&2
    echo "from the given image (mrahtz/cfe31srv or mrahtz/cfe36srv) and " >&2
    echo "pushes the given branch from the Git repository to the container." >&2
}

readonly MODE=$1
readonly CONTAINER_PREFIX=$2
readonly IMAGE_NAME=$3
readonly BRANCH_NAME=$4
readonly PROGDIR=$(dirname "$0")

if [[ $MODE == "" ]]; then
    echo "Error: no mode specified" >&2
    usage
    exit 1
fi
if [[ $IMAGE_NAME == "" ]]; then
    echo "Error: no image name specified" >&2
    usage
    exit 1
fi
if [[ $BRANCH_NAME == "" ]]; then
    echo "Error: no branch specified" >&2
    usage
    exit 1
fi

if ! git rev-parse --git-dir &> /dev/null; then
    echo "Error: current directory is not a Git repository" >&2
    exit 1
fi

if [[ $USER != root ]]; then
    echo "Error: must be run as root" >&2
    exit 1
fi

function escape
{
    local raw_name=$1
    # replace anything other than a-z, A-Z, 0-9, or '-' with a dash
    local escaped_name=$(sed 's/[^a-zA-Z0-9-]/-/g' <<< "$raw_name")
    echo "$escaped_name"
}

function create_container
{
    local image_name=$1
    local container_name=$2

    if ! git show-ref --verify --quiet refs/heads/"$BRANCH_NAME"; then
        echo "Error: branch '$BRANCH_NAME' doesn't exist" >&2
        exit 1
    fi

    echo "Creating docker container with name '$container_name' " \
         "from image '$image_name'..."
    "$PROGDIR/dhcp_container.sh" create "$image_name" "$container_name"
    # DNS sometimes takes a little while to appear
    time_waited_ms=0
    while ! host -t a "$container_name" > /dev/null &&
          (( time_waited_ms < 5000 )); do
        echo "Not in DNS yet, waiting..."
        sleep 0.5
        time_waited_ms=$((time_waited_ms+500))
    done
    if (( time_waited_ms >= 5000 )); then
        echo "Error: container name '$container_name' " \
             "never appeared in DNS..." >&2
        exit 1
    fi

    git remote add "$container_name" root@"$container_name":/var/cfengine_git

    echo "Waiting for cf-serverd to finish initialisation..."
    while ! nc -z "$container_name" 5308; do
        sleep 1
    done
    echo "cf-serverd appears to be listening"
}

function push_branch
{
    local container_name=$1

    echo "Pushing Git branch to container..."
    GIT_SSH="$PROGDIR/container_ssh.sh" \
        git push "$container_name" "$BRANCH_NAME"
}

function destroy_container
{
    local container_name=$1

    # turn off errexit to give the best chance of
    # not leaving stuff around
    set +e

    echo "Removing docker container '$container_name'..."
    "$PROGDIR/dhcp_container.sh" destroy mrahtz/cfe36srv "$container_name"
    git remote rm "$container_name"

    set -o errexit
}

container_name="$(escape "$CONTAINER_PREFIX")-$(escape "$BRANCH_NAME")"
if [[ $MODE == create ]]; then
    create_container "$IMAGE_NAME" "$container_name"
    push_branch "$container_name"
elif [[ $MODE == recreate ]]; then
    # the Docker Way would be to delete and recreate the container,
    # to avoid mutable state
    # however, a CFEngine client stores the address of the policy server
    # it's bootstrapped to as the IP address rather than the hostname:
    # https://dev.cfengine.com/issues/2954
    # this can be worked around by manually writing the hostname to
    # /var/cfengine/policy_server.dat, but then we still need to make
    # sure that the public keys stay the same for each server
    # we can do that by setting 'trustkey => "true"', but it's a bit of hack
    # overall, it's much simpler to just reuse the same container
    push_branch "$container_name"
elif [[ $MODE == destroy ]]; then
    destroy_container "$container_name"
else
    echo "Error: invalid mode '$MODE' specified" >&2
    usage
    exit 1
fi
