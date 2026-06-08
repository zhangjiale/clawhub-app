/// A simple sealed-class async state, independent of Riverpod.
///
/// Used by ViewModels and other non-Riverpod modules to expose
/// loading / data / error states reactively without coupling to
/// any state-management framework.
///
/// Named to avoid collision with Riverpod's own AsyncValue types.
sealed class LoadState<T> {
  const LoadState();
}

class LoadInProgress<T> extends LoadState<T> {
  const LoadInProgress();
}

class LoadData<T> extends LoadState<T> {
  final T value;
  const LoadData(this.value);
}

class LoadError<T> extends LoadState<T> {
  final Object error;
  final StackTrace? stackTrace;
  const LoadError(this.error, [this.stackTrace]);
}
