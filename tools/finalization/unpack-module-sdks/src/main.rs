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

//! `unpack-module-sdks` is a tool to copy selected parts of the artifacts from
//! mainline_modules_sdks.sh to prebuilts/sdk and prebuilts/module_sdk/$module as part of
//! finalizing a new SDK extension version

// TODO(b/481981256): refactor code to more readable

use anyhow::{Context, Result};
use clap::Parser;
use std::path::PathBuf;

mod module_sdks;

const ABOUT: &str = "Tool to extract some of the artifacts of mainline_modules_sdks.sh into prebuilts/sdk and prebuilts/module_sdks/$module.";

#[derive(Parser, Debug)]
#[clap(about=ABOUT)]
struct Cli {
    #[arg(long)]
    mainline_sdks_top: PathBuf,

    #[arg(long)]
    android_top: PathBuf,

    #[arg(long)]
    sdk_ext_version: usize,
}

fn main() -> Result<()> {
    let args = Cli::parse();

    let mut modified_projects: Vec<_> = module_sdks::populate_prebuilts(
        &args.mainline_sdks_top,
        &args.android_top,
        args.sdk_ext_version,
    )
    .with_context(|| {
        format!(
            "unpacking mainline sdks from directory {} to Android tree at {} with SDK extension version {}",
            args.mainline_sdks_top.display(),
            args.android_top.display(),
            args.sdk_ext_version
        )
    })?.into_iter().collect();
    modified_projects.sort_unstable();
    modified_projects.into_iter().for_each(|path| println!("{}", path.display()));

    Ok(())
}
