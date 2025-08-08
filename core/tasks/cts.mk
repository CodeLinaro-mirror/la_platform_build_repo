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

test_suite_name := cts
test_suite_tradefed := cts-tradefed
test_suite_dynamic_config := cts/tools/cts-tradefed/DynamicConfig.xml
test_suite_readme := cts/tools/cts-tradefed/README

$(call declare-1p-target,$(test_suite_dynamic_config),cts)
$(call declare-1p-target,$(test_suite_readme),cts)

include $(BUILD_SYSTEM)/tasks/tools/compatibility.mk

.PHONY: cts
cts: $(compatibility_zip) $(compatibility_tests_list_zip) $(compatibility_files_metadata)
$(call dist-for-goals, cts, $(compatibility_zip) $(compatibility_tests_list_zip) $(compatibility_files_metadata))

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

# Creates a "cts-verifier" directory that will contain:
#
# 1. Out directory with a "android-cts-verifier" containing the CTS Verifier
#    and other binaries it needs.
#
# 2. Zipped version of the android-cts-verifier directory to be included with
#    the build distribution.
##
cts-dir := $(HOST_OUT)/cts-verifier
verifier-dir-name := android-cts-verifier
verifier-dir := $(cts-dir)/$(verifier-dir-name)
verifier-zip-name := $(verifier-dir-name).zip
verifier-zip := $(cts-dir)/$(verifier-zip-name)
cts-v-host-zip := $(HOST_OUT)/cts-v-host/android-cts-v-host.zip

cts : $(verifier-zip)
ifeq ($(wildcard cts/tools/cts-v-host/README),)
$(verifier-zip): PRIVATE_DIR := $(cts-dir)
$(verifier-zip): $(SOONG_ANDROID_CTS_VERIFIER_ZIP)
	rm -rf $(PRIVATE_DIR)
	mkdir -p $(PRIVATE_DIR)
	unzip -q -d $(PRIVATE_DIR) $<
	$(copy-file-to-target)
else
$(verifier-zip): PRIVATE_DIR := $(cts-dir)
$(verifier-zip): PRIVATE_verifier_dir := $(verifier-dir)
$(verifier-zip): PRIVATE_host_zip := $(cts-v-host-zip)
$(verifier-zip): $(SOONG_ANDROID_CTS_VERIFIER_ZIP) $(cts-v-host-zip) $(SOONG_ZIP)
	rm -rf $(PRIVATE_DIR)
	mkdir -p $(PRIVATE_DIR)
	unzip -q -d $(PRIVATE_DIR) $<
	unzip -q -d $(PRIVATE_verifier_dir) $(PRIVATE_host_zip)
	$(SOONG_ZIP) -d -o $@ -C $(PRIVATE_DIR) -D $(PRIVATE_verifier_dir)
endif
$(call dist-for-goals, cts, $(verifier-zip))

cts_api_map_exe := $(HOST_OUT_EXECUTABLES)/cts-api-map

api_map_out := $(HOST_OUT)/cts-api-map

cts_jar_files := $(api_map_out)/cts_jar_files.txt
cts_v_host_jar_files := $(api_map_out)/cts_v_host_jar_files.txt
cts_all_jar_files := $(api_map_out)/cts_all_jar_files.txt

$(cts_jar_files): PRIVATE_API_MAP_FILES := $(sort $(COMPATIBILITY.cts.API_MAP_FILES))
$(cts_jar_files):
	mkdir -p $(dir $@)
	echo $(PRIVATE_API_MAP_FILES) > $@

$(cts_v_host_jar_files): PRIVATE_API_MAP_FILES := $(sort $(COMPATIBILITY.cts-v-host.API_MAP_FILES))
$(cts_v_host_jar_files): $(SOONG_ANDROID_CTS_VERIFIER_APP_LIST)
	mkdir -p $(dir $@)
	cp $< $@
	echo $(PRIVATE_API_MAP_FILES) >> $@

$(cts_all_jar_files): PRIVATE_API_MAP_FILES := $(sort $(COMPATIBILITY.cts.API_MAP_FILES) \
                                                      $(COMPATIBILITY.cts-v-host.API_MAP_FILES))
$(cts_all_jar_files): $(SOONG_ANDROID_CTS_VERIFIER_APP_LIST)
	mkdir -p $(dir $@)
	cp $< $@
	echo $(PRIVATE_API_MAP_FILES) >> $@

api_xml_description := $(TARGET_OUT_COMMON_INTERMEDIATES)/api.xml

system_api_xml_description := $(TARGET_OUT_COMMON_INTERMEDIATES)/system-api.xml
module_lib_api_xml_description := $(TARGET_OUT_COMMON_INTERMEDIATES)/module-lib-api.xml
system_service_api_description := $(TARGET_OUT_COMMON_INTERMEDIATES)/system-server-api.xml

combined_api_xml_description := $(api_xml_description) \
  $(system_api_xml_description) \
  $(module_lib_api_xml_description) \
  $(system_service_api_description)

cts-api-map-xml-report := $(api_map_out)/cts-api-map.xml
cts-v-host-api-map-xml-report := $(api_map_out)/cts-v-host-api-map.xml
cts-combined-api-map-xml-report := $(api_map_out)/cts-combined-api-map.xml
cts-combined-api-map-html-report := $(api_map_out)/cts-combined-api-map.html
cts-combined-api-inherit-xml-report := $(api_map_out)/cts-combined-api-inherit.xml

cts_api_map_dependencies := $(cts_api_map_exe) $(combined_api_xml_description) $(cts_jar_files)
cts_v_host_api_map_dependencies := $(cts_api_map_exe) $(combined_api_xml_description) $(cts_v_host_jar_files)
cts_combined_api_map_dependencies := $(cts_api_map_exe) $(combined_api_xml_description) $(cts_all_jar_files)

android_cts_zip := $(HOST_OUT)/cts/android-cts.zip
cts_verifier_apk := $(call intermediates-dir-for,APPS,CtsVerifier)/package.apk

.PHONY: cts-api-coverage

$(cts-api-map-xml-report): PRIVATE_CTS_API_MAP_EXE := $(cts_api_map_exe)
$(cts-api-map-xml-report): PRIVATE_API_XML_DESC := $(combined_api_xml_description)
$(cts-api-map-xml-report): PRIVATE_JAR_FILES := $(cts_jar_files)
$(cts-api-map-xml-report) : $(android_cts_zip) $(cts_api_map_dependencies) | $(ACP)
	$(call generate-api-map-report-cts,"CTS API MAP Report - XML",\
			$(PRIVATE_JAR_FILES),xml)

$(cts-v-host-api-map-xml-report): PRIVATE_CTS_API_MAP_EXE := $(cts_api_map_exe)
$(cts-v-host-api-map-xml-report): PRIVATE_API_XML_DESC := $(combined_api_xml_description)
$(cts-v-host-api-map-xml-report): PRIVATE_JAR_FILES := $(cts_v_host_jar_files)
$(cts-v-host-api-map-xml-report) : $(verifier_zip) $(cts_v_host_api_map_dependencies) | $(ACP)
	$(call generate-api-map-report-cts,"CTS-V-HOST API MAP Report - XML",\
			$(PRIVATE_JAR_FILES),xml)

$(cts-combined-api-map-xml-report): PRIVATE_CTS_API_MAP_EXE := $(cts_api_map_exe)
$(cts-combined-api-map-xml-report): PRIVATE_API_XML_DESC := $(combined_api_xml_description)
$(cts-combined-api-map-xml-report): PRIVATE_JAR_FILES := $(cts_all_jar_files)
$(cts-combined-api-map-xml-report) : $(verifier_zip) $(android_cts_zip) $(cts_combined_api_map_dependencies) | $(ACP)
	$(call generate-api-map-report-cts,"CTS Combined API MAP Report - XML",\
			$(PRIVATE_JAR_FILES),xml)

$(cts-combined-api-map-html-report): PRIVATE_CTS_API_MAP_EXE := $(cts_api_map_exe)
$(cts-combined-api-map-html-report): PRIVATE_API_XML_DESC := $(combined_api_xml_description)
$(cts-combined-api-map-html-report): PRIVATE_JAR_FILES := $(cts_all_jar_files)
$(cts-combined-api-map-html-report) : $(verifier_zip) $(android_cts_zip) $(cts_combined_api_map_dependencies) | $(ACP)
	$(call generate-api-map-report-cts,"CTS Combined API MAP Report - HTML",\
			$(PRIVATE_JAR_FILES),html)

$(cts-combined-api-inherit-xml-report): PRIVATE_CTS_API_MAP_EXE := $(cts_api_map_exe)
$(cts-combined-api-inherit-xml-report): PRIVATE_API_XML_DESC := $(combined_api_xml_description)
$(cts-combined-api-inherit-xml-report): PRIVATE_JAR_FILES := $(cts_all_jar_files)
$(cts-combined-api-inherit-xml-report) : $(verifier_zip) $(android_cts_zip) $(cts_combined_api_map_dependencies) | $(ACP)
	$(call generate-api-inherit-report-cts,"CTS Combined API Inherit Report - XML",\
			$(PRIVATE_JAR_FILES),xml)

.PHONY: cts-api-map-xml
cts-api-map-xml : $(cts-api-map-xml-report)

.PHONY: cts-v-host-api-map-xml
cts-v-host-api-map-xml: $(cts-v-host-api-map-xml-report)

.PHONY: cts-combined-api-map-xml
cts-combined-api-map-xml : $(cts-combined-api-map-xml-report)

.PHONY: cts-combined-api-inherit-xml
cts-combined-api-inherit-xml : $(cts-combined-api-inherit-xml-report)

# Put the test api map report in the dist dir if "cts-api-coverage" is among the build goals.
$(call dist-for-goals, cts-api-coverage, $(cts-combined-api-map-xml-report):cts-api-map-report.xml)
$(call dist-for-goals, cts-api-coverage, $(cts-combined-api-inherit-xml-report):cts-api-inherit-report.xml)

ALL_TARGETS.$(cts-api-map-xml-report).META_LIC:=$(module_license_metadata)
ALL_TARGETS.$(cts-v-host-api-map-xml-report).META_LIC:=$(module_license_metadata)
ALL_TARGETS.$(cts-combined-api-map-xml-report).META_LIC:=$(module_license_metadata)
ALL_TARGETS.$(cts-combined-api-map-html-report).META_LIC:=$(module_license_metadata)
ALL_TARGETS.$(cts-combined-api-map-inherit-report).META_LIC:=$(module_license_metadata)

# Arguments;
#  1 - Name of the report printed out on the screen
#  2 - A file containing list of files that to be analyzed
#  3 - Format of the report
define generate-api-map-report-cts
	$(hide) mkdir -p $(dir $@)
	$(hide) $(PRIVATE_CTS_API_MAP_EXE) -j 8 -m api_map -m xts_annotation -a $(shell echo "$(PRIVATE_API_XML_DESC)" | tr ' ' ',') -i $(2) -f $(3) -o $@
	@ echo $(1): file://$$(cd $(dir $@); pwd)/$(notdir $@)
endef


# Arguments;
#  1 - Name of the report printed out on the screen
#  2 - A file containing list of files that to be analyzed
#  3 - Format of the report
define generate-api-inherit-report-cts
	$(hide) mkdir -p $(dir $@)
	$(hide) $(PRIVATE_CTS_API_MAP_EXE) -j 8 -m xts_api_inherit -a $(shell echo "$(PRIVATE_API_XML_DESC)" | tr ' ' ',') -i $(2) -f $(3) -o $@
	@ echo $(1): file://$$(cd $(dir $@); pwd)/$(notdir $@)
endef

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
