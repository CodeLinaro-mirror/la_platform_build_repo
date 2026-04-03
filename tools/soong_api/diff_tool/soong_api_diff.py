#!/usr/bin/env python3
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

import sqlite3
import zipfile
import json
import os
import re
import sys

# ANSI Escape Codes for coloring terminal output
RED = "\033[31m"
RESET = "\033[0m"

# 1. Map DB column names to JSON attribute names
# Supports One-to-Many mapping using Lists. If multiple JSON keys are provided,
# their values will be merged and deduplicated before comparison.
COLUMN_MAPPING = {
    "module_type": ["type"],
    "whole_static_dep_files": ["whole_static_lib_files"],
    "package": ["path"],
    "lic_package_name": ["license_package_name"],
    "lk_conditions": ["license_kind_conditions"],
    "lk_url": ["license_kind_url"],
    "cipd_src": ["cipd_srcs"],
    "static_deps": ["static_libs", "crt_libs"],
}

# 2. Columns to skip during field-by-field comparison
EXCLUDED_COLUMNS = [
    "id",
    "prebuilt_src_file",
    "is_static_lib",
    "built_files",
    "static_deps",
    "static_dep_files",
    "is_primary_arch",
    "base_module_type",
    "lic_license_kinds",
    "lic_license_text",
    "installed_files",
    "header_libs",
    "module_type",
    "licenses",
    "whole_static_dep_files"
]

# 3. Module types to skip using Regular Expressions
EXCLUDED_MODULE_TYPE_RE = [
    r"android_app_import",
    r"package",
    r"prebuilt_etc",
    r"cc_prebuilt_library_shared",
    r"cipd_package",
    r"filegroup",
    r"prebuilt_firmware",
    r"genrule",
    r"carrier_settings_prebuilt_etc",
    r".*__bottomUpMutatorModule$"
]

# Pre-compile regex patterns for performance
RE_PATTERNS = [re.compile(p) for p in EXCLUDED_MODULE_TYPE_RE]

class Logger:
    """Helper class to write output to both console (with color) and a log file."""
    def __init__(self, filename):
        self.terminal = sys.stdout
        self.log = open(filename, "w")
        # Regex to strip ANSI color codes for plain text file writing
        self.ansi_escape = re.compile(r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])')

    def write(self, message):
        self.terminal.write(message)
        # Remove color codes before writing to the text file to avoid garbage characters
        clean_message = self.ansi_escape.sub('', message)
        self.log.write(clean_message)

    def flush(self):
        self.terminal.flush()
        self.log.flush()

def normalize_value(val):
    """Standardize scalar values for comparison (Booleans, NULLs, Strings)."""
    if val is None or val == "" or str(val).lower() == "none":
        return ""
    s_val = str(val).strip().lower()
    if s_val in ["1", "true"]: return "true"
    if s_val in ["0", "false"]: return "false"
    return s_val

def is_equal(db_val, json_val):
    """
    Comparison logic for List vs String with normalization and deduplication.
    Splits DB string by whitespace or commas to match JSON array structures.
    """
    if isinstance(json_val, list):
        # Support splitting DB string by spaces OR commas (e.g., 'A B' or 'A,B')
        db_list = re.split(r'[,\s]+', str(db_val)) if db_val else []
        norm_db_list = sorted(list(set([normalize_value(x) for x in db_list if x])))
        norm_json_list = sorted(list(set([normalize_value(x) for x in json_val if x])))
        return norm_db_list == norm_json_list
    return normalize_value(db_val) == normalize_value(json_val)

def should_skip_type(module_type):
    """Check if the module_type matches any exclusion regex patterns."""
    if not module_type:
        return False
    return any(pattern.match(module_type) for pattern in RE_PATTERNS)

def diff_data(db_rows, json_list, missing_log_file):
    """Core diff logic with composite key and comprehensive statistics."""
    # Index JSON data by composite key: name + path + variant
    json_map = {}
    for item in json_list:
        name = item.get('name')
        path = item.get('path', '')
        variant = item.get('variant', '')
        if name:
            key = f"{name}:{path}:{variant}"
            json_map[key] = item

    total_db_count = len(db_rows)
    processed_count = 0
    diff_count = 0
    missing_in_json = 0
    skipped_by_type = 0
    missing_keys = []

    print("-" * 60)
    print(f"Comparison Config: Key=name:package:variant")
    print(f"Initial DB Records: {total_db_count}")
    print("-" * 60)

    for db_row in db_rows:
        module_name = db_row.get('name')
        module_package = db_row.get('package', '')
        module_variant = db_row.get('variant', '')
        module_type = db_row.get('module_type')

        if not module_name:
            continue

        if should_skip_type(module_type):
            skipped_by_type += 1
            continue

        processed_count += 1
        lookup_key = f"{module_name}:{module_package}:{module_variant}"
        json_item = json_map.get(lookup_key)

        if not json_item:
            missing_in_json += 1
            missing_keys.append(f"{lookup_key} (Type: {module_type})")
            continue

        row_diffs = []
        for db_key, db_val in db_row.items():
            if db_key in EXCLUDED_COLUMNS:
                continue

            # Multi-mapping Logic: Fetch all mapped JSON keys and merge them
            json_keys = COLUMN_MAPPING.get(db_key, [db_key])
            combined_json_val = []

            for jk in json_keys:
                val = json_item.get(jk)
                if val:
                    if isinstance(val, list):
                        combined_json_val.extend(val)
                    else:
                        combined_json_val.append(val)

            display_json_key = " + ".join(json_keys)

            # Determine if we should compare as a list or a scalar
            is_json_list = len(json_keys) > 1 or (
                len(json_keys) == 1 and isinstance(json_item.get(json_keys[0]), list)
            )

            compare_json = combined_json_val if is_json_list else (
                combined_json_val[0] if combined_json_val else ""
            )

            if not is_equal(db_val, compare_json):
                row_diffs.append(f"    Field [{db_key} -> {display_json_key}]: "
                                 f"DB='{db_val}', JSON={compare_json}")

        if row_diffs:
            # Highlight [Mismatch] in RED for terminal visibility
            print(f"{RED}[Mismatch]{RESET} Key: {lookup_key} (Type: {module_type})")
            for d in row_diffs:
                print(d)
            diff_count += 1

    # Log modules that exist in DB but are missing in JSON to a separate file
    with open(missing_log_file, "w") as f:
        f.write(f"Modules in DB but missing (Total: {missing_in_json})\n")
        f.write("-" * 60 + "\n")
        for key in missing_keys:
            f.write(key + "\n")

    print("-" * 60)
    print("Final Statistics:")
    print(f"- Total modules in Database:    {total_db_count}")
    print(f"- Modules skipped by Type RE:   {skipped_by_type}")
    print(f"- Net modules scanned (Scan):   {processed_count}")
    print("-" * 60)
    print(f"- Mismatched Modules Found:     {diff_count}")
    print(f"- Modules missing in ZIP/JSON:  {missing_in_json} -> (Logged to {missing_log_file})")
    print("-" * 60)

def main():
    product = os.environ.get("TARGET_PRODUCT", "generic")
    report_file = f"diff_report_{product}.txt"
    missing_file = f"missing_in_json_{product}.txt"

    sys.stdout = Logger(report_file)

    db_path = f"out/soong/compliance-metadata/{product}/compliance-metadata.db"
    zip_path = f"out/soong/soong_api/{product}/soong_api.zip"

    if not os.path.exists(db_path) or not os.path.exists(zip_path):
        print(f"[-] Error: Data files missing for {product}.")
        return

    # Load modules from the compliance SQLite database
    print(f"[+] Loading DB: {db_path}")
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    db_data = [dict(r) for r in conn.execute("SELECT * FROM modules").fetchall()]
    conn.close()

    # Load and combine all JSON metadata from the Soong API ZIP
    print(f"[+] Loading ZIP: {zip_path}")
    json_data = []
    with zipfile.ZipFile(zip_path, 'r') as z:
        for f_name in [n for n in z.namelist() if n.endswith('.json')]:
            with z.open(f_name) as f:
                d = json.load(f)
                if isinstance(d, list):
                    json_data.extend(d)
                else:
                    json_data.append(d)

    diff_data(db_data, json_data, missing_file)
    print(f"\n[+] Diff complete.")
    print(f"[+] Report: {report_file}")
    print(f"[+] Missing Modules Log: {missing_file}")

if __name__ == "__main__":
    main()
