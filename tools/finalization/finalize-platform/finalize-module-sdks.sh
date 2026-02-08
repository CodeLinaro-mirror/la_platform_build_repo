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

m unpack-module-sdks
projects="$(unpack-module-sdks \
    --mainline-sdks-top "$mainline_sdks_dir" \
    --android-top "$top" \
    --sdk-ext-version $SDK_EXT_VERSION)"

for project in $projects; do
    git_commit \
        $project \
<<EOF
Finalize SDK extension $SDK_EXT_VERSION

Import module SDK artifacts from ab/$BUILD_NUMBER.
EOF
done

# vi: expandtab sw=4 ts=4
