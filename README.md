English | [日本語](./README.ja.md)

# swift-cached-remote-image

A SwiftUI package for displaying remote images with memory and disk caching.

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2017.0+%20%7C%20macOS%2014.0+-blue.svg)
![SPM](https://img.shields.io/badge/Swift_Package_Manager-compatible-brightgreen.svg)
![License](https://img.shields.io/badge/License-MIT-yellow.svg)

📚 **[Full Documentation](https://no-problem-dev.github.io/swift-cached-remote-image/documentation/cachedremoteimage/)**

## Overview

`swift-cached-remote-image` is a package for efficiently loading remote images in SwiftUI with two-layer memory and disk caching. It provides async image loading, retry policies, and fully customizable placeholders.

### Features

- ✅ **Native SwiftUI API** — Seamlessly integrated with SwiftUI
- ✅ **Memory & Disk Cache** — Automatic two-layer caching for fast display
- ✅ **Async Image Loading** — Modern concurrency with async/await
- ✅ **Flexible ImageSource** — Load from URL, URL string, or image ID
- ✅ **Image ID Support** — Fetch images through `ImageService` from a resource endpoint
- ✅ **Customizable Retry Policy** — Fixed count or exponential backoff
- ✅ **Customizable Placeholder & Error Views** — Fully replaceable UI
- ✅ **Cache Management** — Separate control of resource and data caches
- ✅ **iOS 17.0+ and macOS 14.0+** — Cross-platform support

## Requirements

- iOS 17.0+
- macOS 14.0+
- Swift 6.0+

## Dependencies

- [swift-api-client](https://github.com/no-problem-dev/swift-api-client) — HTTP client

## Prerequisites

When using `.imageId`, a **REST API that returns responses in the format below** is required.

### Required API Endpoints

1. **GET `/images/{imageId}`** — Fetch image resource
2. **POST `/images`** — Upload image (Base64-encoded JSON)
3. **DELETE `/images/{imageId}`** — Delete image

### Required Response Format (JSON)

```json
{
  "id": "img_123",
  "url": "https://example.com/images/photo.jpg"
}
```

When using `.url` or `.urlString` directly, no API server is required.

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/no-problem-dev/swift-cached-remote-image.git", from: "1.1.5")
]
```

Or in Xcode:
1. File > Add Package Dependencies
2. Enter the package URL: `https://github.com/no-problem-dev/swift-cached-remote-image.git`
3. Select version: `1.1.5` or later

## Quick Start

The simplest usage:

```swift
import SwiftUI
import CachedRemoteImage

CachedRemoteImage(
    source: .url(URL(string: "https://example.com/image.jpg")!)
)
```

This handles image loading, caching, and default loading indicator automatically.

## Usage

### Basic Example

```swift
import SwiftUI
import CachedRemoteImage

struct ContentView: View {
    var body: some View {
        CachedRemoteImage(
            source: .url(URL(string: "https://example.com/image.jpg")!)
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        } placeholder: {
            ProgressView()
        }
    }
}
```

### Load from URL String

```swift
CachedRemoteImage(
    source: .urlString("https://example.com/image.jpg")
) { image in
    image.resizable()
}
```

### ImageSource Options

```swift
// 1. From a URL object
let url = URL(string: "https://example.com/image.jpg")!
CachedRemoteImage(source: .url(url))

// 2. From a URL string (automatically converted)
CachedRemoteImage(source: .urlString("https://example.com/image.jpg"))

// 3. From an image ID (fetches resource via ImageService)
CachedRemoteImage(source: .imageId("img_12345"))
```

> **Note**: `.imageId` requires `ImageService` to be injected into the environment.

### Using ImageService with Image ID

```swift
import APIClient
import CachedRemoteImage

@main
struct MyApp: App {
    let imageService: ImageService

    init() {
        let apiClient = APIClientImpl(baseURL: URL(string: "https://api.example.com")!)
        imageService = ImageServiceImpl(
            apiClient: apiClient,
            imagesPath: "/images",
            maxResourceCacheSize: 100
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .imageService(imageService)
        }
    }
}

struct ImageView: View {
    let imageId: String

    var body: some View {
        CachedRemoteImage(
            source: .imageId(imageId)
        ) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}
```

## Cache Configuration

### Resource Cache Size

```swift
let imageService = ImageServiceImpl(
    apiClient: apiClient,
    imagesPath: "/images",
    maxResourceCacheSize: 200  // up to 200 resource entries
)
```

### Clearing Cache

```swift
// Clear resource cache
await imageService.clearResourceCache()

// Clear image data cache
await imageService.clearImageCache()

// Get disk cache size
let cacheSize = await imageService.diskCacheSize()
print("Current cache size: \(cacheSize) bytes")
```

### Per-Image Configuration

```swift
CachedRemoteImage(
    source: .url(imageURL),
    configuration: CachedRemoteImageConfiguration(
        cachePolicy: .metadataOnly,
        retryPolicy: .exponentialBackoff(maxRetries: 3)
    )
) { image in
    image.resizable()
}
```

Available options:

- **cachePolicy**: `.all` (default), `.metadataOnly`, `.imageOnly`, `.none`
- **retryPolicy**: `.none` (default), `.fixed(count:)`, `.exponentialBackoff(maxRetries:, baseDelay:)`

## License

This project is released under the MIT License. See the [LICENSE](LICENSE) file for details.

## Support

For bug reports or feature requests, please open an [issue on GitHub](https://github.com/no-problem-dev/swift-cached-remote-image/issues).
