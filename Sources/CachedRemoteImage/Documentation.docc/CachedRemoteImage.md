# ``CachedRemoteImage``

Display remote images in SwiftUI, cached in memory and on disk, keyed by image id.

## Overview

**Your app supplies the way images are fetched. This package owns the caching.**

Authentication, endpoints and response shapes differ per app, and a package has no business
guessing them. Caching, retries and the SwiftUI loading lifecycle are the same everywhere, and you
should not have to write them again. So your app implements the three methods of
``ImageTransport``, and ``ImageLibrary`` takes care of the rest.

**Cache keys are image ids**, so a backend that never exposes a public URL — an authenticated API
that returns raw bytes — still gets the full benefit of both cache layers.

### Why no transport ships with the package

Bundling a default implementation would constrain the dependency resolution of everyone who never
uses it. Putting it in a separate target does not help: SPM resolves dependencies **per package**,
not per target, so a dependency declared for a target you never build still enters your resolution
space. In practice an app already on a different generation of the same HTTP client failed to
resolve versions the moment it added this package, because of a target it was not using.

Splitting only helps if you split the package itself, and ``ImageTransport`` is three methods
sitting on top of an HTTP stack your app already has. Shipping an implementation nobody uses is
not worth constraining every consumer's dependency graph.

## Getting started

### 1. Write the transport

The case this package is built for is **private storage**: an authenticated API that returns image
bytes directly. None of the three methods needs caching or retries. ``ImageLibrary`` owns those,
and calls you only once it is certain the bytes are in neither memory nor disk.

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

Throw whatever error type you like. On the display path it is wrapped into
``ImageLoadError/transportFailed(reason:)``, but the description survives. Code that wants to
branch on the concrete type — catch an expired session, send the user to sign-in — belongs in the
transport you wrote: it threw the error, so it holds the most information about it.

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

``ImageLibrary/init(transport:configuration:)`` throws when the cache directory cannot be
resolved — a missing App Group entitlement, for instance. That is a configuration mistake, and
falling back to some other directory would leave your widget permanently blank with no way to find
out why.

### 3. Display

``CachedRemoteImage`` takes an ``ImageSource`` and handles every state with built-in views.

```swift
CachedRemoteImage(source: .imageId("abc123"))

CachedRemoteImage(source: .url(imageURL))

CachedRemoteImage(source: .imageId("abc123"), contentMode: .fill) { image in
    image.resizable()
}
```

``ImageSource/url(_:)`` and ``ImageSource/urlString(_:)`` do not go through your transport. A URL
already names its own destination, so there is no app-specific fetching to inject. Use them for
images that need no authentication, such as search-result thumbnails. They are cached in a key
space of their own, so an id that reads like a URL cannot collide with a real one.

## Backends that return URLs

If your metadata API hands back a public URL, the transport becomes two steps: read the metadata,
then fetch the bytes from that URL. ``ImageTransport`` returns `Data` either way, so everything
from ``ImageLibrary`` onwards behaves identically.

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

If resolving the id into a URL on every fetch is too expensive, cache that inside your transport.
The image bytes are already cached by ``ImageLibrary``, so the transport only has to care about
its own concern.

## Configuring the caches

``ImageLibraryConfiguration`` is passed once, when the library is built. The caches and the retry
policy are one shared resource that a view does not own, and settings given here also apply to
fetches that never go through a view, such as ``ImageLibrary/prefetch(_:)``.

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

The presets are ``ImageLibraryConfiguration/standard``, ``ImageLibraryConfiguration/withRetry``
and ``ImageLibraryConfiguration/appGroup(_:subdirectory:)``.

- **Memory** holds decoded images. What it saves during a scroll is decoding, not file reads.
  Entries do not survive the process and may be evicted under memory pressure, so treat a miss as
  ordinary.
- **Disk** holds the bytes exactly as received. Nothing is re-encoded, so PNG transparency
  survives and a widget reads the real file. Entries past
  ``ImageLibraryConfiguration/diskCacheSizeLimit`` are dropped oldest-first — the system never
  reclaims an App Group container, so that ceiling has to be yours.

Both layers can be emptied independently, and the disk total is available at any time:

```swift
library.clearMemoryCache()
library.clearDiskCache()
let bytes = library.diskCacheSize()
```

## Sharing images with a widget

A widget extension cannot fetch images: WidgetKit's timeline generation has no place for an async
network call, and giving an extension your credentials is the wrong shape anyway. So the app
prefetches, and the widget reads the disk synchronously.

Point the app's cache at an App Group, then prefetch after a sync:

```swift
let library = try ImageLibrary(
    transport: APIImageTransport(api: api),
    configuration: .appGroup("group.com.example.app")
)

let failed = await library.prefetch(topItems.map(\.imageId))
```

The widget builds ``ImageDiskCache`` from the same location, with no transport and no network:

```swift
let cache = try ImageDiskCache(location: .appGroup("group.com.example.app"))

if let data = cache.imageData(for: item.imageId), let image = UIImage(data: data) {
    Image(uiImage: image).resizable()
} else {
    Text(item.emoji)          // always have somewhere to land
}
```

``ImageDiskCache`` has no way to reach the network, so a widget holding one cannot stall on a
fetch. ``ImageDiskCache/imageData(for:)`` returning `nil` means exactly one thing: those bytes are
not on the device yet.

Both sides resolve the directory from the same ``ImageCacheLocation`` value, so the paths cannot
drift apart. A one-character difference would otherwise leave the widget silently blank while the
app still looked correct.

## Replacing the built-in states

Supply all four builders to take over the placeholder, loading, error and loaded appearances.

```swift
CachedRemoteImage(source: .imageId("abc123")) { image in
    image.resizable().scaledToFill()
} loading: {
    ProgressView("Loading…")
} error: { failure in
    VStack {
        Image(systemName: "xmark.circle")
        Text(failure.localizedMessage).font(.caption)
    }
} placeholder: {
    Color.gray.opacity(0.2)
}
```

Every ``ImageLoadError`` reaches that error builder, including
``ImageLoadError/libraryNotConfigured`` when no library was injected. The cause travels as text
rather than as the original error, which keeps the value `Sendable` and `Equatable`; the code that
wants to branch on the concrete type is the transport that threw it. The write paths,
``ImageLibrary/add(_:contentType:)`` and ``ImageLibrary/remove(id:)``, rethrow whatever your
transport threw, untouched.

## Topics

### Views

- ``CachedRemoteImage``

### Built-in state views

- ``DefaultLoadingView``
- ``DefaultErrorView``
- ``DefaultPlaceholderView``

### Fetching and storing images

- ``ImageTransport``
- ``ImageLibrary``

### Caching

- ``ImageDiskCache``
- ``ImageCacheLocation``
- ``ImageCacheLocationError``

### Image sources

- ``ImageSource``

### Configuration

- ``ImageLibraryConfiguration``
- ``RetryPolicy``

### Loading state

- ``LoadingState``
- ``ImageLoadError``
