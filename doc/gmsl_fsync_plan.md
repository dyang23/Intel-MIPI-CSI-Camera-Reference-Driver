# GMSL FSYNC 多相机快门同步 —— 开发实施计划（任务清单）

> 配套设计文档:[gmsl_fsync_design.md](gmsl_fsync_design.md)
> 目标器件:MAX96724(DES)+ MAX9295A(SER)+ ISX031 ×4,MIPI0
> 目标驱动:`drivers/media/i2c/maxim-serdes/`(新驱动)
> 创建日期:2026-07-28
>
> **用法**:每完成一项,把 `[ ]` 改成 `[√]`;整节全部完成时,在节标题后加 `√`。
> 阻塞/放弃的项改成 `[×]` 并在行尾用 `— 原因:...` 说明。

---

## 0. 计划前置:与设计文档的差异修正(先读)

编码前已核对代码与手册,以下几处需以**本文件为准**:

| # | 设计文档写法 | 实际情况 |
|---|---|---|
| 1 | ACPI 文件 `acpi/nodka/nodka_max96724_4x_sensing_isx031_mipi0.asl` | **当前在用的是** [acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl)。注意 `acpi/nodka/` 是**另一块板**的目录,不要改错 |
| 2 | 序列器驱动写作 `max96717.c`,担心 MAX9295 不适用 | [max96717.c:1858](../drivers/media/i2c/maxim-serdes/max96717.c#L1858) 的 ACPI 匹配表含 `INTC1138 → max9295a_info`,**MAX9295A 复用同一份 pinctrl/GPIO 隧道代码** |
| 2b | §5.4 "路径 A(优先,少改码):纯 ACPI 配 SER MFP7 为 RX" | **⚠ 路径 A 走不通 —— 已在 linux-6.17 源码确认**(详见下方"附:为什么路径 A 不可行")。**结论:必须写码,见"路径 C"** |
| 3 | DES 侧 GPIO 组基址 `0x0300 + pin*3` | **⚠ 本行当初的"已确认"是错的(2026-07-28 更正)**。实际地址**不是**均匀步进:GPIO4 与 GPIO9 之后各有 1 字节空洞(`GPIO7_A=0x316` 而非 `0x315`),且 link1/2/3 各有独立的 `GPIO_B`/`GPIO_C` 块(`0x337…`/`0x36D…`/`0x3A4…`)。详见 [gmsl_fsync_status.md §3.3](gmsl_fsync_status.md);代码已改为查表 |
| 4 | `0x4AF` 建议写 `0xD0` | 手册复位值即 `0xCF`(`FS_GPIO_TYPE=1`、`FS_USE_XTAL=1`、`FS_LINK_3:0=1111`、`AUTO_FS_LINKS=0`)。写 `0xD0` 会**清掉 FS_LINK 位图**改走 AUTO;两条路都可用,但需显式选定 |
| 5 | `FSYNC_OUT_PIN` "effective only when **FSYNC_MODE**=01" | 手册原文写的是 "effective only when **FSYNC_METH** = 01"(`doc/max96724.txt:17313`)。疑为手册笔误,**列为阶段 1 实测确认项** |
| 6 | `0x4B1` bit7:3 = `FSYNC_TX_ID` | 确认无误(复位 `0xF0` → TX_ID=0x1E,`FSYNC_ERR_THR[2:0]`=0) |

- [x] 0.1 阅读并认可上述修正,必要时回改 `gmsl_fsync_design.md`

### 附:为什么路径 A(纯 ACPI 配 pinctrl)不可行 —— 已在 `/media/ndk/Dong_U1/dev/linux-6.17` 源码确认

Linux 里"固件描述 → pinctrl 配置"这条链**只有 devicetree 一个实现**:

1. 设备 probe 前,驱动核心调 `pinctrl_bind_pins()`(`drivers/base/pinctrl.c:21`)自动套用 `default` 状态。
2. 它最终进 `create_pinctrl()`(`drivers/pinctrl/core.c:1072`),第一件事就是调 `pinctrl_dt_to_map()`。
3. `pinctrl_dt_to_map()`(`drivers/pinctrl/devicetree.c:200`)开头:
   ```c
   struct device_node *np = p->dev->of_node;
   ...
   if (!np) {                       /* ACPI 设备恒为 NULL */
           if (of_have_populated_dt())
                   dev_dbg(p->dev, "no of_node; not parsing pinctrl DT\n");
           return 0;                /* 直接返回,一条 map 都不建 */
   }
   ```
4. `drivers/pinctrl/` 下**没有** `acpi.c` 之类的对应文件 —— 不存在 ACPI 版本的 map 解析。

**ACPI 唯一能碰到 pinctrl 的口子**是 `GpioIo()` 描述符里的 `PinConfig` 字段,经
`gpiolib-acpi` → `gpio_set_config()` → `gpiochip_generic_config()` → 驱动的 `pin_config_set()`。
但它只能表达**通用**参数(`PullUp`/`PullDown`/`PullNone`、debounce、drive strength,
见 `drivers/gpio/gpiolib-acpi-core.c:653`),**无法**表达 max96717 定义的自定义参数
(`maxim,rx-id`/`maxim,tx-id` 是 `PIN_CONFIG_END + N`,见 [max96717.c:359](../drivers/media/i2c/maxim-serdes/max96717.c#L359))。

**推论**:`max96717_cfg_params[]` 这三个自定义参数在本 ACPI 平台上是**永远不会被触发的死代码**。
但 `_DSD` 里的普通属性(`device_property_read_u32()` 等)在 ACPI 下**完全可用** —— 这正是路径 C 的基础。

---

## 阶段 0 — 现状基线确认(上机,~0.5 天)

- [√] 0.2 用 [ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl) 启动,确认 4 路都能出图,记录 `media-ctl -p` 拓扑
      → **通过**。4 路 `gst-launch-1.0` 稳定预览 ~17h(boot 07-27 16:56 → 07-28 09:35+),无掉流。拓扑见 §0.9
- [×] 0.3 示波器抓 4 个 MAX9295A 的 **MFP7** — **无示波器,暂缓**。改由 §0.10 的软件手段间接判定
- [×] 0.4 抓 ISX031 侧 FSIN 引脚 — **同上,暂缓**
- [√] 0.5 判定 [isx031.c:509](../drivers/media/i2c/isx031.c#L509) 的 `isx031_framesync_reg_list`(`0x8AF0=0x01`)是否真的写下去了
      → **❗结论:根本没写。** 见下方 §0.11「关键发现」
- [√] 0.6 ISX031 是否自走帧?记录实测 fps → **4 路均 30.00 fps,确认自走**
- [√] 0.7 量化 4 路当前的**相位差** → **快门相位极差 6.5–6.9 ms(帧周期的 20%)**;
      且 30s 内抖动仅 2.4–11.8 µs → **频率已锁定(< 0.4 ppm),只差相位**。工具:[fsync_phase_check.py](../script/fsync_phase_check.py)
- [√] 0.8 读 DES `0x4A0 / 0x4AF / 0x4B1 / 0x4B6` 复位值,确认与手册一致
      → **通过**。root 用 `SUDO_ASKPASS=$PWD/script/askpass.sh sudo -A` 取得(§0.12 的两个建议都不必了)。
      实测:未使能时 `0x4A0=0x0C`(MODE=OFF)、`0x4AF=0xCF`、`0x4B1=0x50`(TX_ID=0x0A,板级声明值)、`0x4B6=0x00`
- [√] **产出**:[gmsl_fsync_baseline.md](gmsl_fsync_baseline.md) + [fsync_baseline.json](fsync_baseline.json) / [fsync_baseline_900.json](fsync_baseline_900.json)

### 0.9 实测拓扑(已记录)

| 器件 | I²C | media entity | subdev |
|---|---|---|---|
| MAX96724 (DES) | `0-0027` | 457 | `/dev/v4l-subdev4` |
| MAX9295A (SER) ×4 | `7-0040` `17-0040` `18-0040` `21-0040` | 479/485/491/497 | subdev5..8 |
| ISX031 ×4 | `22-001a` `23-001a` `24-001a` `25-001a` | 503/507/511/515 | subdev9..12 |

取流:`gst-launch-1.0` (PID 21171) 占用 `/dev/video0..3`。

### 0.10 无示波器时的软件替代方案(替代 0.3 / 0.4 / 0.6 / 0.7)

示波器测的是**物理脉冲**,但我们真正要回答的是三个可由软件回答的问题:

| 原问题 | 软件替代做法 |
|---|---|
| 0.6 是否自走帧、帧率多少 | `v4l2-ctl -d /dev/videoN --stream-mmap --stream-count=300 --stream-to=/dev/null`,看打印的 fps。**需先停掉 gst** |
| 0.7 4 路相位差 | 取 buffer 的 `v4l2_buffer.timestamp`(单调时钟,ISYS 在帧结束时打戳),4 路同时抓 300 帧,比较同序号帧的时间戳散布。**同步前应看到随机散布(可达 ±1 帧周期);同步后应收敛到 ~µs 级** |
| 0.3/0.4 MFP7 是否有脉冲 | 间接判定:§0.11 已证明传感器**从未进入外触发从模式**,且 FSIN 被静态拉低 → 逻辑上不可能有脉冲。示波器仅用于最终确认,不阻塞开发 |

> 0.7 的时间戳法是**本项目验收同步效果的主要手段**(阶段 4.1 复用同一脚本前后对比),
> 比示波器更贴近"图像是否真的对齐"这个最终目标。建议写成 `script/fsync_phase_check.py`。

### 0.11 ❗关键发现:传感器从未进入外触发从模式

`journalctl -k -b` 显示 4 路 ISX031 **全部**打印:

```
isx031 i2c-INTC113C:00: No platform data provided
isx031 i2c-INTC113C:01: No platform data provided
isx031 i2c-INTC113C:02: No platform data provided
isx031 i2c-INTC113C:03: No platform data provided
```

即 [isx031.c:1017](../drivers/media/i2c/isx031.c#L1017) 的 `client->dev.platform_data == NULL`。
而写 framesync 的条件是([isx031.c:508](../drivers/media/i2c/isx031.c#L508)):

```c
if (isx031->platform_data && !isx031->platform_data->irq_pin_flags) {
        ret = isx031_write_reg_list(client, &isx031_framesync_reg_list, false);
```

`platform_data == NULL` → **整个条件为假** → `0x8AF0 = 0x01`(external pulse-based sync)**从来没有被写入**。

**推论链**:

1. 4 路 ISX031 一直工作在**默认自走(master)模式**,各自由内部时基产生帧 → 天然不同步
2. 这解释了为什么"FSIN 静态拉低"却仍然出图 —— 传感器压根不看这根线
3. 设计文档 §3.2.1 的疑问("是否出图取决于 ISX031 无脉冲时是否自走")**已解答:是,自走**
4. `irq_pin_flags` 这条路径来自老的 `ipu-acpi-pdata` 控制逻辑(仅当 BIOS 声明
   `GPIO_READY_STAT` 时才置位,见 [ipu-acpi-pdata.c:571](../ipu7-drivers/drivers/media/platform/intel/ipu-acpi-pdata.c#L571));
   新的 `mipi-disco-img` / `ipu_bridge` 流程**不填 `platform_data`**,所以这段判断在本平台恒不成立

**对开发计划的影响(重要)**:

- 阶段 2 新增任务 **2.0**:必须让 `0x8AF0=0x01` 真正写下去,否则 FSYNC 脉冲送到了传感器也**不会被理会**
- 原任务 2.4「确认移除 fsin-gpios 后 framesync 仍会写入」的前提**不成立** —— 它现在就没写。改为"让它写入"
- 判据不该再挂在 `platform_data->irq_pin_flags`(本平台恒 NULL),应改为由 fwnode 属性或 fsync 使能状态驱动

### 0.12 待办:需要 root 的部分(0.8)

当前会话以 `ndk` 运行,`sudo` 需要密码,故以下未完成:

- `/dev/i2c-0` 属 `i2c` 组,当前用户不在该组 → 无法 `i2ctransfer` 读 DES 寄存器
- `/sys/kernel/debug/regmap/` 需 root → 无法用 regmap debugfs 读回
- `CONFIG_VIDEO_ADV_DEBUG is not set`(见 `/boot/config-6.17.0-14-generic`)
      → **`v4l2-dbg` 读寄存器这条路在当前内核上不可用**;若想长期方便调试,可考虑开启该选项重编内核

**建议**(任选其一):
1. `sudo usermod -aG i2c ndk` 然后重新登录 → 之后可免密读 I²C
2. 由人工执行 §0.13 的只读脚本并回贴输出

### 0.13 只读寄存器检查脚本(需 root 执行)

```bash
# MAX96724 @ bus0 0x27,16-bit 寄存器。全部为只读操作,不影响正在跑的预览。
for r in 04A0 04A1 04A5 04A6 04A7 04AF 04B0 04B1 04B6; do
    hi=0x${r:0:2}; lo=0x${r:2:2}
    printf "0x%s = " "$r"
    sudo i2ctransfer -y -f 0 w2@0x27 $hi $lo r1
done
# 预期(手册复位值):04A0=0x03  04AF=0xCF  04B1=0xF0  04B0=0x00  04B6=?
```

> 阶段 0 的结论已经改变了阶段 2 的起始假设(见 §0.11),进阶段 1 前请先读该节。

---

## 阶段 1 — 反序列器 FSYNC 生成器(核心,~2 天)√

### 1.A 共享层接口 √

- [√] 1.1 [max_des.h](../drivers/media/i2c/maxim-serdes/max_des.h) 新增 `struct max_des_fsync`
      → 实际字段为 `enabled/fps/use_xtal/tx_id/link_mask/gen_pin`。
      **`comp_en` 去掉**(没有承载 GPIO,延时补偿无处可加);**`gen_gpio` 改名 `gen_pin`** 并成为可选项(见 2.11)
- [√] 1.2 `struct max_des` 增加 `struct max_des_fsync fsync;` 成员(另加 `bool fsync_active;`,见 3.9)
- [√] 1.3 `struct max_des_ops` 增加 `int (*set_fsync)(struct max_des *des, const struct max_des_fsync *cfg, bool enable);`
- [√] 1.4 确认 `max9296a.c` 不实现该 op 时不回归 —— 调用点 [max_des.c:2520](../drivers/media/i2c/maxim-serdes/max_des.c#L2520) 与
      [max_des.c:3298](../drivers/media/i2c/maxim-serdes/max_des.c#L3298) 均判空;未声明 `maxim,fsync-fps` 时直接 `return 0`

### 1.B max96724 寄存器建模 √

- [√] 1.5 [max96724.c](../drivers/media/i2c/maxim-serdes/max96724.c) 新增 FSYNC 寄存器宏:
      `FSYNC_0(0x4A0)` / `FSYNC_1(0x4A1)` / `FSYNC_5..7(0x4A5..7)` / `FSYNC_15(0x4AF)` / `FSYNC_16(0x4B0)` / `FSYNC_17(0x4B1)` / `FSYNC_22(0x4B6)`
- [√] 1.6 GPIO 隧道寄存器宏 —— **⚠ 本行原写法 `0x300 + (x)*3` 是错的**,见
      [gmsl_fsync_status.md §3.3](gmsl_fsync_status.md)。实际地址不均匀(GPIO4/GPIO9 后各有 1 字节空洞),
      且 link1/2/3 各有独立的 `GPIO_B`/`GPIO_C` 块。已改为 `max96724_gpio_b_regs[4][11]` 查表,
      `GPIO_A` 只有 link0 一份。同时修正**计划前置修正项 #3**(该项照抄了手册的均匀步进,是错的)
- [√] 1.7 `fps → 24bit period` 换算 helper `max96724_fsync_period()`:
      `fps==0`、`!use_xtal`、越界(> `0xFFFFFF`)全部报 `-EINVAL`

### 1.C 生成器实现 √

- [√] 1.8 实现 `max96724_set_fsync()`,写入顺序:TX_ID → FSYNC_15 → PER_DIV → 周期 L/M/H →(可选 gen_pin)→ 最后置 `EN_VS_GEN`
- [√] 1.9 `enable=false` 路径:清 `EN_VS_GEN`、`FSYNC_MODE` 回 `0b11`。
      **承载 GPIO 的 `GPIO_TX_EN` 有意不清** —— 发生器停了以后隧道上只是一个静态电平,无害;
      下次 enable 会幂等地重配,少一次 I²C 往返
- [√] 1.10 全部寄存器改动走 `regmap_update_bits()` 读-改-写
- [√] 1.11 挂进 `max96724_ops`
- [√] 1.12 `log_status` 打印 `FSYNC_LOCKED` / `LOSS_OF_LOCK` / `FSYNC_ERR_CNT`,另加 `FSYNC_0` 回读与 gen_pin 电平

### 1.D 打通验证 √

- [×] 1.13 硬编码 + debugfs/module param 触发 —— **跳过**。ACPI `_DSD` 属性一次就通了,不需要临时开关
- [√] 1.14 **实测确认修正项 #5**(`FSYNC_OUT_PIN` 受 `FSYNC_METH` 还是 `FSYNC_MODE` 约束)
      → **问题本身消解了**:`FSYNC_METH` 只有 `00`(Manual)能产生脉冲,`01`/`10` 下隧道上什么都没有。
      既然 `METH` 恒为 `00`,`FSYNC_OUT_PIN` 在本方案里始终无效,只在 gen_pin 路径上按手册置位备用
- [×] 1.15 示波器量 DES 本地 MFP7 —— **无示波器**。改为读加串器 `GPIO_A(7)=0x2D3` bit3 的引脚电平,
      等效且更贴近"传感器实际收到什么"(见 [gmsl_fsync_status.md §2.3](gmsl_fsync_status.md))
- [√] 1.16 推流中读 `0x4B6 = 0x40` → `FSYNC_LOCKED=1`、`LOSS_OF_LOCK=0`;`0x4B0` 启动瞬间 `0x09`,之后恒 `0x00`
- [√] **产出**:反序列器稳定产生 30Hz 脉冲,`FSYNC_LOCKED` 置位

---

## 阶段 2 — GMSL 隧道 + 序列器 RX(~2 天)

### 2.A 引脚冲突拆除(先做,否则 2.B 量不到波形)

> 冲突根因:"主机经 I²C 驱动 SER MFP7 输出" 与 "MFP7 作 GMSL-RX 隧道输出" **互斥**。
> 现状:[_ser_common_max9295.asl:75](../acpi/_ser_common_max9295.asl#L75) 把 MFP7 放进 `IoRestrictionOutputOnly` 的 GpioIo 资源;
> [_cam_common_isx031.asl:88](../acpi/_cam_common_isx031.asl#L88) 用 `fsin-gpios = {SERx, 0, 1, 1}`(资源 0 / 引脚索引 1 → MFP7 / 低有效)把它交给 ISX031 静态拉低。

- [√] 2.1 在 [ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl) 里删掉 4 处 `#define DESCH_CAM_FSIN_GPIO 1` 及对应 `#undef` → ISX031 不再拿到 `fsin-gpios`
- [√] 2.2 `DESCH_SER_EXTRA_GPIO_PIN 7` —— **已删**。删除后 GpioIo 引脚表由 `{0, 7}` 缩为 `{0}`,
      `reset-gpios` 仍是索引 0 不受影响(附录 A.2 的预判正确);MFP7 不再有任何 gpiolib consumer
- [√] 2.3 `devm_gpiod_get_optional("fsin")` 拿不到时优雅降级 —— 4 路 probe 后 dmesg 不再出现 `Fsin gpio found`,无报错;resume 路径正常
- [√] 2.4 **让 `0x8AF0=0x01` 真正写入** —— 判据已从 `platform_data->irq_pin_flags`(本平台恒 NULL 的死逻辑)
      改为 fwnode 布尔属性 `sony,external-sync`,由板级 ASL 声明。
      4 路 dmesg 均打印 `External frame sync enabled`,传感器确已进入外部脉冲从模式

### 2.B 序列器侧 MFP7 = RX 模式 —— **走路径 C(新增,替代原路径 A)**

> 📖 **完整实现细节(ASL 属性写法 + 驱动代码 + 时序核查)见文末 [附录 A](#附录-a--路径-c-实现细节对应任务-2629)**

> **为什么不走原路径 A**:max96717 的 pinctrl 只实现了 DT 映射(`.dt_node_to_map`),
> 内核 pinctrl 核心从固件建 map 的路径 (`pinctrl_dt_to_map()`) 依赖 `dev->of_node`,**ACPI 下不生效**。
> 现有 `maxim,tx-id`/`maxim,rx-id` 自定义参数在本平台是**死代码**,纯改 ASL 配不出 RX。

- [√] 2.5 确认 pinctrl 核心没有 ACPI map 路径 —— **已在 linux-6.17 源码证实**,见上方"附"节。不再考虑路径 A
- [√] 2.6 在 [max96717.c](../drivers/media/i2c/maxim-serdes/max96717.c) 新增 `max96717_parse_gpio_rx()`,
      读 `maxim,gpio-rx-pin` / `maxim,gpio-rx-id`(fwnode,ACPI/DT 通吃),在 probe 里直接落寄存器。
      拆成两个标量属性而非 `<pin>, <rx_id>` 二元组,ASL 侧更好写
- [√] 2.7 应用逻辑已实现并**回读验证**:`GPIO_C.GPIO_RX_ID=0x0A`、`GPIO_A.GPIO_RX_EN=1`、`GPIO_A.GPIO_OUT_DIS=0`、`GPIO_B.OUT_TYPE=1`
      → 4 路实测 `GPIO_A(0x2D3)=0x8C`、`GPIO_B(0x2D4)=0xA7`、`GPIO_C(0x2D5)=0x4A`
- [√] 2.8 时序安全 —— 附录 A.4 的三条核查均成立,且 MFP7 已无 gpiolib consumer(2.2),不会被改回输出
- [√] 2.9 4 路 SER 的 ASL `_DSD` 均声明 `GPIO_RX_PIN=7` / `GPIO_RX_ID=0x0A`(= DES 的 `FSYNC_TX_ID`,广播)
- [×] 2.10 **备选路径 B** —— 不需要,路径 C 一次通过

### 2.C DES 侧承载 GPIO 配 TX —— **整节不需要**

> **本轮最重要的结论**:MAX96724 的 FSYNC 发生器**本身就是隧道源**,
> 只要 `FSYNC_17.FSYNC_TX_ID` 对上加串器的 `GPIO_RX_ID` 就能广播出去,
> **不需要**先把脉冲注入某个本地 MFP 再进隧道。设计文档 §2.3 的"承载 GPIO"是多余的一步。
> 反而:若真的启用一个同 ID 的本地 GPIO 作 TX,隧道上会出现**两个源**,可能破坏脉冲。

- [×] 2.11 配置 `gen_gpio` 的 `GPIO_TX_ID` / `GPIO_TX_EN` —— **不需要**(理由同上)。
      仍保留为可选属性 `maxim,fsync-gen-pin`,供确实需要把脉冲引出到 DES 引脚的板子使用
- [×] 2.12 `TX_COMP_EN` 开/关对比 —— **不适用**,没有承载 GPIO。实测四路相位差已到 12 µs,无需补偿
- [√] 2.13 DES 承载 GPIO 是否需 `GPIO_OUT_DIS=1` —— **问题消解**:根本不涉及本地引脚

### 2.D 端到端验证 √

- [√] 2.14 **SER#0 的 MFP7 已复现脉冲** —— 无示波器,改读 `GPIO_A(7)=0x2D3` bit3(引脚实际电平),
      推流中四路均在 `0x84`/`0x8C` 之间翻转,占空比一致
- [×] 2.15 量 ISX031 FSIN 引脚 —— **无示波器**。间接证明:传感器处于外部脉冲从模式(2.4),
      无脉冲就不出帧,而实测四路稳定 30.00 fps → 脉冲确已到达
- [√] 2.16 帧率被 FSYNC 锁到 30fps
- [~] 2.17 脉冲极性 / 宽度 —— I²C 采样得到高电平占空比约 25%,极性与传感器要求兼容(能出帧)。
      精确的宽度 / 建立时间仍需示波器,**不阻塞**
- [√] **产出**:四路端到端脉冲贯通

---

## 阶段 3 — 多相机分组 + 使能策略(~2 天)

### 3.A 板级声明解析

- [√] 3.1 属性命名定为 `maxim,fsync-fps` / `-tx-id` / `-link-mask` / `-use-xtal` / `-gen-pin`。
      `-comp-en` 取消(见 2.12);`-gpio` 改名 `-gen-pin` 并降级为可选(见 2.11)
- [√] 3.2 在 `max_des_parse_fsync_dt()` 里解析,填 `des->fsync`,由 `max_des_parse_dt()` 调用
- [√] 3.3 **默认行为**:未声明 `maxim,fsync-fps` → 直接 `return 0`,`fsync.enabled=false`,零回归
- [√] 3.4 参数校验:`fps==0`、`tx_id > 0x1F`、`link_mask` 超出 `ops->num_links` 一律 `-EINVAL`;
      芯片侧另校验 `gen_pin` 只能是 MFP0 / MFP7;`set_fsync` op 缺失时报 `-EOPNOTSUPP`
- [√] 3.5 板级 DES `_DSD` 已加 fsync 组声明:fps=30、tx_id=0x0A、link_mask=0x0F(不声明 gen_pin)

### 3.B 使能挂到开流路径 √

- [√] 3.6 `max_des_update_streams()` 中调用 `max_des_update_fsync(priv, streams_masks, true)`([max_des.c:2671](../drivers/media/i2c/maxim-serdes/max_des.c#L2671))
- [√] 3.7 关流路径对称调用([max_des.c:2651](../drivers/media/i2c/maxim-serdes/max_des.c#L2651))
- [√] 3.8 回滚标签 `err_revert_fsync_enable:` / `err_revert_fsync_disable:` 已就位([max_des.c:2687](../drivers/media/i2c/maxim-serdes/max_des.c#L2687) / [2702](../drivers/media/i2c/maxim-serdes/max_des.c#L2702))
- [√] 3.9 用 `des->fsync_active` 做状态位,首次开流才启、最后一路关流才停
      → 实测佐证:启流前人工把 `FSYNC_0` 清成 `0x0C`、周期清零,推流中回读为 `0x14` / `0x0CB735`,停流后回到 `0x0C`

### 3.C 分组与混接

- [√] 3.10 `link_mask=0x0F` 走 `FS_LINK_3..0` 位图(`AUTO_FS_LINKS=0`);不声明 mask 时才退回 `AUTO_FS_LINKS=1`
- [ ] 3.11 在混接配置([ndk_unitree_max96724_mipi0_d457_d405.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_d457_d405.asl))上验证:**不声明 fsync 组 → 不启用**,D457/D405 不受影响
      —— 代码层面已由 3.3 保证,仍需上机跑一轮
- [ ] 3.12 (可选,可后置)加一个 v4l2 control 做运行时开关 / 改 fps —— **暂不做**

- [√] **产出**:4×ISX031 开流即同步、关流即停(混接回归见 3.11)

---

## 阶段 4 — 验证与固化(~1.5 天)

### 4.A 功能验证

- [√] 4.1 与阶段 0 基线(0.7)对照量化改善 —— `script/fsync_phase_check.py -n 60`:
      **四路快门相位极差 0.012 ms**(基线 6.89 ms),改善约 **570×**,远优于 100 µs 目标。
      四路帧率均 30.00 fps。用时间戳法而非闪烁光源,理由见 §0.10
- [~] 4.2 长跑 ≥30min,周期读 `FSYNC_ERR_CNT`(0x4B0)/`LOSS_OF_LOCK` —— **进行中**
- [ ] 4.3 帧率切换回归:15 / 30 / 60fps 各跑一轮
- [×] 4.4 不同长度 GMSL 线缆下量相位差,评估 `TX_COMP_EN` —— **无不同长度线缆可换**;
      且现有 12 µs 的极差已远小于任何合理线缆差引入的偏斜,暂不构成风险
- [ ] 4.5 S3 / S4 休眠恢复后同步仍在
- [ ] 4.6 单路热插拔:拔掉 1 路,其余 3 路不掉流、同步不乱
- [ ] 4.7 回归 [acpi/nodka_unitree/](../acpi/nodka_unitree/) 下其余配置不受影响:
      `1x_sensing_isx031`、`4x_li_isx031`、`2x_li_isx031_ac`、`d457`、`d405`、`d457_d405`

### 4.B 固化

- [ ] 4.8 更新 `gmsl_fsync_design.md`(回填实测结论;重点:§2.3 的"承载 GPIO"一步是多余的,见 2.C)
- [ ] 4.9 补 ACPI 样例与属性说明文档
- [ ] 4.10 patch 拆分(建议 5 个):① max_des.h 接口 ② max96724 寄存器+生成器 ③ max_des.c 解析 ④ max_des.c 使能钩子 ⑤ ACPI 改动
      —— 另有两个可独立先行的 bugfix:`max96724` GPIO 地址查表(1.6)、`isx031` external-sync 判据(2.4)
- [ ] 4.11 **commit message 必须英文**;`checkpatch.pl --strict` 干净
- [ ] 4.12 输出测试报告
- [ ] **产出**:可评审的 patch 集 + 测试报告

---

## 里程碑

| 阶段 | 交付 | 预计 | 状态 |
|---|---|---|---|
| 0 | 现状基线 | 0.5d | [√] |
| 1 | 反序列器脉冲 + `FSYNC_LOCKED` | 2d | [√] |
| 2 | 端到端单路贯通 | 2d | [√] 四路全通 |
| 3 | 多相机分组 + 使能策略 | 2d | [√] 余 3.11 混接回归 |
| 4 | 验证固化 + patch 集 | 1.5d | [~] 相位达标(12 µs),余长跑/回归/拆 patch |

---

## 风险与待确认项(跟踪表)

| # | 项 | 归属阶段 | 状态 |
|---|---|---|---|
| R1 | ISX031 external-pulse 从模式:无脉冲是否自走 → **已答:是,自走**;从模式已由 `sony,external-sync` 使能。极性可用(能出帧),精确宽度/建立时间需示波器 | 0.6 / 2.17 | [~] 不阻塞 |
| R10 | ~~`0x8AF0=0x01` 未写入~~ → **已解决**:判据改为 fwnode 属性,4 路均打印 `External frame sync enabled` | 0.11 / 2.4 | [√] |
| R2 | `FSYNC_OUT_PIN` 受 `FSYNC_METH` 还是 `FSYNC_MODE` 约束 → **问题消解**:只有 `FSYNC_METH=00`(Manual)能出脉冲,`OUT_PIN` 在本方案里始终无效 | 1.14 | [√] |
| R3 | SER MFP7 原 host-GPIO 用途移除后是否有别的功能依赖 → **无**。`DESCH_SER_EXTRA_GPIO_PIN` 已删,`reset-gpios` 索引不变,MFP7 无 consumer | 2.1 / 2.2 | [√] |
| R4 | 4 路线缆长度差导致的相位差,`TX_COMP_EN` 是否够 → **不适用**(无承载 GPIO);实测极差 12 µs,无需补偿 | 2.12 / 4.4 | [√] |
| R5 | DES 承载 GPIO 是否需 `GPIO_OUT_DIS=1` → **问题消解**:发生器自身即隧道源,不涉及本地引脚 | 2.13 | [√] |
| R6 | ~~路径 A 是否够用~~ → **已确认不可用(pinctrl 无 ACPI map),改走路径 C**;C 一次通过,未用 B | 2.5–2.10 | [√] 已定案 |
| R9 | FSYNC 脉冲极性 vs 原 `fsin-gpios` 的低有效声明是否一致 → 实测能稳定出帧,极性兼容 | 2.17 | [√] |
| R11 | **MAX96724 GPIO 寄存器地址不是均匀步进**(GPIO4/GPIO9 后有空洞,link1-3 另有独立块);原宏 `0x300+x*3` 对 pin7 算出 GPIO6 的 `GPIO_C` | 1.6 | [√] 已改查表 |
| R12 | **MAX9295A 的 `GPIO_C` bit6 是 RSVD,不是 `GPIO_RECEIVED`** —— 曾据此误判"发生器无输出"。正确观测点是 `GPIO_A(x)` bit3 | 调试方法 | [√] 已纠正 |
| R13 | 新默认 `FSYNC_MODE=0b00`(纯隧道源)尚未用**驱动**跑过;0.012 ms 实测是在 `0b01` 下取得的。需重启后复测,异常则改回 `0b01` | 4.x | [ ] |
| R7 | 老驱动 `ipu6-drivers/.../max9x/` 保持不动,不做双份实现 | 全程 | [√] 未改动 |
| R8 | 共享层加通用 `set_fsync` op,便于 max9296a 将来复用(上游可维护性) | 1.3 | [√] |

---

*本清单随开发推进就地更新;每个阶段结束后回填"产出"与风险表状态。*

---

# 附录 A — 路径 C 实现细节(对应任务 2.6–2.9)

## A.1 一句话概括

**绕开 pinctrl 状态机**,在 `max96717.c` 的 probe 里用 `device_property_read_*()`
直接读 ACPI `_DSD` 属性,然后用已有的寄存器宏把 MFP7 配成 GMSL-RX 输出。

为什么能行:pinctrl 的 map 机制是 DT-only(见前面"附"节),
但 `_DSD` 里的**普通属性**在 ACPI 下经 fwnode 层完全可读 —— 驱动里已经在用
`fwnode_property_read_u32()`(如 [max_des.c:3241](../drivers/media/i2c/maxim-serdes/max_des.c#L3241))。

## A.2 ACPI 侧:属性怎么写

在 [_ser_common_max9295.asl](../acpi/_ser_common_max9295.asl) 的 SER `_DSD`
Device Properties 包里加(用一个新的可选宏 `DESCH_SER_FSYNC_RX_ID` 控制):

```asl
#ifdef DESCH_SER_FSYNC_RX_ID
        /* Configure MFP<pin> as a GMSL2 GPIO-tunnel receiver so the
         * deserializer's FSYNC pulse is reproduced on this pin and
         * drives the sensor's FSIN input. */
        Package () { "maxim,gpio-rx-pin",   DESCH_SER_FSYNC_RX_PIN },
        Package () { "maxim,gpio-rx-id",    DESCH_SER_FSYNC_RX_ID  },
#endif
```

调用方([ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl))
每个 CH 段里,把原来的 `#define DESCH_CAM_FSIN_GPIO 1` 换成:

```asl
#define DESCH_SER_FSYNC_RX_PIN 7      /* MFP7 */
#define DESCH_SER_FSYNC_RX_ID  0x0A   /* 必须 == DES 的 FSYNC_TX_ID */
```

> **注意 GPIO 索引会变**:[_cam_common_isx031.asl](../acpi/_cam_common_isx031.asl) 里
> `reset-gpios = {SER, 0, 0, 1}` 用的是资源 0 / **引脚索引 0**(→ MFP0),
> `fsin-gpios = {SER, 0, 1, 1}` 用的是**引脚索引 1**(→ MFP7)。
> 因此删掉 `DESCH_SER_EXTRA_GPIO_PIN` 后 GpioIo 引脚表从 `{0, 7}` 缩成 `{0}`,
> **reset-gpios 仍是索引 0,不受影响** —— 可以安全删除。(此条已解答任务 2.2)

## A.3 驱动侧:解析 + 落寄存器

寄存器宏**已经全部就绪**,直接复用([max96717.c:94-112](../drivers/media/i2c/maxim-serdes/max96717.c#L94)):

| 寄存器 | 宏 | 要写的位 |
|---|---|---|
| `GPIO_A` = `0x2BE + pin*3` | `MAX96717_GPIO_A(x)` | `GPIO_RX_EN`=1(BIT2)、`GPIO_OUT_DIS`=0(BIT0) |
| `GPIO_B` = `0x2BF + pin*3` | `MAX96717_GPIO_B(x)` | `OUT_TYPE`=1(BIT5,推挽) |
| `GPIO_C` = `0x2C0 + pin*3` | `MAX96717_GPIO_C(x)` | `GPIO_RX_ID` = rx_id(`GENMASK(4,0)`) |

新增函数(放在 `max96717_gpiochip_probe()` 之后):

```c
static int max96717_parse_fsync_rx(struct max96717_priv *priv)
{
	struct device *dev = priv->dev;
	u32 pin, rx_id;
	int ret;

	/* Optional: only boards that route a GMSL GPIO-tunnel frame-sync
	 * pulse to the sensor declare these properties. */
	if (device_property_read_u32(dev, "maxim,gpio-rx-pin", &pin))
		return 0;

	ret = device_property_read_u32(dev, "maxim,gpio-rx-id", &rx_id);
	if (ret) {
		dev_err(dev, "maxim,gpio-rx-pin without maxim,gpio-rx-id\n");
		return ret;
	}

	if (pin >= MAX96717_GPIO_NUM || rx_id > 0x1f) {
		dev_err(dev, "invalid gpio-rx pin %u / id %u\n", pin, rx_id);
		return -EINVAL;
	}

	/* Receive the tunneled GPIO and drive it out on the pin. */
	ret = regmap_update_bits(priv->regmap, MAX96717_GPIO_A(pin),
				 MAX96717_GPIO_A_GPIO_RX_EN |
				 MAX96717_GPIO_A_GPIO_OUT_DIS,
				 MAX96717_GPIO_A_GPIO_RX_EN);
	if (ret)
		return ret;

	/* Push-pull, needed to drive the sensor's FSIN input. */
	ret = regmap_update_bits(priv->regmap, MAX96717_GPIO_B(pin),
				 MAX96717_GPIO_B_OUT_TYPE,
				 MAX96717_GPIO_B_OUT_TYPE);
	if (ret)
		return ret;

	/* Must match the deserializer's FSYNC_TX_ID. */
	return regmap_update_bits(priv->regmap, MAX96717_GPIO_C(pin),
				  MAX96717_GPIO_C_GPIO_RX_ID,
				  FIELD_PREP(MAX96717_GPIO_C_GPIO_RX_ID, rx_id));
}
```

在 [max96717_probe()](../drivers/media/i2c/maxim-serdes/max96717.c#L1741) 里挂上:

```c
	ret = max96717_gpiochip_probe(priv);
	if (ret)
		return ret;

	ret = max96717_parse_fsync_rx(priv);      /* <-- 新增 */
	if (ret)
		return ret;

	ret = max96717_register_clkout(priv);
```

## A.4 时序安全性(已核查,回答任务 2.8)

| 疑虑 | 核查结论 |
|---|---|
| 后续会不会有 `RESET_ALL` 把配置冲掉? | `max_ser_reset()` 只在两处调用:[max_des.c:1559](../drivers/media/i2c/maxim-serdes/max_des.c#L1559)(改地址,发生在 SER 驱动 probe **之前**)和 [max_des.c:3486](../drivers/media/i2c/maxim-serdes/max_des.c#L3486)(`max_des_shutdown`)。**正常运行期间不会重置**,probe 时配好即长期有效 |
| `max96717_init()` 会不会覆盖 GPIO 寄存器? | 不会。[max96717.c:1424](../drivers/media/i2c/maxim-serdes/max96717.c#L1424) 只碰 `CMU2` / `MIPI_RX0` / tunnel,**不碰 `0x2BE+` 区间** |
| gpiolib 会不会把 MFP7 改回输出? | 只有 `gpiod_get()` 成功 claim 时才会应用 ACPI 的 flags。删掉 `fsin-gpios` 后**没有任何 consumer 会 claim MFP7** |

→ 结论:放在 probe 里一次性配置是安全的,**不需要**退到路径 B。

## A.5 与路径 A / B 的对比

| | 路径 A(原设计) | **路径 C(采用)** | 路径 B(备选) |
|---|---|---|---|
| 做法 | ACPI 声明 pinctrl 状态 | max96717 读 `_DSD` 直接配寄存器 | DES 远程写 SER 寄存器 |
| ACPI 可行 | ❌ pinctrl 无 ACPI map | ✅ | ✅ |
| 改码量 | 0 | ~50 行,单文件 | 需 `max_ser.h` 导出 helper + DES 侧调用 |
| 耦合 | — | 低,SER 自治 | 高,DES 需知道 SER 引脚布局 |
| 上游友好 | — | 好(DT 也能用同一属性) | 一般 |
