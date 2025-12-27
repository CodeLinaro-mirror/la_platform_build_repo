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

package com.android.metadata.loader;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import com.google.gson.stream.JsonReader;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.sql.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public class MetadataLoader {

    /**
     * Executes the conversion logic: reads the input file and populates the SQLite database.
     *
     * @param inputFile The input metadata.zip or metadata.json file.
     * @param outputDb The output SQLite DB file.
     */
    public void load(File inputFile, File outputDb) throws IOException, SQLException {
        if (!inputFile.exists()) {
            throw new FileNotFoundException("Input file not found: " + inputFile.getAbsolutePath());
        }

        // Establish JDBC connection
        String url = "jdbc:sqlite:" + outputDb.getAbsolutePath();
        try (Connection conn = DriverManager.getConnection(url)) {
            conn.setAutoCommit(false); // Enable transaction for performance

            // Initialize Schema
            initializeDb(conn);

            String inputFileName = inputFile.getName();
            if (inputFileName.endsWith(".zip")) {
                processZip(conn, inputFile);
            } else if (inputFileName.endsWith(".json")) {
                processJson(conn, inputFile);
            } else {
                throw new IllegalArgumentException("Input file must be a .zip or .json file: " + inputFileName);
            }

            conn.commit();
        }
    }

    private void initializeDb(Connection conn) throws SQLException {
        try (Statement stmt = conn.createStatement()) {
            stmt.execute("DROP TABLE IF EXISTS modules");
            stmt.execute("CREATE TABLE modules (name TEXT, metadata TEXT)");
            stmt.execute("CREATE INDEX idx_name ON modules(name)");
        }
    }

    private void processZip(Connection conn, File inputZip) throws IOException, SQLException {
        try (ZipFile zf = new ZipFile(inputZip)) {
            ZipEntry entry = zf.getEntry("metadata.json");
            if (entry == null) {
                throw new IOException("metadata.json not found in " + inputZip.getName());
            }

            try (InputStream is = zf.getInputStream(entry);
                 InputStreamReader isr = new InputStreamReader(is, StandardCharsets.UTF_8)) {
                parseAndInsertMetadata(conn, isr);
            }
        }
    }

    private void processJson(Connection conn, File inputJson) throws IOException, SQLException {
        try (FileInputStream fis = new FileInputStream(inputJson);
             InputStreamReader isr = new InputStreamReader(fis, StandardCharsets.UTF_8)) {
            parseAndInsertMetadata(conn, isr);
        }
    }

    private void parseAndInsertMetadata(Connection conn, InputStreamReader isr) throws IOException, SQLException {
        Gson gson = new Gson();
        String sql = "INSERT INTO modules (name, metadata) VALUES (?, ?)";

        try (JsonReader reader = new JsonReader(isr);
             PreparedStatement pstmt = conn.prepareStatement(sql)) {

            reader.beginArray(); // Start reading the JSON array [

            while (reader.hasNext()) {
                // Stream reading: Read only one Module object into memory at a time.
                JsonObject module = gson.fromJson(reader, JsonObject.class);

                String name = module.has("name") ? module.get("name").getAsString() : "unknown";
                String jsonStr = gson.toJson(module);

                pstmt.setString(1, name);
                pstmt.setString(2, jsonStr);
                pstmt.addBatch();
            }

            reader.endArray(); // End reading the JSON array ]
            pstmt.executeBatch();
        }
    }
}

