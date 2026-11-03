import '../screen/bridge/frb_generated.dart';

Future<void>? _initialization;

/// Loads the Rust library once for both the screen viewer and owned local processes.
Future<void> ensureRust() => _initialization ??= RustLib.init();
