# Permissions Versioning Tool

This custom build tool generates the `permission-versions.xml` file, which houses SDK versioning
metadata specifically for platform-defined permissions that require a purpose declaration.

The resulting XML file is bundled within the SDK zip package. Its primary function is to power
development tooling features, such as lint rules and auto-complete, associated with the Permissions
Purpose Declaration (PPD) feature.

For more information about the tool and its implementation details, please refer to go/pd-devx-eng.

TODO(b/454109900): Provide more details including the current capabilities, limitations, examples,
planned future work etc.
