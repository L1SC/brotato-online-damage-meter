# 联机伤害统计显示补丁

`CoopFix-OnlineDamageMeter` 1.0.0 是一个独立辅助 Mod，修复 Brotato Online 客户端不显示原伤害统计的问题。它不新增统计面板，不发送新的网络统计，也不修改伤害计算。

当前适配目标：

- Brotato 1.1.15.4，ModLoader 6.2.0。
- 联机前置：`six666-BrotatoOnline` 6.6.6。
- 统计前置：`lrueckert-DmgMeter` 2.2.0。

其他版本尚未确认兼容。测试记录与未验证项见 [验证说明](online-damage-meter-verification.md)。

## 原理与范围

当前两个前置的代码中，Online 在客户端清空 `WaveTimerLabel.wave_timer`，而 DmgMeter 依赖该引用判断是否刷新伤害容器，因此跳过显示更新。

本补丁只扩展 `ui_wave_timer`：在联机客户端读取实际 `Main._wave_timer`，驱动原 DmgMeter 容器；标签的 `wave_timer` 引用仍保持 `null`，不恢复被 Online 禁用的计时器行为。非客户端继续使用原逻辑。

每个需要显示统计的客户端单独安装即可，房主不必安装；这一组合已通过本机真实 LAN 验证。它展示原统计 Mod 在当前机器上的数据，不保证房主与客户端数值完全一致：Online 使用混合模拟。3/4 人局沿用 DmgMeter 的前 6 项显示限制。同一场景中武器替换后的引用刷新仍不作额外保证。

## 安装与使用

1. 完全退出游戏，确认两个前置已订阅或安装。
2. 将 `CoopFix-OnlineDamageMeter-1.0.0.zip` **保持 ZIP 原样**放入游戏目录的 `mods` 文件夹，不解压，不放进创意工坊文件夹。
3. 启动游戏，在 Mod 列表中启用两个前置及 `CoopFix-OnlineDamageMeter`，然后重启游戏。
4. 以客户端加入联机房间，进入战斗，检查原伤害统计区域是否更新；切换下一波再检查是否正常重置。

本机安装目标：

```text
D:/Program Files (x86)/Steam/steamapps/common/Brotato/mods/CoopFix-OnlineDamageMeter-1.0.0.zip
```

这里只提供安装方法；构建产物不会自动安装，也不会自动发布。

## 卸载

在 Mod 列表中停用本补丁并退出游戏，删除上述补丁 ZIP 后重新启动即可。不要删除两个前置或游戏文件；无需重置存档。

## 故障排查

- **Mod 列表没有补丁**：检查 ZIP 是否完整放在游戏根目录的 `mods` 中，避免多套一层文件夹；确认当前启动的是对应游戏安装目录。
- **缺少前置或版本不符**：核对前置 Mod ID、启用状态和上述版本，启用后重启游戏。
- **客户端仍无统计**：确认已进入实际战斗且确有伤害产生；记录客户端/房主身份、游戏与 Mod 版本、人数、波次及游戏日志，按 [验证说明](online-damage-meter-verification.md) 核对。房主不需要安装此补丁，但两个前置仍需按原要求安装。
- **数值与房主不同**：本补丁修复显示更新，不强制统一各机器的伤害计数；这不等同于安装失败。
- **更新前置后报错或出现异常**：停用本补丁并重启，保留日志；不要直接修改前置文件。未确认的新版本可能改变本补丁依赖的刷新入口。

## 构建与测试

在项目根目录执行：

```powershell
python tools/build_damage_meter.py
python tools/run_damage_meter_tests.py --game-dir 'D:/Program Files (x86)/Steam/steamapps/common/Brotato'
```

构建与自动测试不能代替实际跨机器联机验证。客户端单独安装、多人显示、波次切换以及武器引用刷新等结果，以 [验证说明](online-damage-meter-verification.md) 为准。

## 许可

本项目原创辅助 Mod 使用 MIT 许可。两个前置分别遵循各自许可；补丁包不重分发前置代码或游戏文件。
