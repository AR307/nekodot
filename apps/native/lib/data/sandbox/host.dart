import 'dart:convert';

import 'package:http/http.dart' as http;

import 'daytona.dart';
import 'vercel.dart';

/// How big a sandbox is. Both sizes fit Daytona (up to 4 CPUs and 8 GB) and
/// Vercel Sandbox (memory must be 2 GB per CPU).
enum SandboxSize {
  standard(cpu: 2, memoryGb: 4),
  large(cpu: 4, memoryGb: 8);

  final int cpu, memoryGb;
  const SandboxSize({required this.cpu, required this.memoryGb});
}

/// Where a sandbox stands, the same words for both providers.
enum SandboxState { running, starting, stopped, gone, failed }

class CommandResult {
  final int exitCode;
  final String output;
  const CommandResult(this.exitCode, this.output);
}

/// A provider refused a request; [message] is its own words.
class SandboxError implements Exception {
  final String message;
  final int status;
  SandboxError(this.message, [this.status = 0]);
  @override
  String toString() => message;
}

/// A cloud sandbox provider, called directly from the app with the user's own
/// key. A sandbox is named by the id its provider gives it.
abstract class SandboxHost {
  String get provider;

  /// Makes a sandbox and returns its id once it can run commands.
  Future<String> create(String name, SandboxSize size);
  Future<SandboxState> state(String id);

  /// Brings a stopped sandbox back and returns once it can run commands.
  Future<void> wake(String id);

  /// Runs a short bash script as root and waits for it.
  Future<CommandResult> exec(String id, String script);

  /// Starts a bash script as root that keeps running after this returns.
  Future<void> launch(String id, String script);
  Future<void> delete(String id);
}

/// The host for a provider and the credentials saved for it.
SandboxHost sandboxHost(
  String provider,
  Map<String, String> credentials, {
  http.Client? transport,
  Duration poll = const Duration(seconds: 3),
}) => switch (provider) {
  'daytona' => DaytonaHost(
    apiKey: credentials['apiKey']!,
    transport: transport,
    poll: poll,
  ),
  'vercel' => VercelHost(
    token: credentials['token']!,
    teamId: credentials['teamId']!,
    projectId: credentials['projectId']!,
    session: Duration(minutes: int.parse(credentials['sessionMinutes']!)),
    transport: transport,
    poll: poll,
  ),
  _ => throw ArgumentError('Unknown sandbox provider $provider'),
};

/// One JSON request to a provider: its error message on failure, its body on
/// success.
Future<dynamic> providerRequest(
  http.Client transport,
  String method,
  Uri url,
  Map<String, String> headers, [
  Object? body,
]) async {
  final request = http.Request(method, url)..headers.addAll(headers);
  if (body != null) {
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(body);
  }
  final response = await transport
      .send(request)
      .then(http.Response.fromStream)
      .timeout(const Duration(seconds: 60));
  if (response.statusCode >= 400) {
    throw SandboxError(_message(response), response.statusCode);
  }
  return response.body.isEmpty ? null : jsonDecode(response.body);
}

String _message(http.Response response) {
  try {
    final body = jsonDecode(response.body);
    final error = body is Map ? (body['error'] ?? body) : body;
    final message = error is Map ? error['message'] : error;
    if (message is String && message.isNotEmpty) return message;
  } on FormatException {
    // Not JSON: the status says enough.
  }
  return 'HTTP ${response.statusCode}';
}

/// [script] as one argument for `bash -c`.
String shellQuote(String script) => "'${script.replaceAll("'", "'\\''")}'";
