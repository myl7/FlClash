import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';

import 'common.dart';

extension PackageInfoExtension on PackageInfo {
  String get ua => [
    '$appName/v$version',
    'clash-verge',
    'Platform/${Platform.operatingSystem}',
  ].join(' ');
}

final _versionPattern = RegExp(
  r'^(\d+)(?:\.(\d+))?(?:\.(\d+))?'
  r'(?:-myl7\.(\d+))?'
  r'(?:-(rc|beta|alpha)(\d+)?)?'
  r'(?:\+(\d+))?$',
);

const _stageRank = {'alpha': 0, 'beta': 1, 'rc': 2};

/// Compares app versions in the fork grammar,
/// `MAJOR.MINOR.PATCH[-myl7.<M>][-<stage><K>][+<build>]`, where myl7 is the
/// fixed fork identifier (only `<M>` counts up) and the stage is rc, beta or
/// alpha. Semver core first, then the fork release counter (a version
/// without it sorts below the fork line, like the changelog tool orders
/// tags), then the stage, where a final outranks any staged tag and stages
/// order alpha < beta < rc, then the build number. A value outside the
/// grammar compares by raw string, so the update check never throws - the
/// previous splitter crashed with a FormatException on every -myl7.M
/// version pair that shared its major and minor.
int compareVersions(String version1, String version2) {
  final v1 = _versionPattern.firstMatch(version1.trim());
  final v2 = _versionPattern.firstMatch(version2.trim());
  if (v1 == null || v2 == null) {
    return version1.trim().compareTo(version2.trim());
  }

  int zeroWhenAbsent(RegExpMatch m, int group) =>
      m.group(group) == null ? 0 : int.parse(m.group(group)!);
  int belowForkLineWhenAbsent(RegExpMatch m, int group) =>
      m.group(group) == null ? -1 : int.parse(m.group(group)!);

  for (var group = 1; group <= 3; group++) {
    final result = zeroWhenAbsent(
      v1,
      group,
    ).compareTo(zeroWhenAbsent(v2, group));
    if (result != 0) return result;
  }
  final byForkRelease = belowForkLineWhenAbsent(
    v1,
    4,
  ).compareTo(belowForkLineWhenAbsent(v2, 4));
  if (byForkRelease != 0) return byForkRelease;
  final stage1 = v1.group(5);
  final stage2 = v2.group(5);
  if (stage1 != null || stage2 != null) {
    if (stage1 == null) return 1;
    if (stage2 == null) return -1;
    final result = _stageRank[stage1]!.compareTo(_stageRank[stage2]!);
    if (result != 0) return result;
  }
  final byStageNum = zeroWhenAbsent(v1, 6).compareTo(zeroWhenAbsent(v2, 6));
  if (byStageNum != 0) return byStageNum;
  return zeroWhenAbsent(v1, 7).compareTo(zeroWhenAbsent(v2, 7));
}

const releaseNotesBeginMarker = '<!-- flclash:changelog:begin -->';
const releaseNotesEndMarker = '<!-- flclash:changelog:end -->';

List<String> parseReleaseBody(String? body) {
  if (body == null) return [];
  final regex = RegExp(r'^[ \t]*-[ \t]+(.*)$', multiLine: true);
  return regex
      .allMatches(scopeReleaseNotes(body))
      .map((match) => match.group(1)?.trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

String scopeReleaseNotes(String body) {
  final begin = body.indexOf(releaseNotesBeginMarker);
  if (begin < 0) return body;
  final start = begin + releaseNotesBeginMarker.length;
  final end = body.indexOf(releaseNotesEndMarker, start);
  return end < 0 ? body.substring(start) : body.substring(start, end);
}
