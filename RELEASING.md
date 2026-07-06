# Releasing

How to cut a versioned release of `platform-swift` and how downstream projects consume it.

## The model: a release is a git tag

Swift Package Manager has no registry or upload step. **Publishing a version means creating a SemVer git tag.** SPM resolves consumers' `from:` / `exact:` / `.upToNextMinor(from:)` requirements against **git tags**, entirely independently of GitHub Releases. The GitHub Release is the human-facing wrapper — it carries the release notes and is the ritual we use to create the tag, but SPM never looks at it.

Two consequences worth internalizing:

- **All 37 products version together.** One tag = one version for the whole package. SPM cannot version products independently within a single package, so a bump to any product is a bump to all of them.
- **The tag is live the instant you publish.** Because SPM consumes tags, a tag becomes resolvable by downstream projects the moment the Release is published — before CI has validated it. So only ever cut a release from an already-green `main` (see below), and never move or re-point an existing tag.

## Versioning policy

- **SemVer**, bare `X.Y.Z` tags — **no `v` prefix** (matches this repo's README and Apple's own packages; SPM accepts either form, but we standardize on bare so pins are consistent). The `release` workflow rejects any tag that isn't bare SemVer.
- **Pre-1.0 (`0.x`) semantics — important for consumers.** While the package is on `0.x`, SemVer (and therefore SPM's `from:`) treats the **minor** as the breaking bump:
  - `from: "0.1.0"` resolves `0.1.0 ..< 0.2.0` **only** — it does *not* range up to `1.0`.
  - So: bump the **minor** (`0.1.0` → `0.2.0`) for any breaking change, and the **patch** (`0.1.0` → `0.1.1`) for backward-compatible changes, until we deliberately commit to `1.0.0`.

## Cutting a release

1. **Confirm `main` is green.** PR CI (`build` / `lint`) already gates every merge, so a merged `main` commit is validated. Release only from such a commit — the tag goes live before the release workflow re-checks it.
2. On GitHub: **Releases ▸ Draft a new release**.
3. **Choose a tag ▸** type the new version (e.g. `0.2.0`) ▸ **Create new tag: `0.2.0` on publish**, with **Target: `main`** (or the exact commit you're releasing).
4. Click **Generate release notes** — GitHub summarizes the merged PRs and commits since the previous tag (this is why `feat:` / `fix:` / `docs():` commit prefixes are worth keeping).
5. **Publish release.** The `release` workflow then checks out the tagged commit and runs `make build` / `make test` / `make build-ios`. On success the release stands as the validated artifact; on failure it is automatically **retracted to a draft** (the git tag still exists — see yanking).

## Yanking a bad release

If a bad tag ships (validation failed, or a defect is found after release):

1. Delete the GitHub Release (or leave the auto-retracted draft).
2. **Delete the git tag** — this is the part that actually matters, since SPM resolves tags:
   ```bash
   git push --delete origin 0.2.0
   git tag -d 0.2.0            # local
   ```
3. Cut the next **patch** (`0.2.1`) with the fix. **Never** move or re-point an existing tag — a consumer may have already resolved and cached it, and reusing a tag for different content breaks reproducibility.

## Consuming a release (downstream)

Add the package once, then depend on just the products you need. Three ways to pin:

```swift
dependencies: [
    // Recommended: patches + (pre-1.0) same-minor updates.
    .package(url: "https://github.com/primandproper/platform-swift.git", from: "0.1.0"),

    // Safest while pre-1.0 — explicitly cap at the next minor:
    // .package(url: "https://github.com/primandproper/platform-swift.git", .upToNextMinor(from: "0.1.0")),

    // Fully pinned (reproducible, no auto-updates):
    // .package(url: "https://github.com/primandproper/platform-swift.git", exact: "0.1.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "Observability", package: "platform-swift"),
        // …add any of the products from the README module table
    ]),
]
```

In Xcode: **File ▸ Add Package Dependencies…**, enter the repo URL, and pick a version rule (Up to Next Minor is the safe default while pre-1.0).
