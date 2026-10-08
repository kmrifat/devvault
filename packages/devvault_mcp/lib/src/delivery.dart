import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'secure_file.dart';

/// A delivery the helper refuses before asking anyone (a bad path, a file
/// it won't overwrite). The message is for the agent and holds no value.
class DeliveryError implements Exception {
  const DeliveryError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Checks a target path before the user is asked: absolute, in a folder
/// that exists, not a folder itself, and only replaced when [overwrite].
void checkTarget(String path, {required bool overwrite}) {
  if (!path.startsWith('/')) {
    throw const DeliveryError('path must be absolute');
  }
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.directory) {
    throw const DeliveryError('path is a folder');
  }
  if (type != FileSystemEntityType.notFound && !overwrite) {
    throw const DeliveryError(
      'the file exists; pass overwrite: true to replace it',
    );
  }
  if (!Directory(File(path).parent.path).existsSync()) {
    throw const DeliveryError("the file's folder doesn't exist");
  }
}

/// Writes [bytes] to [path], readable only by this user (0600).
Future<void> writeSecretFile(String path, List<int> bytes) =>
    writePrivateFile(File(path), bytes);

final _envName = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

/// Whether [name] works as an environment variable name.
bool isEnvName(String name) => _envName.hasMatch(name);

/// Sets [vars] in the dotenv file at [path] (0600): existing lines for
/// those names are replaced in place, every other line is kept as it was,
/// and new names are appended.
Future<void> writeEnvFile(String path, Map<String, String> vars) async {
  final file = File(path);
  final lines = file.existsSync() ? file.readAsLinesSync() : <String>[];
  final pending = Map.of(vars);
  final assignment = RegExp(r'^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=');
  final out = <String>[
    for (final line in lines)
      if (assignment.firstMatch(line) case final m?
          when pending.containsKey(m[2]))
        '${m[1] ?? ''}${m[2]}=${dotenvValue(pending.remove(m[2])!)}'
      else
        line,
    for (final MapEntry(:key, :value) in pending.entries)
      '$key=${dotenvValue(value)}',
  ];
  await writePrivateFile(file, utf8.encode('${out.join('\n')}\n'));
}

/// [value] as a dotenv value: bare when it's plain, otherwise in double
/// quotes with `\`, `"`, `$` and newlines escaped.
String dotenvValue(String value) {
  if (RegExp(r'^[A-Za-z0-9_./:@+=,-]*$').hasMatch(value)) return value;
  final escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll(r'$', r'\$')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
  return '"$escaped"';
}

/// Replaces every secret value in a command's output with
/// `[redacted:NAME]`, so what goes back to the agent never holds one.
///
/// Values shorter than [minLength] are left alone: redacting `1` or `ok`
/// everywhere would wreck the output and protect nothing. Each line of a
/// multi-line value (a PEM key) is redacted on its own too.
class Redactor {
  Redactor(Map<String, String> values, {this.minLength = 4}) {
    final pairs = <(String, String)>[];
    for (final MapEntry(key: name, :value) in values.entries) {
      pairs.add((value, name));
      if (value.contains('\n')) {
        for (final line in value.split(RegExp(r'\r?\n'))) {
          if (line.trim().length >= 8) pairs.add((line.trim(), name));
        }
      }
    }
    _pairs = [
      for (final p in pairs)
        if (p.$1.length >= minLength) p,
    ]..sort((a, b) => b.$1.length.compareTo(a.$1.length));
  }

  final int minLength;
  late final List<(String, String)> _pairs;

  String redact(String text) {
    var out = text;
    for (final (value, name) in _pairs) {
      out = out.replaceAll(value, '[redacted:$name]');
    }
    // Output that was cut off may end in the first part of a value.
    for (final (value, name) in _pairs) {
      for (var k = value.length - 1; k >= minLength; k--) {
        if (out.endsWith(value.substring(0, k))) {
          out = '${out.substring(0, out.length - k)}[redacted:$name]';
          break;
        }
      }
    }
    return out;
  }
}

/// What a command run with secrets returned, already redacted.
class CommandResult {
  const CommandResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
  });

  final int? exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  Map<String, Object?> toJson() => {
    'exit_code': exitCode,
    'timed_out': timedOut,
    'stdout': stdout,
    'stderr': stderr,
  };
}

/// Runs [command] with `/bin/sh -c` in [cwd], with [env] added to this
/// process's environment, and returns its output with every value in
/// [env] redacted. Output is redacted as a whole, after the command ends,
/// so a value split across reads is still caught; each stream keeps its
/// last [maxOutput] characters.
Future<CommandResult> runWithSecrets(
  String command, {
  required Map<String, String> env,
  String? cwd,
  Duration timeout = const Duration(minutes: 5),
  int maxOutput = 20000,
}) async {
  final process = await Process.start(
    '/bin/sh',
    ['-c', command],
    workingDirectory: cwd,
    environment: env,
  );
  final out = BytesBuilder(copy: false), err = BytesBuilder(copy: false);
  const cap = 4 * 1024 * 1024;
  final reading = Future.wait([
    process.stdout.forEach((b) {
      if (out.length < cap) out.add(b);
    }),
    process.stderr.forEach((b) {
      if (err.length < cap) err.add(b);
    }),
  ]);
  var timedOut = false;
  int? exitCode;
  try {
    exitCode = await process.exitCode.timeout(timeout);
  } on TimeoutException {
    timedOut = true;
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
  }
  await reading;
  final redactor = Redactor(env);
  String tidy(BytesBuilder b) {
    final text = redactor.redact(
      utf8.decode(b.takeBytes(), allowMalformed: true),
    );
    return text.length <= maxOutput
        ? text
        : '…${text.substring(text.length - maxOutput)}';
  }

  return CommandResult(
    exitCode: timedOut ? null : exitCode,
    stdout: tidy(out),
    stderr: tidy(err),
    timedOut: timedOut,
  );
}
