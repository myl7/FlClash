<div align="center">

# FlClash-myl7

个人维护的 [FlClash](https://github.com/chen08209/FlClash) fork，只给我自己的安卓设备用。

[![Release](https://img.shields.io/github/v/release/myl7/FlClash?style=flat-square&label=release)](https://github.com/myl7/FlClash/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/myl7/FlClash/total?style=flat-square&logo=github)](https://github.com/myl7/FlClash/releases)
[![License](https://img.shields.io/github/license/myl7/FlClash?style=flat-square)](LICENSE)

</div>

## 这个 fork 改了什么

- **修复 `tailscale` 出站的核心**：带上 wildcard proxy-dialer 修复（[mihomo#3142](https://github.com/MetaCubeX/mihomo/issues/3142)），tailscale 出站在 `dialer-proxy` 下正常工作，并增加 tsnet 预启动和拨号前的会话预热。
- **state_dir 管理**：备份与恢复携带配置声明的 state 目录（任何带 `state-dir` 的出站类型，不限 tailscale）；配置的更多菜单可以导入、导出、删除它的 state_dir。恢复时只要任一方配置声明了同名目录就一并带回。
- **去掉首启免责声明门禁**：声明保留在工具页随时可读，启动直接进应用。
- **仅发布安卓版**：CI 仍检查全平台代码，但只出安卓 APK，发布说明也只列安卓下载。

## 发布

- 形如 `v0.9.0-myl7.1` 的 tag 在 [releases](https://github.com/myl7/FlClash/releases) 页发布签名 APK；应用内更新检查指向本仓库。
- `-rc` tag 是测试版，与正式版并行安装（`com.follow.clash.dev`，标签 `FlClash-myl7-dev`），同一签名、可原位升级。

## 鸣谢

基于 chen08209 的 [FlClash](https://github.com/chen08209/FlClash) 与 [Clash.Meta](https://github.com/MetaCubeX/mihomo) 内核。重活都是上游干的，本 fork 只带以上改动。

## 构建

与上游一致：`flutter pub get` 后 `dart setup.dart android`（见 `.agents/commands.md`）。CI 在每个 tag 上构建。

## 许可

同上游，见 [LICENSE](LICENSE)。
