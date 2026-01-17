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

import argparse
import json
import os
import shutil
import ssl
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

# Utilize the SoongApiClient library for lifecycle management
from soong_api_client import SoongApiClient

EVANS_GITHUB_API = "https://api.github.com/repos/ktr0731/evans/releases/latest"

class SoongApiQuery:
    def __init__(self):
        # Environment detection is handled internally by SoongApiClient
        pass

    def _get_evans_path(self):
        """Finds evans in PATH, ~/bin, or downloads it."""
        if shutil.which("evans"):
            return "evans"
        home_bin = Path.home() / "bin"
        local_evans = home_bin / "evans"
        if local_evans.exists() and os.access(local_evans, os.X_OK):
            return str(local_evans)

        print("Dependency 'evans' (gRPC client) not found.")
        choice = input("Do you want to download the latest 'evans' to ~/bin? [y/N] ").lower()
        if choice != 'y':
            print("Aborted. 'evans' is required for this tool.")
            sys.exit(1)
        self._download_evans(home_bin)
        return str(local_evans)

    def _download_evans(self, install_dir):
        print("Fetching latest release info from GitHub...")
        ssl_ctx = ssl.create_default_context()
        ssl_ctx.check_hostname = False
        ssl_ctx.verify_mode = ssl.CERT_NONE
        try:
            with urllib.request.urlopen(EVANS_GITHUB_API, context=ssl_ctx) as resp:
                data = json.load(resp)

            import platform
            machine = platform.machine()
            arch_keyword = "amd64" if machine in ["x86_64", "amd64"] else "arm64"

            download_url = next((asset['browser_download_url'] for asset in data['assets']
                               if "linux" in asset['name'].lower() and arch_keyword in asset['name'].lower()
                               and "tar.gz" in asset['name'].lower()), None)

            if not download_url:
                print(f"Error: Could not find a suitable binary for Linux {machine}")
                sys.exit(1)

            install_dir.mkdir(parents=True, exist_ok=True)
            print(f"Downloading {download_url}...")
            with tempfile.TemporaryDirectory() as temp_dir:
                tar_path = Path(temp_dir) / "evans.tar.gz"
                with urllib.request.urlopen(download_url, context=ssl_ctx) as response, open(tar_path, 'wb') as out_file:
                    shutil.copyfileobj(response, out_file)
                with tarfile.open(tar_path, "r:gz") as tar:
                    member = next(m for m in tar.getmembers() if m.name.endswith("evans"))
                    member.name = os.path.basename(member.name)
                    tar.extract(member, path=install_dir)

            target = install_dir / "evans"
            target.chmod(target.stat().st_mode | 0o111)
            print(f"Installed to {target}")
        except Exception as e:
            print(f"Error downloading evans: {e}")
            sys.exit(1)

    def run(self):
        parser = argparse.ArgumentParser(description="Soong API Query Tool")
        # This will automatically support both --interactive and --no-interactive
        parser.add_argument(
            "-i", "--interactive",
            action=argparse.BooleanOptionalAction,
            help="Start interactive Evans session (automatically enabled if no method is provided)"
        )
        # This will automatically support both --rebuild and --no-rebuild
        parser.add_argument(
            "--rebuild",
            action=argparse.BooleanOptionalAction,
            default=True,
            help="Rebuild soong_api.db to ensure data freshness"
        )
        parser.add_argument("method", nargs="?", help="Method to call (e.g., GetModule)")

        # Parse known args to separate method from dynamic flags
        args, unknown = parser.parse_known_args()
        evans_bin = self._get_evans_path()

        try:
            # Use SoongApiClient to manage the server lifecycle
            with SoongApiClient(rebuild=args.rebuild) as client:
                # Decide mode: use interactive if explicitly requested,
                # or if no method is provided and interactive wasn't explicitly disabled.
                is_interactive = args.interactive
                if is_interactive is None:
                    is_interactive = not args.method

                if is_interactive:
                    # Interactive Mode
                    print("Launching Evans interactive shell...")
                    subprocess.run([
                        evans_bin,
                        "--host", "localhost",
                        "--port", str(client.port),
                        "--reflection",
                        "repl"
                    ])
                else:
                    # One-shot Query Mode
                    # Parse unknown args (e.g. --name MyModule) into JSON dictionary
                    data = {}
                    i = 0
                    while i < len(unknown):
                        key = unknown[i]
                        if key.startswith("--"):
                            clean_key = key[2:]
                            if i + 1 < len(unknown) and not unknown[i+1].startswith("--"):
                                data[clean_key] = unknown[i+1]
                                i += 2
                            else:
                                data[clean_key] = True
                                i += 1
                        else:
                            i += 1

                    json_data = json.dumps(data)

                    # Replicated the successful manual command logic:
                    # echo 'JSON' | evans --host ... --reflection cli call <method>
                    cmd = [
                        evans_bin,
                        "--host", "localhost",
                        "--port", str(client.port),
                        "--reflection",
                        "cli",
                        "call",
                        args.method
                    ]

                    # Feed the JSON data via standard input (input=json_data)
                    subprocess.run(cmd, input=json_data, text=True)

        except KeyboardInterrupt:
            print("\nInterrupted.")
        except Exception as e:
            print(f"Fatal Error: {e}")
            sys.exit(1)

if __name__ == "__main__":
    tool = SoongApiQuery()
    tool.run()
