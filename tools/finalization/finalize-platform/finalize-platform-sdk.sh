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

# introduce new SDK extension
apply_patches \
    packages/modules/SdkExtensions \
    "$BUNDLED_PATCHES"/packages/modules/SdkExtensions/0001-derive_sdk-introduce-C-extension.patch \
    "$BUNDLED_PATCHES"/packages/modules/SdkExtensions/0002-SdkExtensions-introduce-C-extension.patch \
    "$BUNDLED_PATCHES"/packages/modules/SdkExtensions/0003-sdk-extensions-info.xml-add-the-C-SDK-extensions-C-e.patch
apply_patches \
    packages/modules/common \
    "$BUNDLED_PATCHES"/packages/modules/common/0001-sdk.proto-add-C-modules-none.patch
apply_patches \
    frameworks/libs/modules-utils \
    "$BUNDLED_PATCHES"/frameworks/libs/modules-utils/0001-Add-isAtLeastC.patch

# update Build.java and aapt
apply_patches \
    frameworks/base \
    "$BUNDLED_PATCHES"/frameworks/base/0001-C-is-37.patch

# set SDK extension versions (or $SDK_EXT_VERSION won't appear in api-versions.xml)
for release_config in next trunk trunk_staging; do
    set_build_flags $release_config RELEASE_PLATFORM_SDK_EXTENSION_VERSION=$SDK_EXT_VERSION
done

# build the SDK
set_build_flags next RELEASE_PLATFORM_PROSPECTIVE_SDK_VERSION_FULL=37.0
m sdk sdk_repo dist

# populate prebuilts/sdk
#
# Will update these files under prebuilts/sdk:
#
#   - $MAJOR/**/*
#   - current/**/*
#   - latest
#   - Android.bp
#
# -f $MAJOR instead of $major.$minor to force update_prebuilts.py to
# update the 37 directory instead of creating a new 37.0 directory
# (TODO: debug why renaming the existing directory to 37.0 first
# doesn't work)
#
# TODO: extract the logic of update_framework in update_prebuilts.py (and
# rewrite to be more readable), but for now, call the legacy script
$TOP/prebuilts/sdk/update_prebuilts/update_prebuilts.py \
    -f $MAJOR \
    --local_mode \
    --bug $BUG \
    1234 # doesn't matter in local mode

# update_prebuilts.py updates current/ but that directory should only hold
# artifacts from sdk_with_runtime_apis builds; undo those changes before
# committing
#
# Also remove the unwanted SDK zip file that --local_mode copies
pushd "$TOP"/prebuilts/sdk
rm android-sdk*.zip
git checkout current
git clean -fd current
popd


git_commit \
    prebuilts/sdk \
<<EOF
Finalize platform SDK for Android $MAJOR.$MINOR

Files imported from ab/$BUILD_NUMBER.

EOF

# hotfix to fix broken build
apply_patches \
    packages/apps/Settings \
    "$BUNDLED_PATCHES"/packages/apps/Settings/0001-Fix-compilation-error-after-37.0-finalization.patch
