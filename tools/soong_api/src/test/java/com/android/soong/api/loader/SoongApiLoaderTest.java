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

package com.android.soong.api.loader;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Before;
import org.junit.Rule;
import org.junit.Test;
import org.junit.rules.TemporaryFolder;
import org.junit.runner.RunWith;
import org.junit.runners.JUnit4;

import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

/**
 * Tests for {@link SoongApiLoader}.
 */
@RunWith(JUnit4.class)
public class SoongApiLoaderTest {

    @Rule
    public TemporaryFolder tempFolder = new TemporaryFolder();

    private File outputDb;
    private SoongApiLoader loader;

    // Mock JSON content using snake_case as expected from Soong.
    private final String jsonContent = "[\n" +
            "  {\n" +
            "    \"name\": \"moduleA\", \n" +
            "    \"type\": \"java_library\", \n" +
            "    \"path\": \"frameworks/base\", \n" +
            "    \"install_files\": [\"/system/lib/a.jar\"]\n" +
            "  },\n" +
            "  {\n" +
            "    \"name\": \"moduleB\", \n" +
            "    \"type\": \"cc_binary\", \n" +
            "    \"path\": \"system/core\", \n" +
            "    \"install_files\": []\n" +
            "  }\n" +
            "]";

    @Before
    public void setUp() throws Exception {
        loader = new SoongApiLoader();
        outputDb = tempFolder.newFile("test_soong_api.db");
    }

    @Test
    public void testLoad_fromZip_convertsJsonToSqlite() throws Exception {
        // 1. Arrange: Create a mock soong_api.zip
        File inputZip = tempFolder.newFile("soong_api.zip");
        createMockZipFile(inputZip, jsonContent);

        // 2. Act: Run the Loader to ingest data into SQLite
        loader.load(inputZip, outputDb);

        // 3. Assert: Verify the database structure and content
        assertDbContent();
    }

    @Test
    public void testLoad_fromJson_convertsJsonToSqlite() throws Exception {
        // 1. Arrange: Create a mock soong_api.json
        File inputJson = tempFolder.newFile("soong_api.json");
        createMockJsonFile(inputJson, jsonContent);

        // 2. Act: Run the Loader to ingest data into SQLite
        loader.load(inputJson, outputDb);

        // 3. Assert: Verify the database structure and content
        assertDbContent();
    }

    private void createMockZipFile(File zipFile, String content) throws Exception {
        try (FileOutputStream fos = new FileOutputStream(zipFile);
             ZipOutputStream zos = new ZipOutputStream(fos)) {

            ZipEntry entry = new ZipEntry("soong_api.json");
            zos.putNextEntry(entry);
            zos.write(content.getBytes(StandardCharsets.UTF_8));
            zos.closeEntry();
        }
    }

    private void createMockJsonFile(File jsonFile, String content) throws Exception {
        try (FileWriter writer = new FileWriter(jsonFile, StandardCharsets.UTF_8)) {
            writer.write(content);
        }
    }

    /**
     * Helper method to assert the correctness of the generated database.
     */
    private void assertDbContent() throws Exception {
        assertTrue("Output DB should exist", outputDb.exists());

        String url = "jdbc:sqlite:" + outputDb.getAbsolutePath();
        try (Connection conn = DriverManager.getConnection(url);
             Statement stmt = conn.createStatement()) {

            // Verify total module count
            ResultSet rs = stmt.executeQuery("SELECT count(*) FROM modules");
            assertTrue("Result set should have a row", rs.next());
            assertEquals("Should have 2 modules", 2, rs.getInt(1));

            // Verify specific data for moduleA
            rs = stmt.executeQuery("SELECT metadata FROM modules WHERE name = 'moduleA'");
            assertTrue("moduleA should exist", rs.next());
            String jsonA = rs.getString("metadata");

            // Verify content
            assertTrue("JSON should contain type", jsonA.contains("\"type\":\"java_library\""));
            assertTrue("JSON should contain install path", jsonA.contains("/system/lib/a.jar"));

            // Verify fix for field naming: must be snake_case to support SQL JSON queries.
            assertTrue("JSON must use snake_case 'install_files'",
                       jsonA.contains("\"install_files\""));
            assertFalse("JSON must NOT use camelCase 'installFiles'",
                        jsonA.contains("\"installFiles\""));
        }
    }
}
