# Copyright (C) 2015 The Android Open Source Project
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

cts: cts-verifier

.PHONY: cts_v2
cts_v2: cts

# platform version check (b/32056228)
# ============================================================
ifneq (,$(wildcard cts/))
  cts_platform_version_path := cts/tests/tests/os/assets/platform_versions.txt
  cts_platform_version_string := $(shell cat $(cts_platform_version_path))
  cts_platform_release_path := cts/tests/tests/os/assets/platform_releases.txt
  cts_platform_release_string := $(shell cat $(cts_platform_release_path))

  ifneq (REL,$(PLATFORM_VERSION_CODENAME))
    ifeq (,$(findstring $(PLATFORM_VERSION),$(cts_platform_version_string)))
      define error_msg
        ============================================================
        Could not find version "$(PLATFORM_VERSION)" in CTS platform version file:
        $(cts_platform_version_path)
        Most likely PLATFORM_VERSION in build/core/version_defaults.mk
        has changed and a new version must be added to this CTS file.
        ============================================================
      endef
      $(error $(error_msg))
    endif
  endif
  ifeq (,$(findstring $(PLATFORM_VERSION_LAST_STABLE),$(cts_platform_release_string)))
    define error_msg
      ============================================================
      Could not find version "$(PLATFORM_VERSION_LAST_STABLE)" in CTS platform release file:
      $(cts_platform_release_path)
      Most likely PLATFORM_VERSION_LAST_STABLE in build/core/version_defaults.mk
      has changed and a new version must be added to this CTS file.
      ============================================================
    endef
    $(error $(error_msg))
  endif
endif

# Reset temp vars
cts_api_map_dependencies :=
cts_v_host_api_map_dependencies :=
cts_combined_api_map_dependencies :=
cts-api-map-xml-report :=
cts-v-host-api-map-xml-report :=
cts-combined-api-map-xml-report :=
cts-combined-api-map-html-report :=
cts-combined-api-map-inherit-report :=
api_xml_description :=
api_text_description :=
system_api_xml_description :=
combined_api_xml_description :=
napi_xml_description :=
napi_text_description :=
api_map_out :=
cts_jar_files :=
cts_api_map_exe :=
cts_verifier_apk :=
android_cts_zip :=
cts-dir :=
verifier-dir-name :=
verifier-dir :=
verifier-zip-name :=
verifier-zip :=
cts-v-host-zip :=
cts_files_metadata :=
file_metadata_generation_tool :=
aapt2_tool :=
