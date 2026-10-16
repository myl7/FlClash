part of '../action.dart';

const stateDirManifestName = 'manifest.json';

typedef StateDirArchive = ({bool isBackup, Set<String> dirs});

/// The profile's declared state directories, cached for the profile menu.
@Riverpod(name: 'profileStateDirsProvider')
Future<Set<String>> profileStateDirs(Ref ref, int profileId) async {
  final file = File(await appPath.getProfilePath(profileId.toString()));
  if (!await file.exists()) {
    return const {};
  }
  try {
    return stateDirsOfDocument(loadPlainYaml(await file.readAsString()));
  } on YamlException {
    return const {};
  }
}

@Riverpod(keepAlive: true)
class StateDirAction extends _$StateDirAction {
  @override
  void build() {}

  Future<Uint8List?> exportArchive(Profile profile) async {
    final homeDirPath = await appPath.homeDirPath;
    final filesByDir = <String, List<String>>{};
    for (final dir in await dirsOf(profile)) {
      final files = await filesUnderEntry(homeDirPath, dir);
      if (files.isNotEmpty) {
        filesByDir[dir] = files;
      }
    }
    if (filesByDir.isEmpty) {
      return null;
    }
    final archivePath = await appPath.tempFilePath;
    final encoder = ZipFileEncoder()..create(archivePath);
    try {
      encoder.addArchiveFile(
        ArchiveFile.string(
          stateDirManifestName,
          json.encode({'version': 1, 'stateDirs': filesByDir.keys.toList()}),
        ),
      );
      for (final files in filesByDir.values) {
        for (final file in files) {
          await encoder.addFile(
            File(BackupEntries.resolve(homeDirPath, file)),
            file,
          );
        }
      }
    } finally {
      await encoder.close();
    }
    final bytes = await File(archivePath).readAsBytes();
    await File(archivePath).delete();
    return bytes;
  }

  /// A state_dir export carries its directories in a manifest; a full backup
  /// carries them alongside its own files, and the caller's declared
  /// directories say which entries to take from it.
  Future<StateDirArchive?> inspect(String archivePath) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(await File(archivePath).readAsBytes());
    } on FormatException {
      return null;
    }
    final names = archive.files
        .where((file) => file.isFile)
        .map((file) => file.name)
        .toSet();
    if (names.contains(configJsonName)) {
      return (isBackup: true, dirs: const <String>{});
    }
    if (!names.contains(stateDirManifestName)) {
      return null;
    }
    final Object? manifest;
    try {
      manifest = json.decode(_manifestContent(archive));
    } on FormatException {
      return null;
    }
    final declared = switch (manifest) {
      final Map<String, Object?> map when map['stateDirs'] is List<Object?> =>
        (map['stateDirs'] as List<Object?>).whereType<String>(),
      _ => const Iterable<String>.empty(),
    };
    return (isBackup: false, dirs: declared.toSet());
  }

  /// Copies the archive's [mapping] directories into the home directory and
  /// returns how many files landed there.
  Future<int> apply(String archivePath, Map<String, String> mapping) async {
    final archive = ZipDecoder().decodeBytes(
      await File(archivePath).readAsBytes(),
    );
    final homeDirPath = await appPath.homeDirPath;
    var count = 0;
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final entry = _stagedEntryName(file.name);
      if (entry == null) {
        continue;
      }
      final source = entry.key;
      final target = mapping[source];
      if (target == null) {
        continue;
      }
      final destination = File(
        BackupEntries.resolve(homeDirPath, '$target/${entry.value}'),
      );
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(file.content as List<int>);
      count++;
    }
    return count;
  }

  Future<void> erase(Profile profile) async {
    final homeDirPath = await appPath.homeDirPath;
    for (final dir in await dirsOf(profile)) {
      await Directory(
        BackupEntries.resolve(homeDirPath, dir),
      ).safeDelete(recursive: true);
    }
  }

  Future<void> restartCoreIfNeeded() async {
    if (ref.read(coreStatusProvider) == CoreStatus.disconnected) {
      return;
    }
    await ref.read(coreActionProvider.notifier).restartCore();
  }

  Future<Set<String>> dirsOf(Profile profile) async {
    final file = await profile.file;
    if (!await file.exists()) {
      return const {};
    }
    try {
      return stateDirsOfDocument(loadPlainYaml(await file.readAsString()));
    } on YamlException {
      return const {};
    }
  }

  String _manifestContent(Archive archive) {
    final manifest = archive.files.singleWhere(
      (file) => file.name == stateDirManifestName,
    );
    return String.fromCharCodes(manifest.content as List<int>);
  }

  MapEntry<String, String>? _stagedEntryName(String name) {
    final normalized = posix.normalize(name.replaceAll('\\', '/'));
    final separator = normalized.indexOf('/');
    if (separator <= 0 || normalized.startsWith('../')) {
      return null;
    }
    return MapEntry(
      normalized.substring(0, separator),
      normalized.substring(separator + 1),
    );
  }
}
