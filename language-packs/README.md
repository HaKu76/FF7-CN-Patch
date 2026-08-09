# 外置 FFNx 语言包

每个语言包必须是一个独立目录，并在目录内提供顶层 `ff7` 文件夹。安装器会把
`ff7`（或 `ff7\workingdir`）中的 FFNx 资源合并到游戏的 `ff7\workingdir`：

```text
language-packs\<language-id>\
  ff7\
    FFNx.toml              # 可选，安装器会以 FFNx 运行时为基础合并
    direct\                # 可选
    override\              # 可选
    hext\                  # 可选
    mods\                  # 可选
    ff7_en.exe             # 可选，语言包自带运行时可覆盖基础运行时
```

完整包已经内置 `traditional-cht-1.47`。普通用户无需导入，直接运行根目录的
`安裝 繁體中文補丁.cmd` 并选择“一键安装并启动”。

内置 v1.47 资源来源于 [FF Saga / FFSaga](https://www.youtube.com/@ffsaga)，其内置和
再分发未经补丁作者明确同意。如作者或相关权利人提出异议，后续版本将
移除内置资源；本目录定义的外置语言包格式和 `imports\language` 导入能力仍会保留。

外部模块请放到 `..\imports\language`，再选择菜单“导入/更新语言包”；不要把整个
`language-packs` 目录重新放回 `imports`。
简中传统 `data\*.lgp` 整包不能直接放在这里；需要先转换成 FFNx 的
`direct/override/hext` 布局。
