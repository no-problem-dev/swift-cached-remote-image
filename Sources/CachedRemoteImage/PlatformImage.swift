#if canImport(UIKit)
import UIKit

/// iOS/macOS 両対応のプラットフォーム画像型。iOS では `UIImage`、macOS では `NSImage` が割り当てられる。
public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit

/// iOS/macOS 両対応のプラットフォーム画像型。iOS では `UIImage`、macOS では `NSImage` が割り当てられる。
public typealias PlatformImage = NSImage
#endif
