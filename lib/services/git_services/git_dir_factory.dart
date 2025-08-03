import 'package:git/git.dart' show GitDir;

typedef GitDirFactory = Future<GitDir> Function(String path);

Future<GitDir> defaultGitDirFactory(String path) {
  return GitDir.fromExisting(path);
}