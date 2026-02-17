/*
 * Copyright (C) 2026 The Android Open Source Project
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

use anyhow::{bail, Context, Result};
use glob::glob;
use regex::Regex;
use serde::Deserialize;
use std::{
    collections::{HashMap, HashSet},
    ffi::OsStr,
    fs,
    io::{self, Read},
    path::{Component, Path, PathBuf},
};

#[derive(Debug, Deserialize)]
struct ModuleInfo {
    #[serde(skip_deserializing)]
    package_name: String,
    module_sdk_project: String,
}

fn parse_mainline_module_info_json<R: Read>(json: R) -> Result<Vec<ModuleInfo>> {
    let map: HashMap<String, ModuleInfo> =
        serde_json::from_reader(json).context("deserialize json")?;
    let list: Vec<_> = map
        .into_iter()
        .map(|(key, mut value)| {
            value.package_name = key;
            value
        })
        .collect();
    Ok(list)
}

fn is_ignored(filename: &str) -> bool {
    // conscrypt has some legacy API tracking files that we don't consider for extensions
    ["conscrypt.module.intra.core.api", "conscrypt.module.platform.api"]
        .iter()
        .any(|prefix| filename.starts_with(prefix))
}

fn tweak_filename(filename: &str) -> String {
    // for legacy reasons, art and conscrypt file names in the SDKs
    // (*.module.public.api) do not match their expected filename in prebuilts/sdk
    // (art, conscrypt), so rename them
    //
    // the stub jar artifacts from official builds are named '*-stubs.jar', but the
    // convention for the copies in prebuilts/sdk is just '*.jar', so fix that
    filename
        .replace("art.module.public.api", "art")
        .replace("conscrypt.module.public.api", "conscrypt")
        .replace("-stubs", "")
}

pub fn populate_prebuilts<P: AsRef<Path>>(
    mainline_sdks_top: P,
    android_top: P,
    new_version: usize,
) -> Result<HashSet<PathBuf>> {
    let json_path = mainline_sdks_top.as_ref().join("mainline-modules-info.json");
    let json_file =
        std::fs::File::open(&json_path).with_context(|| format!("open {}", json_path.display()))?;
    let module_infos = parse_mainline_module_info_json(json_file)
        .with_context(|| format!("parse {}", json_path.display()))?;

    let regex = Regex::new(r"sdk_library/(.*?)/(.*?\.(?:txt|jar))").unwrap();
    let mut modified_projects = HashSet::from([PathBuf::from("prebuilts/sdk")]);
    'outer: for zip_path in glob(&format!(
        "{}/mainline-sdks/for-next-build/current/*/sdk/*.zip",
        mainline_sdks_top.as_ref().display()
    ))? {
        let zip_path = zip_path.context("glob")?;
        for module in &module_infos {
            if zip_path
                .components()
                .any(|part| part == Component::Normal(OsStr::new(&module.package_name)))
            {
                // record this project as modified for caller to create git commit
                modified_projects.insert(PathBuf::from(&module.module_sdk_project));

                // populate prebuilts/modules/$module/$new_version: extract entire zip
                let dest_dir = android_top
                    .as_ref()
                    .join(&module.module_sdk_project)
                    .join(new_version.to_string());
                fs::create_dir_all(&dest_dir)
                    .with_context(|| format!("create dir {}", dest_dir.display()))?;

                let zip_file = fs::File::open(&zip_path)
                    .with_context(|| format!("open {}", zip_path.display()))?;
                let mut zip_archive = zip::ZipArchive::new(&zip_file)
                    .with_context(|| format!("open zip archive {}", zip_path.display()))?;
                zip_archive.extract(&dest_dir).with_context(|| {
                    format!("extract entire zip archive {}", zip_path.display())
                })?;

                let old_android_bp = dest_dir.join("Android.bp");
                let new_android_bp = dest_dir.join("Android.bp.auto");
                fs::rename(&old_android_bp, &new_android_bp).with_context(|| {
                    format!("rename {} -> {}", old_android_bp.display(), new_android_bp.display())
                })?;

                // populate prebuilts/sdk/extensions/$new_version: extract sdk_library/*/*.{txt,jar} files
                let dest_dir_root = android_top
                    .as_ref()
                    .join("prebuilts")
                    .join("sdk")
                    .join("extensions")
                    .join(new_version.to_string());
                let zip_entries: Vec<String> =
                    zip_archive.file_names().map(|s| s.to_string()).collect();
                for caps in zip_entries.iter().filter_map(|entry| regex.captures(entry)) {
                    let entry_path = &caps[0];
                    let api_type = &caps[1];
                    let entry_filename = &caps[2];
                    if is_ignored(entry_filename) {
                        continue;
                    }
                    let mut dest_dir = dest_dir_root.join(api_type);
                    if entry_filename.ends_with(".txt") {
                        dest_dir.push("api");
                    }
                    fs::create_dir_all(&dest_dir)
                        .with_context(|| format!("create dir {}", dest_dir.display()))?;
                    let mut zip_entry = zip_archive.by_name(entry_path).with_context(|| {
                        format!("opening entry {entry_path} in zip archive {}", zip_path.display())
                    })?;
                    let tweaked_entry_filename = tweak_filename(entry_filename);
                    let dest_path = dest_dir.join(&tweaked_entry_filename);
                    let mut dest_file = fs::File::create(&dest_path)
                        .with_context(|| format!("create {}", dest_dir.display()))?;
                    io::copy(&mut zip_entry, &mut dest_file).with_context(|| {
                        format!(
                            "extract entry {entry_path} from zip archive {} to {}",
                            zip_path.display(),
                            dest_path.display()
                        )
                    })?;
                }

                continue 'outer;
            }
        }
        bail!("failed to find ModuleInfo for {}", zip_path.display());
    }

    Ok(modified_projects)
}
