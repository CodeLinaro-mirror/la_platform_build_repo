#!/usr/bin/env python3
#
# Copyright (C) 2025 The Android Open Source Project
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

import grpc
import os
import platform
import socket
import subprocess
import sys
import time
from pathlib import Path

# Import generated protobuf code
# These come from the genrule :soong_api_python_protoc_gen
import soong_api_pb2
import soong_api_pb2_grpc

class SoongApiClient:
    """
    A Python Client for the Soong API gRPC Service.

    This client handles the lifecycle of the local gRPC server automatically.
    On initialization, it checks for the existence of soong_api.db. If missing,
    it triggers a build using the Android build system. It then starts a local
    soong_api_server instance on a free ephemeral port and establishes a channel.
    """

    SOONG_UI_BASH_REL = "build/soong/soong_ui.bash"
    DEFAULT_OUT_DIR = "out"
    DEFAULT_HOST_OUT_REL = "out/host/linux-x86"

    def __init__(self):
        self._check_os()
        self.android_top = self._find_android_top()
        self.soong_ui = self.android_top / self.SOONG_UI_BASH_REL
        self.server_path = self._resolve_server_path()
        self.db_path = self._resolve_db_path()
        self.server_process = None
        self.channel = None
        self.stub = None

        self._ensure_build_artifacts()
        self._start_server()

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.close()

    def close(self):
        if self.channel:
            self.channel.close()

        if self.server_process:
            print("Shutting down soong_api_server...")
            self.server_process.terminate()
            try:
                self.server_process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                self.server_process.kill()

    # --- Public API Methods ---

    def GetAllModules(self):
        """Returns an iterator of all modules defined in the build system."""
        request = soong_api_pb2.GetAllModulesRequest()
        return self.stub.GetAllModules(request)

    def GetModule(self, name):
        """
        Convenience method to get modules by name.
        Args:
            name (str): The name of the module (e.g., "libc").
        Returns:
            iterator: A stream of Module messages.
        """
        request = soong_api_pb2.GetModuleRequest(name=name)
        return self.stub.GetModule(request)

    def GetModuleByInstallPath(self, install_path):
        """
        Convenience method to get modules by install path.
        Args:
            install_path (str): The absolute installation path.
        Returns:
            iterator: A stream of Module messages.
        """
        request = soong_api_pb2.GetModuleByInstallPathRequest(install_path=install_path)
        return self.stub.GetModuleByInstallPath(request)

    # --- Internal Methods ---

    def _check_os(self):
        if platform.system() != 'Linux':
            raise OSError("SoongApiClient currently supports Linux only.")

    def _find_android_top(self):
        env_top = os.environ.get('ANDROID_BUILD_TOP')
        if env_top:
            return Path(env_top)

        # Fallback: Check CWD
        cwd = Path.cwd()
        if (cwd / self.SOONG_UI_BASH_REL).exists():
            return cwd

        raise FileNotFoundError(
            "Could not locate Android Root. Please set ANDROID_BUILD_TOP "
            "or run from the root of the source tree."
        )

    def _resolve_server_path(self):
        # Use ANDROID_HOST_OUT if available (e.g. out/host/linux-x86)
        host_out = os.environ.get('ANDROID_HOST_OUT')
        if host_out:
            return Path(host_out) / "bin/soong_api_server"

        return self.android_top / self.DEFAULT_HOST_OUT_REL / "bin/soong_api_server"

    def _resolve_db_path(self):
        # Use OUT_DIR if available, otherwise default to "out"
        out_dir = os.environ.get('OUT_DIR', self.DEFAULT_OUT_DIR)
        out_path = Path(out_dir)

        # Handle relative OUT_DIR (relative to top)
        if not out_path.is_absolute():
            out_path = self.android_top / out_path

        return out_path / "soong/soong_api/soong_api.db"

    def _ensure_build_artifacts(self):
        if self.server_path.exists() and self.db_path.exists():
            return

        print("Soong API artifacts missing. Attempting to build...")

        if not os.environ.get('TARGET_PRODUCT'):
             raise EnvironmentError("Build environment not set. Please run 'lunch' first.")

        cmd = [str(self.soong_ui), "--make-mode", "soong_api.db", "soong_api_server"]

        try:
            # Redirect output to inherit to show build progress
            subprocess.check_call(cmd, cwd=self.android_top)
            print("Build successful.")
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"Build failed with exit code: {e.returncode}") from e

    def _find_free_port(self):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(('localhost', 0))
            return s.getsockname()[1]

    def _wait_for_server_start(self, port):
        start = time.time()
        timeout = 5.0 # seconds

        while time.time() - start < timeout:
            if self.server_process.poll() is not None:
                raise RuntimeError("Server process died unexpectedly during startup.")

            try:
                with socket.create_connection(("localhost", port), timeout=0.1):
                    return # Connection successful
            except (ConnectionRefusedError, OSError):
                time.sleep(0.05) # Wait 50ms before retrying

        raise TimeoutError(f"Timed out waiting for server to start on port {port}")

    def _start_server(self):
        port = self._find_free_port()
        print(f"Starting soong_api_server on port {port}...")

        cmd = [
            str(self.server_path),
            "--db_path", str(self.db_path),
            "--port", str(port)
        ]

        # Suppress stdout/stderr to keep console clean, or inherit for debugging
        self.server_process = subprocess.Popen(
            cmd,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.STDOUT
        )

        self._wait_for_server_start(port)
        print("Server started.")

        self._create_channel(port)

    def _create_channel(self, port):
        self.channel = grpc.insecure_channel(f'localhost:{port}')
        self.stub = soong_api_pb2_grpc.SoongApiServiceStub(self.channel)
