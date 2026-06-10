/// Sentinel marker for nullable copyWith parameters.
///
/// Use with [copyWithNullable] to distinguish "not provided" from
/// "explicitly set to null" in hand-written copyWith methods.
///
/// ```dart
/// MyState copyWith({Object? nullableField = CopyWithSentinel.instance}) {
///   return MyState(
///     nullableField: copyWithNullable(nullableField, this.nullableField),
///   );
/// }
/// ```
class CopyWithSentinel {
  const CopyWithSentinel._();
  static const instance = CopyWithSentinel._();
}

/// Resolves a nullable copyWith parameter:
/// - Returns [current] if [value] is [CopyWithSentinel.instance] (not provided).
/// - Otherwise returns [value] cast to `T?`.
T? copyWithNullable<T>(Object? value, T? current) =>
    identical(value, CopyWithSentinel.instance) ? current : value as T?;
