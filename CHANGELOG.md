# Changelog

All notable changes to this project are recorded in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/lang/ja/).

## [Unreleased]

None

## [4.0.2] - 2026-08-02

**Ships a privacy manifest.** Adopters no longer have to declare it on our behalf.

`ImageDiskCache` reads `.contentModificationDateKey` to evict oldest-first when over capacity.
This is an API Apple requires a declared reason for (file timestamps), and without a
declaration adopters receive the ITMS-91053 warning.

Until now the adopting app had to write it in its own `PrivacyInfo.xcprivacy`.
That assumes the adopter knows which APIs this package calls, and makes them read
the cache implementation. **If we declare it ourselves, adopters need to know nothing.**

- One declaration only (file timestamps / `C617.1` = inside the app or App Group container)
- No collection. There is not even an implementation that fetches images (`ImageTransport` is a protocol)
- Bundled with `.copy` (`.process` may optimize it as a plist)

Nothing to do on the adopter side. Just raise the version you depend on, and a missing app-side declaration is covered.

## [4.0.1] - 2026-07-27

**A fix that makes 4.0.0 usable.** The package now has zero dependencies.

Published tags are not replaced, so **4.0.0 stays as an unusable version and this
4.0.1 fixes it**. Replacing it would make fetched caches and the revision left in an
adopter's `Package.resolved` disagree with the contents, breaking in ways whose cause
is hard to see: "cannot resolve", "what I fetched is different".

### Why 4.0.0 was unusable

4.0.0 put the default fetch implementation (`URLImageTransport`, which uses `APIClient`)
in a separate target named `CachedRemoteImageAPIClient`. The aim was that adopters who
only use the view would not pull in `APIClient`.

**That does not work. SPM resolves dependencies per package**, so dependencies declared
for an unused target still enter the adopter's resolution space. Apps on the
`swift-api-client` 1.x generation could not adopt 4.0.0:

```
error: Dependencies could not be resolved because root depends on
'swift-authentication' 1.0.0..<2.0.0 and root depends on 'swift-cached-remote-image' 4.0.0..<5.0.0.
'swift-cached-remote-image' >= 4.0.0 practically depends on 'swift-api-client' 3.0.0..<4.0.0
```

To separate, you have to separate the package itself. And `URLImageTransport` merely fills
the 3 methods of `ImageTransport` over HTTP — under 30 lines if written with the HTTP stack
the app already has. Bundling an unused implementation and constraining the adopter's dependency graph is not a fair trade.

### Changed

- **Removed** the `CachedRemoteImageAPIClient` target and `URLImageTransport`.
  **No default fetch implementation is bundled** — adopters implement `ImageTransport` with their own HTTP stack
- The package now has **zero** dependencies (the DocC plugin is build-time only)
- Only one product is added to a target: `CachedRemoteImage`
- Tests went 72 → 52. The 20 tests belonging to the removed target (multipart assembly,
  LRU for URL resolution) went away with it. The remaining 52 are regressions for cache,
  retry, and transport substitution, all green
- README / DocC now match reality. Fetching is what adopters write, so the
  `ImageTransport` implementation example (private storage, an authenticated API returning bytes) is the centerpiece

### Why patch, not major

Removing a product is strictly a breaking change. But **4.0.0 does not resolve, so it has
no real adopters** (only adopters who could resolve it could use `CachedRemoteImageAPIClient`,
and no such environment exists). Stacking one more major just to fix a broken version
advances the version number away from reality.

### If you were trying to adopt 4.0.0

Move straight to `4.0.1` or later. If 4.0.0 remains in `Package.resolved`, delete it and resolve again.

## [4.0.0] - 2026-07-27

> ⚠️ **This version does not resolve. Use 4.0.1 or later.**
> The module split in "Breaking change 2" below is the cause; this version cannot be adopted (see the 4.0.1 entry).
> What follows is a record of what this version shipped, not the current API.

The direction of responsibility is inverted. 3.x had the package hard-code "how images are
fetched" and hid the cache inside it. 4.0 has **the app supply the fetching, and the package own the cache**.

### Why the change

3.1.0 added `ImageService.loadImage(imageId:)`, but in practice it was **an entrance with nothing behind it**.

- `ImageServiceImpl` does not override this requirement, and the default implementation
  delegates to `getImageResource` → URL → `loadImage(from:)`. That does not hold for
  backends without a public URL
- The two-tier cache was keyed by **URL string**, so a `loadImage(imageId:)` written by the
  adopter never reached the cache at all

As a result, adopters using private storage rewrote the cache themselves, had
`getImageResource` throw "there is no URL", and had `uploadImage` fabricate a nonexistent
URL and return it — implementations written only to satisfy the protocol.
Once two backends of the same shape appeared in a row, that is evidence not of an exception but that **the default assumption is backwards**.

### ⚠️ Breaking changes

#### 1. Removed `ImageService`, replaced by `ImageTransport` + `ImageLibrary`

The app implements only `ImageTransport`, three methods.
The two-tier cache, retries, and feeding SwiftUI views are taken over by the concrete type `ImageLibrary`.

```swift
public protocol ImageTransport: Sendable {
    func fetch(id: String) async throws -> Data
    func upload(_ data: Data, contentType: String) async throws -> String  // → image id
    func delete(id: String) async throws
}
```

**The cache key is now the image ID.** The byte path rides the two-tier cache as-is.

- Removed: `ImageService` / `ImageServiceImpl` / `ImageResource`
- Added: `ImageTransport` / `ImageLibrary` / `ImageDiskCache` /
  `ImageCacheLocation` / `ImageLibraryConfiguration`
- Environment value and modifier: `\.imageService` → `\.imageLibrary`, `.imageService(_:)` → `.imageLibrary(_:)`

Migration (private storage, API returning bytes):

```swift
// Before: ~130 lines to satisfy the 9 requirements of ImageService. Half is a hand-written memory cache
struct MyImageService: ImageService {
    func getImageResource(imageId: String) async throws -> ImageResource {
        throw ImageServiceError.noPublicURL       // implementation only to state there is no URL
    }
    func uploadImage(imageData: Data, contentType: String) async throws -> ImageResource {
        ImageResource(id: uploaded.id, url: placeholderURL(for: uploaded.id))  // a URL that does not exist
    }
    // + loadImage(imageId:) / loadImage(from:) / deleteImage / clearResourceCache /
    //   clearImageCache / diskCacheSize / a hand-rolled memory cache actor
}

// After: 3 methods
struct MyImageTransport: ImageTransport {
    let api: MyAPI
    func fetch(id: String) async throws -> Data { try await api.getImage(id: id) }
    func upload(_ data: Data, contentType: String) async throws -> String {
        try await api.uploadImage(data, contentType: contentType).id
    }
    func delete(id: String) async throws { try await api.deleteImage(id: id) }
}

let library = try ImageLibrary(transport: MyImageTransport(api: api))
ContentView().imageLibrary(library)
```

Migration (REST API returning URLs) — passing `CachedRemoteImageAPIClient`'s
`URLImageTransport` keeps it working through the same path as before:

```swift
// Before
let service = ImageServiceImpl(apiClient: apiClient, imagesPath: "/images", maxResourceCacheSize: 100)
ContentView().imageService(service)

// After
let transport = URLImageTransport(apiClient: apiClient, imagesPath: "/images", maxURLCacheSize: 100)
let library = try ImageLibrary(transport: transport)
ContentView().imageLibrary(library)
```

#### 2. Split into two modules

`CachedRemoteImage` no longer depends on `APIClient`. A Presentation layer that only uses
the view no longer drags in Infrastructure (the HTTP client).

| Module | Contents | Dependencies |
|---|---|---|
| `CachedRemoteImage` | Views, `ImageTransport`, `ImageLibrary`, `ImageDiskCache`, configuration | None |
| `CachedRemoteImageAPIClient` | `URLImageTransport` (metadata API → URL → URLSession) | `APIClient` |

To use `URLImageTransport`, add `CachedRemoteImageAPIClient` to the dependencies as well:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
.product(name: "CachedRemoteImageAPIClient", package: "swift-cached-remote-image"),
```

#### 3. Configuration is per library, not per view

`CachedRemoteImageConfiguration` is gone, replaced by `ImageLibraryConfiguration`.
The `configuration` argument of `CachedRemoteImage(source:configuration:)` is gone too.

Cache and retries are both resources the library holds as one; they are not the kind of thing to switch per view.
In fact `cachePolicy` was read from nowhere — **passing it did nothing**.

```swift
// Before (cachePolicy had no effect. retryPolicy was per view)
CachedRemoteImage(source: .imageId(id), configuration: .withRetry)

// After (once, when creating the library. Also applies to fetches that skip the view)
let library = try ImageLibrary(transport: transport, configuration: .withRetry)
```

- Removed: `CachePolicy` (`.all` / `.metadataOnly` / `.imageOnly` / `.none`) — it was never implemented
- Removed: `CachedRemoteImageConfiguration`
- `RetryPolicy` stays (moved to `ImageLibraryConfiguration`)

#### 4. The disk cache location can be injected

An App Group can be specified. Required for a widget extension to read images.

```swift
let library = try ImageLibrary(transport: transport, configuration: .appGroup("group.com.example.app"))
```

If the location cannot be resolved, `ImageLibrary.init` **throws** (`ImageCacheLocationError`),
because silently falling back elsewhere hides the reason a widget shows nothing until the very end.
Creating an `ImageLibrary` now requires `try`.

#### 5. Disk stores the received bytes as-is

3.x decoded to `UIImage` and re-encoded as JPEG q0.8 before writing.
That discarded the fetched bytes to produce different, degraded ones, and PNG transparency was lost too.
4.0 writes the received `Data` unchanged. What the widget reads is the real bytes as well.

Cache file names changed too (SHA-256 of the key). **3.x disk caches cannot be read.**
They are simply re-fetched as cache misses on first launch; no deletion step is needed.

#### 6. Upload is now multipart

`UploadImageContract` drops Base64-in-JSON and sends `multipart/form-data`.
The 33% inflation and holding everything in memory are gone. The field name can be changed
with `uploadFieldName` of `URLImageTransport` (default `"file"`).

**If the server expects Base64 JSON (`image_data` / `content_type`), it has to be changed
to accept multipart.**

#### 7. How failures are reported

- Swapped the cases of `ImageLoadError`: `.libraryNotConfigured` / `.invalidURL` /
  `.transportFailed(reason:)` / `.notAnImage(byteCount:)`
  (removed: `.metadataFetchFailed` / `.downloadFailed` / `.networkError` / `.unknown`)
- When `ImageLibrary` is not injected, 3.x printed and moved on.
  4.0 yields `.failure(.libraryNotConfigured)` and shows it in the error view
- Removed `catch { print; return nil }` in `loadImage(from:)`. Fetch failures throw
- URL conversion in `ImageResourceDTO` throws instead of `fatalError`.
  The app no longer crashes just because the server returned a broken value
- Display paths (`image(for:)` / `image(from:)` / `imageData(for:)`) wrap in `ImageLoadError`.
  Write paths (`add` / `remove`) pass through the type the transport threw

#### 8. Cache management API

```swift
// Before                              // After
await service.clearResourceCache()     library.clearMemoryCache()
await service.clearImageCache()        library.clearDiskCache()
await service.diskCacheSize()          library.diskCacheSize()
```

No longer `async` (file operations are synchronous; there is nothing to wait for).

### Added

- `ImageDiskCache` — a type that reads disk **synchronously**. It has no means to reach the network.
  The entrance for WidgetKit timeline generation

  ```swift
  let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
  if let data = cache.imageData(for: item.imageId) { /* reads synchronously */ }
  ```

- `ImageLibrary.cachedImageData(for:)` — the same entrance on the app side
- `ImageLibrary.prefetch(_:)` — pulls images to be shown onto the device in advance.
  Widgets cannot hold credentials, so the app puts them there. Returns the IDs it could not fetch
- `ImageCacheLocation` — pass the storage location as a value. The app and the widget
  resolve from the same value, so path spellings cannot drift
- A disk cache limit (default 100MB, oldest deleted when exceeded).
  App Groups are a place the OS does not clear, so without a limit device space never comes back

### Changed

- `ImageSource` also conforms to `Hashable`
- `RetryPolicy.delay(for:)` is no longer `async` (it was a pure computation)
- Retries now apply only to fetch failures. Undecodable bytes (`.notAnImage`) are not
  retried, because decoding the same bytes again cannot change the result

### Tests

31 → 72. Tests that lost meaning with the design change were deleted, and regressions were
added for the new paths (ID-keyed cache, synchronous reads, transport substitution, limits, multipart).

## [3.1.0] - 2026-07-20

### Added

- Added `ImageService.loadImage(imageId:)`. A load path for backends without a public URL
  (private storage, authenticated APIs returning image bytes). When metadata carries no URL,
  the two-step `getImageResource` → `loadImage(from:)` does not hold, so implementing this
  requirement fetches the bytes directly.

  The default implementation still resolves a URL from metadata and delegates to `loadImage(from:)`,
  so **implementers whose backend can return URLs need do nothing** (non-breaking addition).

  The same feature was already added to the 1.x line as 1.1.6 (2026-07-20), but was never
  ported to the 2.0.0+ line, leaving adopters of `loadImage(imageId:)` stranded on 1.x.

### Changed

- In the 1.x implementation the default implementation swallowed metadata fetch failures with `try?` and returned `nil`,
  so callers lost the cause and treated it as "download failed". In reality it had not even
  reached the download. This line makes the requirement `throws` and **propagates the cause as-is**.
  `nil` now means only "it was fetched but did not become an image".
  Non-throwing implementations still satisfy the requirement, so existing conformers need no change.

## [3.0.0] - 2026-07-19

### ⚠️ Breaking changes

- Updated the swift-api-client dependency to `from: "3.0.0"` (unifying the api-client generation across the family).
  This package does not use `AuthTokenProvider` symbols directly, so there is no source change,
  but the dependency's major bump affects consumers' resolution graphs.

## [2.0.0] - 2026-07-19

### ⚠️ Breaking changes

- Updated the swift-api-client dependency to `from: "2.3.1"` (pin generation unification).
  Follows the Codec seam change in APIInput.
- Added 28 real tests for LRU / two-tier cache / ImageService
  (previously placeholders only).

## [1.1.5] - 2026-01-18

### Changed
- Changed image upload from multipart form data to a Base64-encoded JSON body
- Added the `UploadImageRequestBody` struct to structure the request body
- Added `uploadImage(imageData:contentType:)` to the `ImageService` protocol (content type can be specified)

### Breaking changes
- Change to support servers expecting a Base64 JSON body

## [1.1.4] - 2026-01-08

### Changed
- Changed `ImageRepository` and `ImageServiceImpl` to generic implementations conforming to the `APIExecutable` protocol
- Migrated from the `APIEndpoint` + `request()` pattern to the `APIContract` + `execute()` pattern
- Added type-safe API contracts (`GetImageResourceContract`, `UploadImageContract`, `DeleteImageContract`)
- Updated swift-tools-version from 6.0 to 6.2
- Added `Package.resolved` to gitignore to exclude it from version control

## [1.1.3] - 2025-11-13

### Changed
- Changed package dependency notation to explicit `.upToNextMajor(from:)`
  - `swift-api-client`: `from: "1.0.0"` → `.upToNextMajor(from: "1.0.0")`
  - `swift-docc-plugin`: `from: "1.4.0"` → `.upToNextMajor(from: "1.4.0")`
  - Functionally equivalent, but the versioning strategy's intent is clearer

## [1.1.2] - 2025-11-09

### Fixed
- Unified the automated release workflow messages entirely in Japanese (PR description, release notes, log messages)

## [1.0.5] - 2025-11-04

### Added
- Added automatic DocC documentation generation and publishing to GitHub Pages
  - Added Swift DocC Plugin to the dependencies
  - GitHub Actions workflow generates and deploys documentation automatically
  - Added a link to the full documentation in README (https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)

### Changed
- Improved documentation accessibility

### Fixed
- Fixed compile errors in Swift 6 strict concurrency mode
  - Added `@MainActor` to `ImageService.loadImage(from:)`
  - Added `@MainActor` to `ImageDataCache` methods
  - Resolved actor-boundary issues with non-Sendable types (`NSImage`/`UIImage`)

## [1.0.4] - 2025-02-11

### Changed
- Removed implementation details from README, narrowing it to the user's perspective
  - Removed the internal flow (metadata fetch flow) explanation
  - Removed the section on using ImageEntity directly (implementation detail)
  - Focused only on features users actually use

## [1.0.3] - 2025-02-11

### Added
- Added an API prerequisites section to README
  - Documented the REST API requirements for using `.imageId`
  - Documented the required API endpoints (GET, POST, DELETE)
  - Specified the required JSON response format in camelCase
  - Clarified that URL-based usage (.url/.urlString) needs no API server

## [1.0.2] - 2025-02-11

### Changed
- Added accurate API examples and badges to README
  - Added badges for Swift 6.0, platforms, SPM, and license
  - Added a quick start section for the fastest onboarding
  - Fixed all examples to the correct ImageSource API (source: .url(), .urlString(), .imageId())
  - Fixed ImageServiceImpl initialization to the correct parameters
  - Added a comprehensive description of ImageSource types
  - Added an ImageID feature section with the proper workflow
  - Removed the nonexistent Firebase Storage section
  - Added cache configuration examples
  - Updated the features section to reflect actual functionality

### Fixed
- Fixed README API usage examples not matching the implementation
- Fixed incorrect ImageServiceImpl initialization parameters

## [1.0.1] - 2024-12-XX

### Fixed
- Use .product() for dependencies whose package name differs

## [1.0.0] - 2024-12-XX

### Added
- Initial release
- SwiftUI-native API
- Memory & disk cache
- Asynchronous image loading
- Flexible ImageSource (URL, URL string, image ID)
- Image ID support
- Customizable retry policy
- Customizable placeholder and error views
- Cache management
- iOS 17.0+ and macOS 14.0+ support

[Unreleased]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.5...HEAD
[1.1.5]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.0.5...v1.1.2
[1.0.5]: https://github.com/no-problem-dev/swift-cached-remote-image/compare/v1.0.4...v1.0.5

<!-- Auto-generated on 2025-11-09T05:06:53Z by release workflow -->

<!-- Auto-generated on 2025-11-13T01:14:35Z by release workflow -->

<!-- Auto-generated on 2026-01-08T00:03:15Z by release workflow -->
