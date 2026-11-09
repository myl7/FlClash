import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/changelog/git.dart';

void main() {
  group('VersionTag.tryParse', () {
    test('parses upstream bare and pre tags', () {
      final bare = VersionTag.tryParse('v0.9.3');
      expect(bare?.version, '0.9.3');
      expect(bare?.stage, isNull);

      final pre = VersionTag.tryParse('v0.9.3-pre.1');
      expect(pre?.pre, 1);
      expect(pre?.isPrerelease, isTrue);
    });

    test('parses fork finals as releases of their own', () {
      final tag = VersionTag.tryParse('v0.9.3-myl7.1');
      expect(tag?.mylPatch, 1);
      expect(tag?.stage, isNull);
      expect(tag?.isPrerelease, isFalse);
    });

    test('parses fork staged prereleases', () {
      final rc = VersionTag.tryParse('v0.9.3-myl7.2-rc1');
      expect(rc?.stage, 'rc');
      expect(rc?.stageNum, 1);

      final beta = VersionTag.tryParse('v0.9.4-myl7.1-beta2');
      expect(beta?.stage, 'beta');
      expect(beta?.stageNum, 2);

      final alpha = VersionTag.tryParse('v0.9.4-myl7.1-alpha1');
      expect(alpha?.stage, 'alpha');
      expect(alpha?.stageNum, 1);

      final bare = VersionTag.tryParse('v0.9.4-myl7.1-rc');
      expect(bare?.stage, 'rc');
      expect(bare?.stageNum, isNull);
    });

    test('rejects the dotted stage form and foreign tags', () {
      expect(VersionTag.tryParse('v0.9.3-myl7.2-rc.1'), isNull);
      expect(VersionTag.tryParse('v0.9.3-myl7'), isNull);
      // myl7 is the fork identifier, not a counter: another mylN is foreign.
      expect(VersionTag.tryParse('v0.9.3-myl8.1'), isNull);
      expect(VersionTag.tryParse('backup-pre-squash-20261019'), isNull);
    });
  });

  group('VersionTag.compareTo', () {
    VersionTag parse(String name) => VersionTag.tryParse(name)!;

    test('orders a fork line by semver precedence', () {
      final line = [
        parse('v0.9.3-myl7.2-rc2'),
        parse('v0.9.3-myl7.2'),
        parse('v0.9.3-myl7.2-rc1'),
        parse('v0.9.3-myl7.1'),
      ]..sort();
      expect(line.map((t) => t.name).toList(), [
        'v0.9.3-myl7.1',
        'v0.9.3-myl7.2-rc1',
        'v0.9.3-myl7.2-rc2',
        'v0.9.3-myl7.2',
      ]);
    });

    test('orders stages alpha, beta, rc', () {
      final stages = [
        parse('v0.9.4-myl7.1-rc1'),
        parse('v0.9.4-myl7.1-alpha1'),
        parse('v0.9.4-myl7.1-beta1'),
      ]..sort();
      expect(stages.map((t) => t.stage).toList(), ['alpha', 'beta', 'rc']);
    });

    test('ranks a fork final above the bare upstream tag it partitions', () {
      // Not strict semver precedence (a prerelease-slot suffix would rank
      // below the release): the changelog orders by release history, and the
      // fork release on top of an upstream tag is the newer partition.
      expect(parse('v0.9.3-myl7.1').compareTo(parse('v0.9.3')), greaterThan(0));
    });
  });
}
