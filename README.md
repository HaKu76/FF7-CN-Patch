# FFVII GOG + FFNx 繁体中文与成就兼容候选

本仓库提供一个面向 GOG 版 FINAL FANTASY VII 的 FFNx 繁体中文兼容候选。它把汉化资源、FFNx 渲染运行时和 GOG Galaxy API 兼容桥放在独立的 `ff7\workingdir` 下，通过备份、哈希校验和回滚管理安装。

这是兼容候选，不是 GOG 或 Square Enix 官方组件。成就是否显示、同步和解锁取决于 GOG Galaxy 登录状态、游戏版本和实际游戏条件。发布时必须同时遵守 FFNx、汉化补丁、字体和第三方运行库的许可证与再分发许可。

> [!WARNING]
> **内置繁体中文补丁授权声明：**当前完整测试包内置的繁体中文补丁 v1.47 来源于 [ffsaga](https://www.youtube.com/@ffsaga)，其内置和再分发目前**未经补丁作者明确同意**。如补丁作者或相关权利人提出异议，本项目将从后续源码快照和发布包中移除内置繁体中文资源。语言包导入功能不会因此移除，用户仍可通过 `imports/language` 导入其自行合法取得并有权使用的兼容语言包。

## 快速使用

1. 将 `FF7-CN-Patch` 放在 GOG 游戏根目录，并确保它与 `FFVII.exe` 同级。
2. 右键 `安裝 繁體中文補丁.cmd`，选择“以管理员身份运行”。
3. 首次使用直接选择 `4`“一键安装并启动”；当前完整包已内置繁中语言包和 FFNx，不需要先导入。
4. 只想安装、不启动游戏时选择 `3`。
5. 安装成功后，直接双击 `启动 FFVII GOG 中文版.cmd`。该文件会复用已安装的哈希清单，不会每次重复安装。

菜单 `1` 和 `2` 是可选的模块更新入口，不是安装前置步骤：

| 菜单 | 导入目录 | 用途 |
| --- | --- | --- |
| `1` 导入/更新语言包 | `imports/language` | 替换内置语言包；游戏已经安装时会自动备份旧模块、回滚旧安装并重新应用新语言包。目录为空时只显示内置语言包状态并正常返回。 |
| `2` 导入/更新 FFNx | `imports/ffnx` | 替换内置 FFNx；目录为空时只显示内置 FFNx 版本并正常返回。 |

外部原始繁中包必须包含：

```text
files/direct
files/override
files/hext
files/mods
files/fonts/msjh_bd
```

规范语言模块也可以使用 `<language-id>/ff7/direct`、`override`、`hext`、`mods` 布局。Windows 自带的 `tar.exe` 负责解压 ZIP/RAR。校验失败不会删除导入源；如果游戏已经安装，导入器会在新模块校验通过后自动回滚旧安装并重新安装。只有整个更新流程成功后，对应导入目录内的源包或源目录才会自动清理。

## FFNx 模块与下载来源

当前完整包内置并验证的是 FFNx `1.24.2.26` x86。它来自 Julian Xhokaxhiu 维护的 FFNx 官方项目，许可证为 GNU GPL v3：

| 内容 | 地址 |
| --- | --- |
| 官方源码仓库 | <https://github.com/julianxhokaxhiu/FFNx> |
| 官方发布页 | <https://github.com/julianxhokaxhiu/FFNx/releases> |
| 官方最新稳定版 | <https://github.com/julianxhokaxhiu/FFNx/releases/latest> |
| 官方 Canary | <https://github.com/julianxhokaxhiu/FFNx/releases/tag/canary> |
| 已验证 `1.24.2.26` 对应源码提交 | <https://github.com/julianxhokaxhiu/FFNx/tree/7b7799027a02ce279a34e4ecc69bd8c676430a53> |
| 已验证源码 ZIP 快照 | <https://github.com/julianxhokaxhiu/FFNx/archive/7b7799027a02ce279a34e4ecc69bd8c676430a53.zip> |
| `1.24.2` 稳定版源码 | <https://github.com/julianxhokaxhiu/FFNx/archive/refs/tags/1.24.2.zip> |
| `1.24.2.0` 官方 Steam 构建 | <https://github.com/julianxhokaxhiu/FFNx/releases/download/1.24.2/FFNx-Steam-v1.24.2.0.zip> |

`1.24.2.26` 是当时 Canary 工作流产生的连续构建，不是 `1.24.2.0` 稳定包。官方 `canary` 标签和资产会随新构建移动，因此现在没有可保证不变的上游 `1.24.2.26` 二进制下载地址。根据二进制时间和上游 Git 历史，该构建对应提交 `7b779902...`（其父提交 `6f66eae1...` 是实际代码修复，`7b779902...` 只更新 Changelog）；上游已清理旧 Actions 运行，所以仓库同时保存精确版本与哈希作为追溯证据。本项目发布独立的 `FFNx-GOG-Runtime-Module-1.24.2.26-0.7.3.zip`，保存验收时使用的精确上游二进制、许可证、源码快照地址及 SHA-256；导入器在本地把 FFNx 的 Valve `steam_api.dll` SHA-1 白名单替换为本包 GOG 适配桥的 SHA-1。

FFNx 导入只接受包含 `AF3DN.P`、`AF4DN.P`、`FFNx.toml`、`COPYING.TXT` 的 FFNx-Steam 模块。当前候选锁定 `1.24.2.26` x86 及精确哈希；不要把未经回归测试的最新版直接替换进发布包。

## 汉化文件组成

内置语言包版本为 v1.47，位于 `language-packs/traditional-cht-1.47/ff7`。导入器只复制 FFNx 需要的资源：

| 目录 | 作用 |
| --- | --- |
| `direct` | FFNx 直接资源覆盖，包含菜单/世界等资源及中文字体图集。 |
| `override` | 将场景、战斗、内核和电影等英文路径映射到中文资源；窗口和跳过片头资源也在这里处理。 |
| `hext` | FFNx 的文本和运行时配置补丁，例如字体、窗口和战斗显示行为。`hext-bat1` 会合并到 `hext`。 |
| `mods` | 汉化补丁使用的纹理等 Mod 资源。 |
| `fonts/msjh_bd` | 天幻繁体补丁提供的微软正黑粗体字体资源，导入时复制到 `direct`，供 FFNx 字体系统读取。 |

`.iro` 模组包、教程、原始安装脚本和 VC 安装程序不进入正式语言包。`runtime-payload/traditional/runtime` 中的 `ff7_en.exe`、`ali213.dll`、`msvcr100.dll` 和 `ff7input.cfg` 是传统补丁的运行时兼容文件，不是本仓库重新制作的中文文本。

## 汉化如何生效

安装器执行以下步骤：

1. 验证 GOG 根目录存在 `FFVII.exe`/`FFVII_LAUNCHER.exe` 和 `ff7` 目录。
2. 校验 `runtime-payload/ffnx` 的版本、x86 架构及 SHA-256，再复制到 `ff7\workingdir`；`AF3DN.P`/`AF4DN.P`、`FFNx.toml` 和资源目录组成 FFNx 渲染运行时。
3. 将语言包的 `direct`、`override`、`hext`、`mods` 和字体资源复制到同一个工作目录。
4. 将传统运行时 `ff7_en.exe` 作为工作目录启动文件，并以 FFNx 的 Direct3D 11 配置加载覆盖资源。
5. FFNx 在运行时优先读取 `direct`/`override` 资源，并用中文字体图集绘制文本；不依赖 Windows 系统是否安装中文字体。

安装器不会修改根目录的 `FFVII.exe`、`FFVII_LAUNCHER.exe`、`Galaxy.dll`、`Galaxy64.dll` 或 Galaxy 配置。每个目标文件都会先备份并记录 SHA-256，回滚时只恢复安装前版本。

## GOG 成就桥

菜单中的“GOG 成就验证”不是每次游戏前必须执行的独立补丁。它的实际作用是启动已经安装的 GOG/FFNx 兼容链路，并让用户在游戏中触发成就。安装成功后桥已经是持久文件，启动器会复用它。

关键文件及关系：

```text
runtime-payload/bridge/steam_api.dll
  -> ff7/workingdir/steam_api.dll       兼容桥

GOG 游戏根目录的 steam_api.dll
  -> ff7/workingdir/steam_api_gog.dll   原始 GOG API，保留为桥接目标

GOG 游戏根目录的 Galaxy.dll/GalaxyConfig.json
  -> ff7/workingdir/                 本地运行时副本（若存在）
```

桥接 DLL 导出 FFNx/传统运行时需要的 `SteamAPI_*`、`SteamUser`、`SteamUserStats` 和 `SteamUtils` 接口。它启动时加载旁边的 `steam_api_gog.dll`，解析 GOG 原始 API，再转发初始化、回调、用户统计和工具接口；请求的 App ID 会映射到 GOG FFVII App ID `3837340`。桥接日志写入 `ff7\workingdir\FFNxGOGBridge.log`，FFNx 日志写入 `FFNx.log`。

桥接源码位于 `bridge-source`：

- `bridge/steam_api_bridge.cpp`：DLL 转发和 GOG App ID 适配
- `bridge/bridge_selftest.cpp`：导出和真实 GOG DLL 加载自测
- `bridge/steam_api.def`：导出表
- `build-bridge.ps1`：在安装 Visual Studio C++ 工具链后构建并运行自测

当前候选的成就链路已在本机 GOG 版本测试过可触发解锁，但 Galaxy 弹窗不是桥接 API 的保证行为。发行版应要求测试者确认 Galaxy 账户状态、解锁前后成就状态和 `FFNxGOGBridge.log`，不要只以“游戏启动”作为成就兼容证据。

## 启动与回滚

- `安裝 繁體中文補丁.cmd`：导入、安装、启动、清理日志和回滚菜单。
- `启动 FFVII GOG 中文版.cmd`：安装完成后的长期启动入口。
- `state/install-manifest.json`：已安装文件、源哈希和备份位置。
- `backups/<timestamp>`：安装前文件备份，首次安装时自动创建。
- `logs/`：安装器和启动器日志；游戏运行日志在 `ff7/workingdir`。

启动器发现安装清单后会执行已安装文件哈希校验；文件被外部修改时会拒绝静默覆盖，并要求先回滚/重新安装。回滚或删除安装清单后，需要再次以管理员身份运行安装菜单。

## 特别鸣谢

- [ffsaga](https://www.youtube.com/@ffsaga)：本项目使用的繁体中文补丁来源。感谢其制作、整理与分享 FFVII 繁体中文资源。
- [FFNx](https://github.com/julianxhokaxhiu/FFNx) 项目及其贡献者：感谢提供开源的现代 FFVII 游戏驱动、资源覆盖与渲染运行时。本项目的中文显示方案建立在 FFNx 之上。
- 一位无名氏的 GOG 粉丝大力支持。

## 开发与许可证

PowerShell 5.1、Windows `tar.exe` 和 FFNx 运行时是最低要求。FFNx 许可文本随 `runtime-payload/ffnx/COPYING.TXT` 提供，运行时模块的版本和修改记录位于 `runtime-payload/ffnx-module.json`。汉化资源、字体、`ali213.dll`、`ff7_en.exe` 和 `msvcr100.dll` 来自第三方补丁；本项目目前尚未取得这些第三方资产的完整再分发授权，也不声称拥有其版权。收到作者或权利人异议时，相关内置资产将从后续发布中移除，外置模块导入机制仍会保留。
