# GMSL FSYNC — 阶段 0 现状基线测量记录

> 对应 [gmsl_fsync_plan.md](gmsl_fsync_plan.md) 阶段 0 的"产出"
> 测量日期:2026-07-28
> 配置:[ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl](../acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl)
> 内核:6.17.0-14-generic,主机 `ndk-Default-string`

---

## 1. 一句话结论

**4 路 ISX031 目前"频率已锁、相位未对齐"** —— 帧率完全一致(30.00 fps,漂移 < 0.4 ppm),
但快门相位相差 **6.5–6.9 ms,约为帧周期的 20%**。
根因是传感器**从未被置入外触发从模式**(见 §4),FSIN 线形同虚设。

---

## 2. 平台与拓扑

| 器件 | I²C | media entity | subdev |
|---|---|---|---|
| MAX96724 (DES) | `0-0027` | 457 | `/dev/v4l-subdev4` |
| MAX9295A (SER) ×4 | `7-0040` `17-0040` `18-0040` `21-0040` | 479 / 485 / 491 / 497 | subdev5..8 |
| ISX031 ×4 | `22-001a` `23-001a` `24-001a` `25-001a` | 503 / 507 / 511 / 515 | subdev9..12 |

取流节点:`/dev/video0..3`,格式 **1920×1536 UYVY**(`Bytes per Line 3840`,`Size Image 5902080`)。

### 2.1 长稳性(任务 0.2)

启动 07-27 16:56,4 路 `gst-launch-1.0` 连续预览 **约 17 小时**无掉流。
`journalctl -k -b` 中无相机相关 error。

> 顺带澄清两条无害日志,避免后来者误查:
> - `File kernel/firmware/acpi/ndk_unitree_max96724_mipi0_4x_sensing_isx031.aml exceeding MAX_CPIO_FILE_NAME [18]`
>   —— 仅截断记录用的文件名([lib/earlycpio.c:129](file:///media/ndk/Dong_U1/dev/linux-6.17/lib/earlycpio.c)),AML 数据照常返回,SSDT 正常加载
> - `WARNING at fs/exec.c:118 path_noexec` —— 从 noexec 挂载的 U 盘执行脚本导致,与相机无关

---

## 3. 帧率与相位测量(任务 0.6 / 0.7)

工具:[script/fsync_phase_check.py](../script/fsync_phase_check.py)(本次新增),
读取每帧 `v4l2_buffer.timestamp`(CLOCK_MONOTONIC,已确认 `V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC`),
4 路同时开流、以屏障对齐 STREAMON,丢弃前 15 帧热身。

### 3.1 结果

```
$ python3 script/fsync_phase_check.py -n 900

  /dev/video0:  900 frames   30.00 fps  clock=monotonic
  /dev/video1:  900 frames   30.00 fps  clock=monotonic
  /dev/video2:  900 frames   30.00 fps  clock=monotonic
  /dev/video3:  900 frames   30.00 fps  clock=monotonic

shutter phase vs /dev/video0, folded into the 33.33 ms frame period:
  /dev/video0:   +0.000 ms  (jitter 0.0000 ms, +0 whole frames)
  /dev/video1:   +2.074 ms  (jitter 0.0040 ms, +1 whole frames)
  /dev/video2:   +6.890 ms  (jitter 0.0024 ms, +3 whole frames)
  /dev/video3:   +4.597 ms  (jitter 0.0118 ms, +2 whole frames)

  worst-case shutter misalignment: 6.890 ms
  => NOT SYNCHRONISED: shutter phase spread 6.89 ms = 21% of the 33.33 ms frame period
```

两次独立测量(300 帧 / 900 帧)一致:

| 指标 | 300 帧(10 s) | 900 帧(30 s) |
|---|---|---|
| 各路帧率 | 30.00 fps ×4 | 30.00 fps ×4 |
| 快门相位极差 | **6.542 ms**(20%) | **6.890 ms**(21%) |
| 单路相位抖动 | 1.1 – 4.4 µs | 2.4 – 11.8 µs |

### 3.2 关键推论:频率已经锁定,只差相位

30 秒内相位抖动仅 **2.4 – 11.8 µs**,折合频率偏差 **< 0.4 ppm**。
独立晶振之间典型偏差 10–100 ppm,30 秒会累积 **300 µs – 3 ms** 的漂移 —— 实测低两个数量级。

→ **4 个传感器共用同一时基**,极可能是 MAX9295 的 RCLKOUT(由 GMSL 链路时钟派生,
最终溯源到 MAX96724)驱动 ISX031 的 INCK。ASL 里
[_cam_common_isx031.asl:62](../acpi/_cam_common_isx031.asl#L62) 声明 `mipi-img-clock-frequency = 96 MHz` 与之相符。
*(时钟走线的物理确认需查原理图,但频率锁定这一**测量事实**不依赖于机制解释。)*

**这对项目是好消息**:FSYNC 只需要解决**相位**,不需要对抗频率漂移。
预期上同步后极差应从 6.9 ms 收敛到 µs 量级。

### 3.3 相位在会话内稳定、跨会话随机

两次测量的绝对相位不同(如 video2:第一次 -4.453 ms,第二次 +6.890 ms),
但**单次会话内**抖动只有几 µs。即:每次 STREAMON 重新随机化相位关系,之后锁死。
这是"频率锁定 + 相位自由"的典型特征,与 §4 的结论互相印证。

> **对验收的影响**:阶段 4.1 复测必须与本基线**同样的方式**(同一脚本、同样帧数),
> 且不能只跑一次 —— 跨会话相位随机,单次结果不足以判定。

---

## 4. ❗根因:传感器从未进入外触发从模式(任务 0.5)

`journalctl -k -b` 中 4 路 ISX031 **全部**打印:

```
isx031 i2c-INTC113C:00: No platform data provided
isx031 i2c-INTC113C:01: No platform data provided
isx031 i2c-INTC113C:02: No platform data provided
isx031 i2c-INTC113C:03: No platform data provided
```

即 [isx031.c:1017](../drivers/media/i2c/isx031.c#L1017) 取到的 `client->dev.platform_data == NULL`。
而写入外同步寄存器的条件是 [isx031.c:508](../drivers/media/i2c/isx031.c#L508):

```c
if (isx031->platform_data && !isx031->platform_data->irq_pin_flags) {
        ret = isx031_write_reg_list(client, &isx031_framesync_reg_list, false);
```

第一个条件即为假 → **`0x8AF0 = 0x01`(external pulse-based sync)从来没有被写入**。

### 4.1 为什么 platform_data 是 NULL

`irq_pin_flags` 只在老的 `ipu-acpi-pdata` 控制逻辑里、且仅当 BIOS 声明了 `GPIO_READY_STAT` 时才置位
([ipu-acpi-pdata.c:571](../ipu7-drivers/drivers/media/platform/intel/ipu-acpi-pdata.c#L571))。
本平台走的是新的 `mipi-disco-img` / `ipu_bridge` 流程,**不填 `platform_data`**。
→ 这段判断在本平台恒不成立,是**死逻辑**。

### 4.2 推论链

1. 4 路 ISX031 一直工作在**默认自走(master)模式**,不理会 FSIN 电平
2. 这解释了为什么"FSIN 被静态拉低"却照常出图 —— 设计文档 §3.2.1 的疑问**已解答:会自走**
3. 也解释了 §3.2 的现象:共用时钟 → 频率一致;各自自走 → 相位随机

### 4.3 对开发计划的影响

- **阶段 2 必做**:让 `0x8AF0=0x01` 真正写下去,判据从 `platform_data->irq_pin_flags`
  改为 fwnode 属性驱动。否则 FSYNC 脉冲送到传感器**也不会被理会**
- 原任务 2.4「确认移除 fsin-gpios 后 framesync 仍会写入」的前提不成立,已改写
- 见计划文档风险项 **R10**

---

## 5. 引脚占用现状

4 路均打印 `Fsin gpio found` 与 `Reset gpio found`,即每路 ISX031 都成功 claim 了
自己那颗 MAX9295A 的 MFP7 并静态驱动为低。这与 GMSL-RX 隧道输出**互斥**,
是设计文档 §3.2.2 描述的冲突,阶段 2.A 拆除。

> [isx031.c:1014](../drivers/media/i2c/isx031.c#L1014) 的注释预期"同一 MAX9295 后的姊妹传感器会拿到 -EBUSY",
> 但本 4×配置每路各有独立 MAX9295A,所以 4 路都 claim 成功,无 -EBUSY。

---

## 6. 未完成项

| 任务 | 状态 | 原因 / 后续 |
|---|---|---|
| 0.3 示波器抓 MAX9295A MFP7 | **暂缓** | 无示波器。§4 已从逻辑上证明不可能有脉冲,不阻塞开发 |
| 0.4 示波器抓 ISX031 FSIN | **暂缓** | 同上 |
| 0.8 读 DES `0x4A0/0x4AF/0x4B1/0x4B6` | **待做** | 需 root:`/dev/i2c-0` 属 `i2c` 组且当前用户不在组内;`/sys/kernel/debug` 需 root |

### 6.1 关于 v4l2-dbg

`/boot/config-6.17.0-14-generic` 中 **`# CONFIG_VIDEO_ADV_DEBUG is not set`**,
因此 `v4l2-dbg --get-register` 这条读寄存器的路在当前内核上**不可用**。
驱动里 `max_des_ops.reg_read` / `reg_write` 也在 `#ifdef CONFIG_VIDEO_ADV_DEBUG` 之内。

**建议**:阶段 1 开始写寄存器前,考虑开启该选项重编内核,后续调试会方便很多。
临时替代方案是 `i2ctransfer`(需加入 `i2c` 组)。

---

## 7. 基线数据存档

| 文件 | 内容 |
|---|---|
| [fsync_baseline.json](fsync_baseline.json) | 300 帧测量原始结果 |
| [fsync_baseline_900.json](fsync_baseline_900.json) | 900 帧测量原始结果 |

复现命令:

```bash
cd /media/ndk/Dong_U1/dev/Intel-MIPI-CSI-Camera-Reference-Driver
python3 script/fsync_phase_check.py -n 900 --json baseline.json
```
