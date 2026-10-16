import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:riverpod/riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

Profile _profile(int id, String label) => Profile(
  id: id,
  label: label,
  autoUpdateDuration: Duration.zero,
  extendType: ExtendType.standard,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database testDatabase;
  late Directory home;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'version': 1});
    await AppLocalizations.load(const Locale('en'));
    home = Directory.systemTemp.createTempSync('flclash-state-dir-');
    AppPath.supportDirectory = () async => home;
    AppPath.temporaryDirectory = () async => home;
    AppPath.cacheDirectory = () async => home;
    AppPath.downloadDirectory = () async => home;
  });

  tearDownAll(() {
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  setUp(() {
    testDatabase = Database(NativeDatabase.memory());
    database = testDatabase;
  });

  tearDown(() async {
    await testDatabase.close();
  });

  ProviderContainer containerOf() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  StateDirAction actionOf(ProviderContainer container) =>
      container.read(stateDirActionProvider.notifier);

  Future<Profile> seedProfile() async {
    final profile = _profile(1, 'With state');
    await testDatabase.profilesDao.putAll([profile.toCompanion(0)]);
    final file = File(await appPath.getProfilePath('1'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        'proxies:\n'
        '  - name: TAILNET\n'
        '    type: tailscale\n'
        '    state-dir: ./ts-state\n',
      );
    addTearDown(file.deleteSync);
    return profile;
  }

  test('export packs the declared directories and a manifest', () async {
    final profile = await seedProfile();
    final identity = File(join(home.path, 'ts-state', 'tailscaled.state'))
      ..createSync(recursive: true)
      ..writeAsStringSync('identity');

    final bytes = await actionOf(containerOf()).exportArchive(profile);

    final archive = ZipDecoder().decodeBytes(bytes!);
    final names = archive.files.map((file) => file.name).toSet();
    expect(names, containsAll(['manifest.json', 'ts-state/tailscaled.state']));
    final manifest = json.decode(
      String.fromCharCodes(
        archive.files
                .singleWhere((file) => file.name == 'manifest.json')
                .content
            as List<int>,
      ),
    );
    expect(manifest['stateDirs'], ['ts-state']);
    identity.deleteSync();
  });

  test('export without state data yields null', () async {
    final profile = await seedProfile();

    expect(await actionOf(containerOf()).exportArchive(profile), isNull);
  });

  test('inspect tells a full backup from a state_dir export', () async {
    final archivePath = join(home.path, 'backup-like.zip');
    final encoder = ZipFileEncoder()..create(archivePath);
    encoder.addArchiveFile(
      ArchiveFile.string(configJsonName, json.encode({'version': 1})),
    );
    encoder.addArchiveFile(
      ArchiveFile.string('ts-state/tailscaled.state', 'identity'),
    );
    await encoder.close();
    final backup = await actionOf(containerOf()).inspect(archivePath);
    expect(backup, isNotNull);
    expect(backup!.isBackup, isTrue);

    final blobPath = join(home.path, 'blob-like.zip');
    encoder
      ..create(blobPath)
      ..addArchiveFile(
        ArchiveFile.string(
          stateDirManifestName,
          json.encode({
            'version': 1,
            'stateDirs': ['ts-state'],
          }),
        ),
      )
      ..addArchiveFile(
        ArchiveFile.string('ts-state/tailscaled.state', 'identity'),
      );
    await encoder.close();

    final blob = await actionOf(containerOf()).inspect(blobPath);
    expect(blob, isNotNull);
    expect(blob!.isBackup, isFalse);
    expect(blob.dirs, {'ts-state'});
  });

  test('apply lands the archive files in the mapped directories', () async {
    final archivePath = join(home.path, 'rename-source.zip');
    final encoder = ZipFileEncoder()..create(archivePath);
    encoder.addArchiveFile(
      ArchiveFile.string('other-dir/tailscaled.state', 'identity'),
    );
    await encoder.close();

    final count = await actionOf(
      containerOf(),
    ).apply(archivePath, {'other-dir': 'ts-state'});

    expect(count, 1);
    expect(
      File(join(home.path, 'ts-state', 'tailscaled.state')).readAsStringSync(),
      'identity',
    );
  });

  test('erase removes the declared directories', () async {
    final profile = await seedProfile();
    final identity = Directory(join(home.path, 'ts-state'))
      ..createSync(recursive: true);
    File(join(identity.path, 'tailscaled.state')).writeAsStringSync('x');

    await actionOf(containerOf()).erase(profile);

    expect(identity.existsSync(), isFalse);
  });
}
