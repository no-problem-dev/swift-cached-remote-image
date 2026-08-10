English | [日本語](./README.ja.md)

# swift-cached-remote-image

A SwiftUI package for displaying remote images with memory and disk caching.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![Dependencies](https://img.shields.io/badge/Dependencies-none-brightgreen.svg)
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

### This package has no dependencies

No default transport is bundled. You write it: about 40 lines straight from `URLSession`, as
the example below shows, or 15 if your app already has an HTTP client.

It is not bundled because bundling one constrains your dependency resolution. The first cut of
4.0 put a default transport — one built on an HTTP client — in a separate target, on the
assumption that people who only use the views would never pull the dependency in. **That does
not work.** SPM resolves dependencies **per package**, not per target. A dependency declared
for a target you never build still enters your resolution space. In practice, an app already on
a different generation of that HTTP client failed to resolve versions the moment it added this
package — because of a target it was not using.

Splitting only helps if you split the package itself. And `ImageTransport` is three methods that
sit straight on top of an HTTP stack your app already has. Shipping an implementation nobody
uses is not worth constraining every consumer's dependency graph.

### Features

- ✅ **Works with private storage** — an authenticated API returning raw bytes is the default case, not the exception
- ✅ **Zero dependencies** — nothing enters your resolution space, so the package cannot collide with your HTTP client's generation
- ✅ **Memory & disk cache keyed by image id** — decoded images in memory, the bytes you received on disk
- ✅ **Widget-ready** — App Group storage plus a synchronous, network-free disk read
- ✅ **Failures reach the caller** — nothing is swallowed into a `print` or a silent `nil`
- ✅ **Customizable retry policy** — fixed count or exponential backoff
- ✅ **Customizable placeholder & error views** — fully replaceable UI
- ✅ **iOS 17.0+ and macOS 14.0+**

## Requirements

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "4.0.2")
]
```

**4.0.0 is unusable** — it does not resolve; see [CHANGELOG.md](CHANGELOG.md) for why. If
`Package.resolved` still pins 4.0.0, delete it and resolve again.

There is one product to add to your target:

```swift
.product(name: "CachedRemoteImage", package: "swift-cached-remote-image"),
```

## Quick Start

### 1. Write the transport

The default case this package is built for is **private storage** — an authenticated API that
returns image bytes directly. `ImageTransport` needs three methods, and none of them needs
caching or retries: the surrounding `ImageLibrary` owns those, and only calls you once it is
certain the bytes are in neither memory nor disk.

```swift
import CachedRemoteImage
import Foundation

struct APIImageTransport: ImageTransport {
    let baseURL: URL
    let accessToken: @Sendable () async -> String

    func fetch(id: String) async throws -> Data {
        let request = await authorized("images/\(id)")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(response)
        return data
    }

    func upload(_ imageData: Data, contentType: String) async throws -> String {
        var request = await authorized("images", method: "POST")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.upload(for: request, from: imageData)
        try Self.checkOK(response)
        return try JSONDecoder().decode(UploadedImage.self, from: data).id
    }

    func delete(id: String) async throws {
        let request = await authorized("images/\(id)", method: "DELETE")
        let (_, response) = try await URLSession.shared.data(for: request)
        try Self.checkOK(response)
    }

    private func authorized(_ path: String, method: String = "GET") async -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("Bearer \(await accessToken())", forHTTPHeaderField: "Authorization")
        return request
    }

    private struct UploadedImage: Decodable {
        let id: String
    }

    private static func checkOK(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
```

If your app already has an HTTP client, the three methods just sit on top of it:

```swift
struct APIImageTransport: ImageTransport {
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

Throw whatever error type you like. On the display path it is wrapped into
`ImageLoadError.transportFailed(reason:)`, but the description (`localizedDescription`)
survives. Code that wants to branch on the type — catch an expired session, send the user to
sign-in — belongs in the transport you wrote: it threw the error, so it holds the most
information about it.

### 2. Build the library and inject it

```swift
@main
struct MyApp: App {
    private let library: ImageLibrary

    init() {
        do {
            library = try ImageLibrary(transport: APIImageTransport(api: api))
        } catch {
            fatalError("Cannot initialize the image cache: \(error)")
        }
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

If your metadata API hands back a public URL, the transport becomes two steps — read the
metadata, then fetch the bytes from that URL. `ImageTransport` returns `Data` either way, so
everything from `ImageLibrary` onwards behaves identically.

```swift
struct MetadataImageTransport: ImageTransport {
    let baseURL: URL

    func fetch(id: String) async throws -> Data {
        let (json, _) = try await URLSession.shared.data(from: baseURL.appending(path: "images/\(id)"))
        let metadata = try JSONDecoder().decode(ImageMetadata.self, from: json)
        let (bytes, _) = try await URLSession.shared.data(from: metadata.url)
        return bytes
    }

    // upload / delete take the same shape: POST / DELETE, then read the id out of the JSON

    private struct ImageMetadata: Decodable {
        let id: String
        let url: URL
    }
}
```

If resolving the id → URL on every fetch is too expensive, cache it inside your transport. The
image bytes are cached by `ImageLibrary`, so the transport only has to care about its own
concern — resolving the URL.

## Widgets

A widget extension cannot fetch images: WidgetKit's timeline generation has no place for an
async network call, and giving an extension your auth credentials is the wrong shape anyway.

So the app prefetches, and the widget reads the disk synchronously.

**App — point the cache at an App Group and prefetch after syncing:**

```swift
let library = try ImageLibrary(
    transport: APIImageTransport(api: api),
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

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

For bug reports or feature requests, please open an [issue on GitHub](https://github.com/no-problem-dev/swift-cached-remote-image/issues).
