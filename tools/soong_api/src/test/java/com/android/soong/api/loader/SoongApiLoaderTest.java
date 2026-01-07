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

    // Mock two JSON records
    private final String jsonContent = "[\n" +
            "  {\"name\": \"moduleA\", \"type\": \"java_library\", \"install_files\": [\"/system/lib/a.jar\"]},\n" +
            "  {\"name\": \"moduleB\", \"type\": \"cc_binary\", \"install_files\": []}\n" +
            "]";

    @Before
    public void setUp() throws Exception {
        loader = new SoongApiLoader();
        outputDb = tempFolder.newFile("test_soong_api.db");
    }

    @Test
    public void testLoad_fromZip_convertsJsonToSqlite() throws Exception {
        // 1. Arrange: Create a mock metadata.zip (Soong typically produces this)
        File inputZip = tempFolder.newFile("soong_metadata.zip");
        createMockZipFile(inputZip, jsonContent);

        // 2. Act: Run the Loader
        loader.load(inputZip, outputDb);

        // 3. Assert: Verify DB content
        assertDbContent();
    }

    @Test
    public void testLoad_fromJson_convertsJsonToSqlite() throws Exception {
        // 1. Arrange: Create a mock metadata.json
        File inputJson = tempFolder.newFile("metadata.json");
        createMockJsonFile(inputJson, jsonContent);

        // 2. Act: Run the Loader
        loader.load(inputJson, outputDb);

        // 3. Assert: Verify DB content
        assertDbContent();
    }

    private void createMockZipFile(File zipFile, String content) throws Exception {
        try (FileOutputStream fos = new FileOutputStream(zipFile);
             ZipOutputStream zos = new ZipOutputStream(fos)) {

            ZipEntry entry = new ZipEntry("metadata.json");
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

    private void assertDbContent() throws Exception {
        assertTrue("Output DB should exist", outputDb.exists());

        try (Connection conn = DriverManager.getConnection("jdbc:sqlite:" + outputDb.getAbsolutePath());
             Statement stmt = conn.createStatement()) {

            // Verify total count
            ResultSet rs = stmt.executeQuery("SELECT count(*) FROM modules");
            assertTrue("Result set should have a row", rs.next());
            int count = rs.getInt(1);
            assertEquals("Should have 2 modules", 2, count);

            // Verify specific data for moduleA
            rs = stmt.executeQuery("SELECT metadata FROM modules WHERE name = 'moduleA'");
            assertTrue("moduleA should exist", rs.next());
            String jsonA = rs.getString("metadata");
            // Note: JsonFormat.printer() might change whitespace, but "contains" is safe.
            assertTrue("JSON A should contain type", jsonA.contains("\"type\":\"java_library\""));
            assertTrue("JSON A should contain install path", jsonA.contains("/system/lib/a.jar"));

            // Verify specific data for moduleB
            rs = stmt.executeQuery("SELECT metadata FROM modules WHERE name = 'moduleB'");
            assertTrue("moduleB should exist", rs.next());
            String jsonB = rs.getString("metadata");
            assertTrue("JSON B should contain type", jsonB.contains("\"type\":\"cc_binary\""));
        }
    }
}
