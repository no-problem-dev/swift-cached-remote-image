English | [日本語](./README.ja.md)

# swift-cached-remote-image

A SwiftUI package for displaying remote images with memory and disk caching.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[Full Documentation](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**

## Overview

**Your app supplies the way images are fetched. This package owns the caching.**

Authentication, endpoints and response shapes differ per app — the package has no business
guessing them. Caching, retries and the SwiftUI loading lifecycle are the same everywhere —
you should not have to write them again.

So you implement three methods:

```swift
public protocol ImageTransport: Sendable {
    func fetch(id: String) async throws -> Data
    func upload(_ data: Data, contentType: String) async throws -> String  // → image id
    func delete(id: String) async throws
}
```

…and `ImageLibrary` gives you a two-layer cache keyed by **image id**, retries, prefetching,
a synchronous disk read for widgets, and the `CachedRemoteImage` view.

If your backend returns public URLs from a metadata endpoint, `URLImageTransport` ships with
the package — you do not have to write a transport at all.

### Features

- ✅ **Works with private storage** — an authenticated API returning raw bytes is the default case, not the exception
- ✅ **Memory & disk cache keyed by image id** — decoded images in memory, the bytes you received on disk
- ✅ **Widget-ready** — App Group storage plus a synchronous, network-free disk read
- ✅ **Presentation-safe module split** — the view module does not depend on `APIClient`
- ✅ **Failures reach the caller** — nothing is swallowed into a `print` or a silent `nil`
- ✅ **Customizable retry policy** — fixed count or exponential backoff
- ✅ **Customizable placeholder & error views** — fully replaceable UI
- ✅ **iOS 17.0+ and macOS 14.0+**

### Modules

| Module | Contents | Depends on |
|---|---|---|
| `CachedRemoteImage` | Views, `ImageTransport`, `ImageLibrary`, `ImageDiskCache`, configuration | — |
| `CachedRemoteImageAPIClient` | `URLImageTransport` (metadata API → URL → URLSession) | `APIClient` |

The split exists so a Presentation layer that only draws images does not pull in an HTTP client.

## Requirements

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "4.0.0")
]
```

Then add the module(s) you need:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
// only if you use the bundled URL-based transport
.product(name: "CachedRemoteImageAPIClient", package: "swift-cached-remote-image"),
```

## Quick Start

### 1. Implement the transport

```swift
import CachedRemoteImage

struct MyImageTransport: ImageTransport {
    let api: MyAPIClient

    func fetch(id: String) async throws -> Data {
        try await api.getImage(id: id)
    }

    func upload(_ data: Data, contentType: String) async throws -> String {
        try await api.uploadImage(data, contentType: contentType).id
    }

    func delete(id: String) async throws {
        try await api.deleteImage(id: id)
    }
}
```

### 2. Build the library and inject it

```swift
@main
struct MyApp: App {
    private let library: ImageLibrary

    init() throws {
        library = try ImageLibrary(transport: MyImageTransport(api: api))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .imageLibrary(library)
        }
    }
}
```

`ImageLibrary.init` throws when the cache directory cannot be resolved — a missing App Group
entitlement, for instance. That is a configuration mistake, and falling back to some other
directory would leave your widget permanently blank with no way to find out why.

### 3. Display

```swift
CachedRemoteImage(source: .imageId("img_12345"))

CachedRemoteImage(source: .imageId("img_12345"), contentMode: .fill) { image in
    image.resizable()
} placeholder: {
    Color.gray.opacity(0.2)
}
```

`ImageSource` has three cases:

```swift
CachedRemoteImage(source: .imageId("img_12345"))                        // through ImageTransport
CachedRemoteImage(source: .url(url))                                    // plain URLSession
CachedRemoteImage(source: .urlString("https://example.com/a.jpg"))      // plain URLSession
```

`.url` / `.urlString` do not go through your transport. A URL already names its own
destination, so there is no app-specific fetching to inject. Use them for images that need no
authentication — search-result thumbnails, for example.

## Backends That Return URLs

If `GET /images/{id}` returns `{ "id": ..., "url": ... }`, use the bundled transport:

```swift
import CachedRemoteImageAPIClient

let transport = URLImageTransport(apiClient: apiClient, imagesPath: "/v1/images")
let library = try ImageLibrary(transport: transport)
```

Required endpoints:

| Endpoint | Body | Response |
|---|---|---|
| `GET {imagesPath}/{id}` | — | `{ "id": "img_123", "url": "https://..." }` |
| `POST {imagesPath}` | `multipart/form-data` (field name `file` by default) | same shape |
| `DELETE {imagesPath}/{id}` | — | — |

Change the field name with `URLImageTransport(… uploadFieldName: "image")`.

The id → URL lookup is cached (LRU) inside the transport. The image bytes are cached by
`ImageLibrary`, so every transport gets the same caching behavior.

## Widgets

A widget extension cannot fetch images: WidgetKit's timeline generation has no place for an
async network call, and giving an extension your auth credentials is the wrong shape anyway.

So the app prefetches, and the widget reads the disk synchronously.

**App — point the cache at an App Group and prefetch after syncing:**

```swift
let library = try ImageLibrary(
    transport: MyImageTransport(api: api),
    configuration: .appGroup("group.com.example.app")
)

let failed = await library.prefetch(topItems.map(\.imageId))
```

**Widget — same location, no transport, no network:**

```swift
import CachedRemoteImage

let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))

if let data = cache.imageData(for: item.imageId), let image = UIImage(data: data) {
    Image(uiImage: image).resizable()
} else {
    Text(item.emoji)          // always have somewhere to land
}
```

`ImageDiskCache` has no way to reach the network, so a widget holding one cannot stall on a
fetch. `imageData(for:)` returning `nil` means exactly one thing: the bytes are not on the
device yet.

Both sides resolve the directory from the same `ImageCacheLocation` value, so the paths cannot
drift apart — a one-character difference would otherwise leave the widget silently blank.

## Cache Configuration

```swift
let library = try ImageLibrary(
    transport: transport,
    configuration: ImageLibraryConfiguration(
        cacheLocation: .appGroup("group.com.example.app"),
        diskCacheSizeLimit: 200 * 1024 * 1024,
        memoryCountLimit: 200,
        memoryCostLimit: 100 * 1024 * 1024,
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
)
```

Presets: `.standard`, `.withRetry`, `.appGroup(_:subdirectory:)`.

Configuration is per library, not per view — the caches are one shared resource, and a view is
not the thing that owns them.

- **Memory** holds decoded images. What it saves during a scroll is decoding, not file reads
- **Disk** holds the bytes exactly as received — no re-encoding, so PNG transparency survives
  and a widget reads the real thing. Entries past `diskCacheSizeLimit` are dropped oldest-first
  (App Group storage is not purged by the OS, so the limit has to be yours)

```swift
library.clearMemoryCache()
library.clearDiskCache()
let bytes = library.diskCacheSize()
```

## Errors

```swift
public enum ImageLoadError: Error, Equatable, Sendable {
    case libraryNotConfigured          // no .imageLibrary(_:) in the environment
    case invalidURL(String)
    case transportFailed(reason: String)
    case notAnImage(byteCount: Int)
}
```

Every one of these reaches the error view. The cause travels as text: keeping the original
error type would cost `Sendable` and `Equatable`, and the code that wants to branch on the
type — refresh a token, sign the user out — is the code that wrote the transport and threw it.

Write paths (`add`, `remove`) rethrow whatever your transport threw, untouched.

## Migrating from 3.x

`ImageService` / `ImageServiceImpl` are gone; see [CHANGELOG.md](CHANGELOG.md) for the full list
of breaking changes and step-by-step migration.

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

For bug reports or feature requests, please open an [issue on GitHub](https://github.com/no-problem-dev/swift-cached-remote-image/issues).
