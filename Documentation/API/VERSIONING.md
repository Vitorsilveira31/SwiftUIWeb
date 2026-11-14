# SwiftUIWeb public API and versioning

SwiftUIWeb follows semantic versioning for the library products listed in
`Package.swift`: a breaking source or ABI change increments the major version,
an additive source-compatible API increments the minor version, and a bug fix
increments the patch version. Release tags are plain `MAJOR.MINOR.PATCH`
versions with no `v` prefix (for example `0.1.9`); the package manifest intentionally does not duplicate a version string because
SwiftPM derives the version from the tag or revision selected by the consumer.

The checked-in [`public-api.json`](public-api.json) is the review baseline for
the public Swift surface. `make api-diff` extracts explicit `public`/`open`
declarations from every library target, includes their `@available` metadata,
and fails if the baseline changes. An intentional API change must update the
baseline in the same commit with:

```sh
make api-diff-update
make api-diff
```

Availability follows the package floor (`macOS 15`) unless a declaration has
an explicit `@available` annotation. New platform-specific APIs must carry an
annotation rather than lowering the package floor. Native Swift compilation and
Embedded compilation remain authoritative for type and binary compatibility;
this source contract exists to make accidental API drift visible before release.

The public target list is deliberately separate from examples, browser
fixtures, and test support. Those directories can evolve without becoming
consumer API, and their executables are not included in the API baseline.
