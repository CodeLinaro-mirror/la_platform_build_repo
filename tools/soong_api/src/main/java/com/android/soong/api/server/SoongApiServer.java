/*
 * Copyright (C) 2025 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.android.soong.api.server;

import com.android.soong.api.db.SoongApiDao;
import io.grpc.protobuf.services.ProtoReflectionService;
import io.grpc.Server;
import io.grpc.ServerBuilder;

import java.io.File;
import java.io.IOException;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import java.util.concurrent.TimeUnit;

/**
 * Main entry point for the Soong API Server (SNAPI).
 * <p>
 * Usage: {@code soong_api_server --db_path <path> [--port <port>]}
 */
public class SoongApiServer {
    private Server server;
    private Connection connection;

    private void start(int port, String dbPath) throws IOException, SQLException {
        // 1. Initialize DB Connection
        String url = "jdbc:sqlite:" + dbPath;
        connection = DriverManager.getConnection(url);
        System.out.println("Connected to Soong API database: " + dbPath);

        // 2. Initialize DAO and Service
        SoongApiDao dao = new SoongApiDao(connection);
        SoongApiServiceImpl service = new SoongApiServiceImpl(dao);

        // 3. Build and Start gRPC Server
        server = ServerBuilder.forPort(port)
                .addService(service)
                .addService(ProtoReflectionService.newInstance())
                .build()
                .start();

        System.out.println("Soong API Server started, listening on " + port);

        // 4. Add Shutdown Hook for graceful termination
        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            System.err.println("*** shutting down SNAPI server since JVM is shutting down");
            try {
                SoongApiServer.this.stop();
            } catch (InterruptedException e) {
                e.printStackTrace(System.err);
            }
            System.err.println("*** SNAPI server shut down");
        }));
    }

    private void stop() throws InterruptedException {
        if (server != null) {
            server.shutdown().awaitTermination(30, TimeUnit.SECONDS);
        }
        if (connection != null) {
            try {
                connection.close();
                System.out.println("Database connection closed.");
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    private void blockUntilShutdown() throws InterruptedException {
        if (server != null) {
            server.awaitTermination();
        }
    }

    public static void main(String[] args) throws IOException, InterruptedException, SQLException {
        int port = 50051; // Default port
        String dbPath = null;

        for (int i = 0; i < args.length; i++) {
            if ("--db_path".equals(args[i]) && i + 1 < args.length) {
                dbPath = args[i + 1];
                i++;
            } else if ("--port".equals(args[i]) && i + 1 < args.length) {
                port = Integer.parseInt(args[i + 1]);
                i++;
            }
        }

        if (dbPath == null) {
            System.err.println("Usage: soong_api_server --db_path <metadata.db> [--port <port>]");
            System.exit(1);
        }

        if (!new File(dbPath).exists()) {
            System.err.println("Error: Database file not found: " + dbPath);
            System.exit(1);
        }

        final SoongApiServer server = new SoongApiServer();
        try {
            server.start(port, dbPath);
            server.blockUntilShutdown();
        } catch (Exception e) {
            System.err.println("SNAPI Server failed to start: " + e.getMessage());
            e.printStackTrace();
            System.exit(1);
        }
    }
}
