import 'dart:convert';
import 'dart:io' show ProcessResult, systemEncoding, Process;

// process_runner.dart
abstract class IProcessRunner {
  Future<ProcessResult> run(
      String executable,
      List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        Encoding? stdoutEncoding = systemEncoding, // systemEncoding из dart:io
        Encoding? stderrEncoding = systemEncoding,
      });
}

class ProcessRunner implements IProcessRunner {
  @override
  Future<ProcessResult> run(
      String executable,
      List<String> arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true,
        bool runInShell = false,
        Encoding? stdoutEncoding = systemEncoding,
        Encoding? stderrEncoding = systemEncoding,
      }) {
    return Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment,
      runInShell: runInShell,
      stdoutEncoding: stdoutEncoding,
      stderrEncoding: stderrEncoding,
    );
  }
}