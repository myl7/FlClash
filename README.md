<div align="center">

# FlClash-myl7

A personally maintained fork of [FlClash](https://github.com/chen08209/FlClash) for my own Android devices.

[![Release](https://img.shields.io/github/v/release/myl7/FlClash?style=flat-square&label=release)](https://github.com/myl7/FlClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/myl7/FlClash/total?style=flat-square&logo=github)](https://github.com/myl7/FlClash/releases)
[![License](https://img.shields.io/github/license/myl7/FlClash?style=flat-square)](LICENSE)

</div>

## What this fork changes

- **Fixed core for the `tailscale` outbound**: carries the wildcard proxy-dialer fix ([mihomo#3142](https://github.com/MetaCubeX/mihomo/issues/3142)) so a tailscale outbound keeps working behind `dialer-proxy`, plus an eager tsnet start and a session warmup before dials.
- **state_dir management**: backups and restores carry the state directories profiles declare — any outbound type with a `state-dir`, not only tailscale — and each profile's more menu can import, export or delete its state_dir. A restore brings a directory back when any profile in play declares it.
- **No first-launch disclaimer gate**: the statement stays readable from the tools page; startup opens straight into the app.
- **Android-only releases**: CI still checks all platforms' code, but only Android APKs are published and the release notes list Android downloads only.

## Releases

- Tags like `v0.9.0-myl7.1` publish signed APKs on the [releases](https://github.com/myl7/FlClash/releases) page; the in-app updater tracks this repository.
- `-rc` tags are test builds that install beside the release (`com.follow.clash.dev`, labelled `FlClash-myl7-dev`) under the same signing key, so they upgrade in place.

## Credits

Based on [FlClash](https://github.com/chen08209/FlClash) by chen08209 and the [Clash.Meta](https://github.com/MetaCubeX/mihomo) core. Upstream does the heavy lifting; this fork only carries the changes above.

## Building

Same as upstream: `flutter pub get`, then `dart setup.dart android` (see `.agents/commands.md`). CI builds on every tag.

## License

As upstream. See [LICENSE](LICENSE).
