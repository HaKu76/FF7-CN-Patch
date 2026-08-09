# FFNx 运行时模块

## 当前验证版本

- 项目：FFNx
- 上游仓库：<https://github.com/julianxhokaxhiu/FFNx>
- 版本：`1.24.2.26`
- 架构：x86
- 对应源码提交：`7b7799027a02ce279a34e4ecc69bd8c676430a53`
- 源码快照：<https://github.com/julianxhokaxhiu/FFNx/archive/7b7799027a02ce279a34e4ecc69bd8c676430a53.zip>
- 许可证：GNU GPL v3，见模块内 `ffnx/COPYING.TXT`

`1.24.2.26` 是旧 Canary 连续构建。上游会移动 `canary` 标签并替换发布资产，旧二进制已经没有不变的官方发布链接。模块通过下列哈希固定验收输入：

```text
上游 AF3DN.P SHA-256:
8a21e5a990ea9d28e4b85f814d0c8923bcb7456438765663d5c8daaab1db5de7

上游 AF4DN.P SHA-256:
28117cdc956b764e35650a3856b5cf942dfe317c68abaaabb693cb3d83ae333c
```

## 导入行为

将 `FFNx-GOG-Runtime-Module-1.24.2.26-0.7.3.zip` 放进 `FF7-CN-Patch\imports\ffnx`，再选择菜单“导入/更新 FFNx”。导入器执行：

1. 校验 `AF3DN.P`/`AF4DN.P`、`FFNx.toml`、`COPYING.TXT`。
2. 校验 PE 架构为 x86、版本为 `1.24.2.26`，并核对精确 SHA-256。
3. 只复制 FFNx 运行时文件，不导入 Valve `steam_api.dll`、`FFsky.dll` 或调试 PDB。
4. 把上游 `AF3DN.P` 内 Valve Steam API 的 SHA-1 白名单值替换成本项目 GOG 适配桥的精确 SHA-1。
5. 再次验证适配后 `AF3DN.P` SHA-256 为：

```text
2ccb5282417a04c6370dcfe56f2fa05c919bb57ce944461feaa881b102c1f873
```

这个二进制修改是可复现的 40 字节等长替换。原始 FFNx 模块不会直接写进游戏；导入后仍由主安装器执行备份、安装清单和回滚。

## 官方下载

- 最新稳定版：<https://github.com/julianxhokaxhiu/FFNx/releases/latest>
- 所有稳定版：<https://github.com/julianxhokaxhiu/FFNx/releases>
- Canary：<https://github.com/julianxhokaxhiu/FFNx/releases/tag/canary>
- `1.24.2.0` 官方 Steam 包：<https://github.com/julianxhokaxhiu/FFNx/releases/download/1.24.2/FFNx-Steam-v1.24.2.0.zip>

当前安装器不会接受 `1.24.2.0` 或最新版本替代 `1.24.2.26`，因为这些版本尚未完成相同的中文显示和 GOG 成就回归测试。更换 FFNx 版本必须更新允许哈希并重新执行完整验收。
