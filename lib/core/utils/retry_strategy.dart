/// Shared exponential-backoff retry strategy used across the codebase.
///
/// Encapsulates the `base * 2^attempt` formula with a configurable cap,
/// replacing the duplicated `_computeBackoff()` and agent-sync retry logic.
///
/// ## Predefined strategies
///
/// - [RetryStrategy.networkReconnect] — WebSocket reconnect (1s→2s→4s→8s→
///   16s→30s, infinite retries).
/// - [RetryStrategy.agentSync] — agent-list sync (5s→10s, max 3 attempts).
class RetryStrategy {
  /// Initial delay in seconds for attempt 0.
  final int baseDelaySeconds;

  /// Hard cap on delay in seconds.
  final int maxDelaySeconds;

  /// Maximum number of retries, or `null` for unlimited.
  ///
  /// A `maxAttempts` of _n_ means the operation will be tried at most _n_ times
  /// (1 initial + n-1 retries).  Pass `null` for infinite retries.
  final int? maxAttempts;

  const RetryStrategy({
    this.baseDelaySeconds = 1,
    this.maxDelaySeconds = 30,
    this.maxAttempts,
  });

  /// Exponential-backoff delay for the given attempt index (0-based).
  ///
  /// Formula: `min(maxDelay, baseDelay * 2^attempt)`.
  Duration delayForAttempt(int attempt) {
    var delay = baseDelaySeconds;
    for (int i = 0; i < attempt; i++) {
      delay *= 2;
      if (delay >= maxDelaySeconds) return Duration(seconds: maxDelaySeconds);
    }
    return Duration(seconds: delay);
  }

  /// Whether the given attempt index should be retried.
  bool shouldRetry(int attempt) {
    if (maxAttempts == null) return true;
    return attempt < maxAttempts!;
  }

  // ---------------------------------------------------------------------------
  // Predefined instances
  // ---------------------------------------------------------------------------

  /// Network-level WebSocket reconnect: exponential 1s→2s→4s→8s→16s→30s, no
  /// retry limit.
  static const networkReconnect = RetryStrategy(
    baseDelaySeconds: 1,
    maxDelaySeconds: 30,
  );

  /// Agent-list sync: 5s→10s, at most 3 attempts (1 initial + 2 retries).
  static const agentSync = RetryStrategy(
    baseDelaySeconds: 5,
    maxDelaySeconds: 10,
    maxAttempts: 3,
  );

  /// Network-level reconnect with a cap of 3 total attempts — 1 initial + 2
  /// retries (US-016 AC-3). Same backoff as [networkReconnect].
  /// `maxAttempts: 2` = 3 total per the field doc (1 initial + n-1 retries).
  static const networkReconnectLimited = RetryStrategy(
    baseDelaySeconds: 1,
    maxDelaySeconds: 30,
    maxAttempts: 2,
  );
}
