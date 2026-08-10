import Foundation

/// How many times a failed fetch is retried, and how long it waits in between.
///
/// Only fetches are retried. Bytes that arrive but cannot be decoded
/// (``ImageLoadError/notAnImage(byteCount:)``) are not, since decoding the same bytes again gives
/// the same answer. Pass a policy to ``ImageLibraryConfiguration`` and it governs every fetch the
/// library makes, including the ones that never go through a view.
///
/// ## Examples
/// ```swift
/// // No retries (the default)
/// let library = try ImageLibrary(transport: transport)
///
/// // Three retries, with no waiting in between
/// let library = try ImageLibrary(
///     transport: transport,
///     configuration: ImageLibraryConfiguration(retryPolicy: .fixed(count: 3))
/// )
///
/// // Exponential backoff, which is what an unreliable network wants
/// let library = try ImageLibrary(transport: transport, configuration: .withRetry)
/// ```
public enum RetryPolicy: Equatable, Sendable {
    /// Give up on the first failure.
    case none

    /// Retry immediately, with no wait between attempts.
    ///
    /// Suits a transport whose failures clear on their own. For network errors prefer
    /// ``exponentialBackoff(maxRetries:baseDelay:)``: retrying instantly only adds load to a
    /// server that may already be struggling.
    ///
    /// - Parameter count: How many times to retry after the first failure.
    case fixed(count: Int)

    /// Retry with a wait that doubles after every attempt.
    ///
    /// The wait before retry *n* is `baseDelay * 2^n`, so a one-second base waits one, two and
    /// then four seconds. The task is suspended for that time, and cancelling it ends the
    /// retrying.
    ///
    /// - Parameters:
    ///   - maxRetries: How many times to retry after the first failure.
    ///   - baseDelay: Seconds to wait before the first retry.
    case exponentialBackoff(maxRetries: Int, baseDelay: TimeInterval = 1.0)

    /// How many retries this policy allows after the first failure. Negative counts read as zero.
    internal var maxRetries: Int {
        switch self {
        case .none:
            return 0
        case .fixed(let count):
            return max(0, count)
        case .exponentialBackoff(let maxRetries, _):
            return max(0, maxRetries)
        }
    }

    /// The seconds to wait before a given retry attempt.
    ///
    /// - Parameter attemptNumber: The zero-based index of the retry about to be made.
    /// - Returns: The delay in seconds, or zero for the policies that do not wait.
    internal func delay(for attemptNumber: Int) -> TimeInterval {
        switch self {
        case .none:
            return 0
        case .fixed:
            return 0
        case .exponentialBackoff(_, let baseDelay):
            return baseDelay * pow(2.0, Double(attemptNumber))
        }
    }
}
