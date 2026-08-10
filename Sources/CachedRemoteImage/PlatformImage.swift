#if canImport(UIKit)
import UIKit

/// The platform's image type: `UIImage` on iOS, `NSImage` on macOS.
///
/// It is not `Sendable` on macOS, which is why the calls that hand images in and out of the
/// memory cache are isolated to the main actor.
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit

/// The platform's image type: `UIImage` on iOS, `NSImage` on macOS.
///
/// It is not `Sendable` on macOS, which is why the calls that hand images in and out of the
/// memory cache are isolated to the main actor.
public typealias PlatformImage = NSImage
#endif
