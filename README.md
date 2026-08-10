English | [日本語](./README.ja.md)

# swift-cached-remote-image

Remote images in SwiftUI, cached in memory and on disk, keyed by image id rather than by URL.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![Dependencies](https://img.shields.io/badge/Dependencies-none-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

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

- ✅ **Works with private storage** — an authenticated API returning raw bytes is the default case, not the exception
- ✅ **Zero dependencies** — nothing enters your resolution space, so the package cannot collide with your HTTP client's generation
- ✅ **Memory & disk cache keyed by image id** — decoded images in memory, the bytes you received on disk
- ✅ **Widget-ready** — App Group storage plus a synchronous, network-free disk read
- ✅ **Failures reach the caller** — nothing is swallowed into a `print` or a silent `nil`
- ✅ **Customizable retry policy** — fixed count or exponential backoff
- ✅ **Customizable placeholder & error views** — fully replaceable UI

No default transport is bundled, deliberately: shipping one would constrain the dependency
resolution of everybody who never uses it, because SPM resolves dependencies per package and not
per target. Written straight on `URLSession`, a transport is about 40 lines; on an HTTP client
your app already has, about 15.

## Quick Start

Three moving parts: the transport you write, one library, and the view.

```swift
import CachedRemoteImage

struct AppImages: ImageTransport {
    let api: MyAPIClient
    func fetch(id: String) async throws -> Data { try await api.imageBytes(id) }
    func upload(_ bytes: Data, contentType: String) async throws -> String { try await api.putImage(bytes, contentType).id }
    func delete(id: String) async throws { try await api.dropImage(id) }
}

let library = try ImageLibrary(transport: AppImages(api: api))   // once, at launch
ContentView().imageLibrary(library)                              // once, at the root

CachedRemoteImage(source: .imageId("img_12345"))                 // anywhere below it
```

That is the whole surface for the common case: the view resolves the library from the
environment, checks memory, then disk, and only then calls your transport.

`ImageLibrary.init` throws when the cache directory cannot be resolved — a missing App Group
entitlement, for instance. That is a configuration mistake, and falling back to some other
directory would leave your widget permanently blank with no way to find out why.

Two other sources skip the transport entirely, for images that need no authentication:

```swift
CachedRemoteImage(source: .url(url))
CachedRemoteImage(source: .urlString("https://example.com/a.jpg"))
```

## Backends That Return URLs

If your metadata API hands back a public URL, the transport becomes two steps — read the
metadata, then fetch the bytes from that URL. `ImageTransport` returns `Data` either way, so
everything from `ImageLibrary` onwards behaves identically.

```swift
func fetch(id: String) async throws -> Data {
    let metadata = try await api.imageMetadata(id)
    return try await URLSession.shared.data(from: metadata.url).0
}
```

If resolving the id into a URL on every fetch is too expensive, cache that inside your transport.
The image bytes are already cached by `ImageLibrary`.

## Widgets

A widget extension cannot fetch images: WidgetKit's timeline generation has no place for an
async network call, and giving an extension your auth credentials is the wrong shape anyway.

So the app prefetches, and the widget reads the disk synchronously.

```swift
// App — point the cache at an App Group, prefetch after syncing
let library = try ImageLibrary(transport: AppImages(api: api),
                               configuration: .appGroup("group.com.example.app"))
let failed = await library.prefetch(topItems.map(\.imageId))

// Widget — same location, no transport, no network
let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))
let bytes = cache.imageData(for: item.imageId)   // nil = not on the device yet
```

`ImageDiskCache` has no way to reach the network, so a widget holding one cannot stall on a
fetch. Both sides resolve the directory from the same `ImageCacheLocation` value, so the paths
cannot drift apart — a one-character difference would otherwise leave the widget silently blank.

## Cache Configuration

Configuration is per library, not per view — the caches are one shared resource, and a view is
not the thing that owns them. Presets cover most of it:

```swift
let library = try ImageLibrary(transport: transport, configuration: .withRetry)
```

`.standard` is the Caches directory with no retries, `.withRetry` adds exponential backoff, and
`.appGroup(_:subdirectory:)` moves the files where a widget can read them. Everything is
adjustable through `ImageLibraryConfiguration`.

- **Memory** holds decoded images. What it saves during a scroll is decoding, not file reads
- **Disk** holds the bytes exactly as received — no re-encoding, so PNG transparency survives
  and a widget reads the real thing. Entries past the size limit are dropped oldest-first
  (App Group storage is not purged by the OS, so the limit has to be yours)

## Errors

Everything that can go wrong reaches the error view as an `ImageLoadError`: a missing library, a
string that is not a URL, a failing transport, or bytes that do not decode. The cause travels as
text — keeping the original error type would cost `Sendable` and `Equatable`, and the code that
wants to branch on the type (refresh a token, sign the user out) is the code that wrote the
transport and threw it.

Write paths (`add`, `remove`) rethrow whatever your transport threw, untouched.

## Documentation

📚 **[API reference and guides](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**
— a full transport written on `URLSession`, the widget setup end to end, and every configuration
option.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "4.0.2")
]
```

There is one product to add to your target:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
```

4.0.0 does not resolve and `from: "4.0.2"` skips it. If a stale `Package.resolved` still pins
4.0.0, delete it and resolve again.

## Requirements

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for details.
