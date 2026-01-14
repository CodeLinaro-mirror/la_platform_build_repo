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

//! `finalize-non-api-flags` is a tool to create a snapshot of exception (that
//! is, exported non-API) flags that have "made it" to a given release. Since they're
//! used cross-binary, this binary supports automatically adding an SDK level
//! check so the flags are resilient to deletion. This means that once this
//! binary is run, the flags have passed a "point of no return" where they
//! cannot be rolled back.
use anyhow::Result;
use clap::Parser;
use std::{fs::File, path::PathBuf};

mod exception_flags;

pub(crate) type FlagId = String;

const ABOUT: &str = "Creates a temp file of 'finalized' exported non-API flags.

Ensures exported flags which don't guard APIs still get the generated SDK level
check so they can be safely cleaned up.

**Only flags on the exception list will be included. If an exported flag is not
on that list OR used to guard an API, it will not get the SDK level check, even if it's included in a
major platform release.**

This tool:

  - Reads the exception list from the source tree [--exception-list]
  - Reads the state of the current flags from release configs [--flag-sources]
  - Filters the exception list to only include flags that are present in the
    release configs, recording the earliest relese config that has each flag
  - Prints the map of <flags, release config> to stdout
";

#[derive(Parser, Debug)]
#[clap(about=ABOUT)]
struct Cli {
    #[arg(long)]
    exception_list: PathBuf,

    #[arg(long)]
    flag_sources: PathBuf,
}

fn main() -> Result<()> {
    let args = Cli::parse();

    let file = File::open(args.exception_list)?;
    let _all_exception_flags = exception_flags::read_exception_flags(file)?;

    // TODO(b/467323313): Load all aconfig flags from the cache, filter to the
    // flags on the exception list, filter to flags in a non-trunk release
    // config, and generate the finalized flags map.
    Ok(())
}
