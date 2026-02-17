#!/bin/bash
#
# Copyright (C) 2026 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Calculate the top of the android source tree
top="${ANDROID_BUILD_TOP:-$(dirname "${BASH_SOURCE[0]}")/../../../../..}"

# Add the host bin directory to the PATH so that tools can be found by CI
export PATH="$top/${OUT_DIR:-out}/host/linux-x86/bin:$PATH"

# The current build ID (set if running on a build server)
BUILD_NUMBER=${BUILD_NUMBER:=local-build}

# Define the m function to run the build.
# This function uses the TARGET_PRODUCT, TARGET_RELEASE, and TARGET_BUILD_VARIANT environment variables if they are set.
# Otherwise, it uses default values (sdk, sdk_finalization, and userdebug respectively).
function m() {
    "$top/build/soong/soong_ui.bash" --make-mode \
        "TARGET_PRODUCT=${TARGET_PRODUCT:-sdk}" \
        "TARGET_RELEASE=${TARGET_RELEASE:-sdk_finalization}" \
        "TARGET_BUILD_VARIANT=${TARGET_BUILD_VARIANT:-userdebug}" \
        "$@"
}

# Print a debug message
function info() {
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    if [[ -t 1 ]]; then
        echo -e "\e[90m${timestamp} \e[33mINFO\e[0m $1"
    else
        echo -e "${timestamp} INFO $1"
    fi
}

# Print an error message
function error() {
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    if [[ -t 1 ]]; then
        echo -e "\e[90m${timestamp} \e[31mERROR\e[0m $1"
    else
        echo -e "${timestamp} ERROR $1"
    fi
}

# Create a git commit.
#
# Will create the topic $BRANCH and add all modified files in a given project
# before committing the changes.
#
# $1: project path relative to $top
# stdin: commit message
function git_commit() {
    local project="$1"

    pushd "$top/$project"
    repo start "$BRANCH" .
    git add .
    git commit -F -
    popd
}

# Traverse the Android tree and create patch files for all commits on the topic
# $BRANCH.
#
# $1: path to directory in which to store the patch files
function format_patches_into_patchdir() {
    local patch_dir="$1"
    mkdir -p $patch_dir

    # repo forall has a timeout and formatting patches in prebuilts/sdk will
    # trigger this timeout, so only use repo forall to get the list of projects
    for path in $(repo forall -c pwd); do
        if [[ "$(git -C "$path" branch --show-current)" == "$BRANCH" ]]; then
            project="${path#$top/}"
            mkdir -p "$patch_dir/$project"
            git -C "$path" format-patch -o "$patch_dir/$project" "$BRANCH" ^goog/main
        fi
    done
}


# Create the topic $BRANCH and apply patches to a given project
#
# $1: project path relative to $top
# $2, ...: paths to patch files to apply
function apply_patches() {
    local project="$1"
    shift

    pushd "$top/$project"
    repo start "$BRANCH" .
    git am --whitespace=nowarn $*
    popd
}

# Create the topic $BRANCH and apply patches to the Android tree
#
# The patches are expected to have been created by
# format_patches_into_patchdir.
#
# $1: path to directory of patches
function apply_patches_from_patchdir() {
    local patch_dir="$1"
    for project in $(find $patch_dir -type f -printf "%P\n" | xargs dirname | sort -u); do
        apply_patches \
            "$project" \
            $(ls $patch_dir/$project/*.patch | sort)
    done
}

# vi: expandtab sw=4 ts=4
