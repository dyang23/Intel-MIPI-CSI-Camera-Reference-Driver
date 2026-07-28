# GMSL FSYNC 调试状态与后续计划

日期：2026-07-28（本轮更新）
平台：NODKA unitree (PTL / IPU75XA)，Linux 6.17.0-14-generic
硬件：MAX96724 (DES, i2c-0 @0x27) + 4× MAX9295A (SER @0x40) + 4× Sony ISX031 (@0x1a)
分支：`s36-DongYang`

---

## 1. 一句话总结

**四路快门同步已打通并实测通过。**
MAX96724 内部 FSYNC 发生器直接驱动 GMSL2 反向通道隧道，4 个加串器的 MFP7 同步复现脉冲，
ISX031 在外部脉冲从模式下出帧，**四路快门相位差 0.012 ms**（基线 6.89 ms，改善约 570×）。

上一版文档的核心结论"发生器没有向隧道发送任何信号"**是错的**，原因见 §3.1。

---

## 2. 实测结果

### 2.1 相位测量

`python3 script/fsync_phase_check.py -n 60`（4 路并发，`v4l2_buffer.timestamp`，CLOCK_MONOTONIC）：

```
  /dev/video0:   +0.000 ms  (jitter 0.0000 ms, +0 whole frames)
  /dev/video1:   +0.004 ms  (jitter 0.0004 ms, +1 whole frames)
  /dev/video2:   +0.008 ms  (jitter 0.0005 ms, -1 whole frames)
  /dev/video3:   -0.004 ms  (jitter 0.0004 ms, -1 whole frames)
  worst-case shutter misalignment: 0.012 ms
  => SYNCHRONISED: shutter phase spread 0.012 ms < 2% of the 33.33 ms frame period
```

四路帧率均为 30.00 fps。对比 `doc/gmsl_fsync_baseline.md` 的自由运行基线
（相位差 6.5–6.9 ms，抖动 2.4–11.8 µs），**远优于 100 µs 的目标**。

> "whole frames" 是整帧偏移，属于各路启流先后造成的帧号错位，不是快门错位；
> 折算到一个帧周期内的相位才是真正的快门对齐程度。

### 2.2 确认是驱动自身的路径产生的效果

为排除"手工写寄存器导致同步"的可能，先把发生器强制关掉再启流：

| 时刻 | `FSYNC_0 (0x4A0)` | 周期 `0x4A5-7` | `FSYNC_22 (0x4B6)` |
|---|---|---|---|
| 启流前（人工清零） | `0x0C` 关闭 | `0x000000` | `0x00` |
| **推流中** | **`0x14`** EN_VS_GEN + METH=manual | **`0x0CB735`** | **`0x40` = `FSYNC_LOCKED`** |
| 停流后 | `0x0C`（驱动关闭发生器） | `0x0CB735`（保留） | — |

`FSYNC_ERR_CNT (0x4B0)` 启动瞬间为 `0x09`，之后连续读取恒为 `0x00`。
`FSYNC_17 (0x4B1) = 0x50` → `TX_ID = 0x0A`，与 ASL 里的 `DES_FSYNC_TX_ID` 一致。

即：周期、`TX_ID`、使能全部由驱动在 stream-on 时写入，stream-off 时关闭。

### 2.3 四路加串器引脚实测翻转

推流中采样各 SER 的 `GPIO_A(7) = 0x2D3`，bit3 = `GPIO_IN`：

```
  i2c-7  (link0): 0x84 ×29  0x8C ×11
  i2c-17 (link1): 0x84 ×29  0x8C ×11
  i2c-20 (link2): 0x84 ×33  0x8C ×7
  i2c-21 (link3): 0x84 ×31  0x8C ×9
```

`0x8C` = `GPIO_IN` 为高。四路占空比一致（约 75/25），与 30 fps 周期相符。

---

## 3. 上一轮结论为何是错的

### 3.1 观测点选错了：MAX9295A 的 `GPIO_C` bit6 不是 `GPIO_RECEIVED`

上一版用 SER 的 `GPIO_C (0x2D5) bit6` 当作"隧道收到的值"，采样恒为 `0x4A` 就判定发生器无输出。

**MAX9295A / MAX96717F 的 `GPIO_C` bit6 是 RSVD**，加串器侧根本没有 `GPIO_RECEIVED` 这一位
（那是解串器 `GPIO_C` 才有的）。`0x2D5` 复位值即 `0x47`，bit6 本来就是 1。
也就是说，那个实验一直在盯着一个**永远不会变化**的位。

正确的观测点是 `GPIO_A(7) = 0x2D3` 的 bit3（`GPIO_IN`，只读的引脚实际电平）。

### 3.2 用正确观测点重做实验

把周期设到最大 `0xFFFFFF`（≈ 0.671 s，半周期 335 ms），遍历 `FSYNC_0`：

```
FSYNC_0=0x00 回读 0x00   SER0 0x2D3 采样到：0x84 0x8C   ← 有跳变
FSYNC_0=0x04 回读 0x04   SER0 0x2D3 采样到：0x84 0x8C   ← 有跳变
FSYNC_0=0x10 回读 0x10   SER0 0x2D3 采样到：0x84 0x8C   ← 有跳变
FSYNC_0=0x14 回读 0x14   SER0 0x2D3 采样到：0x84 0x8C   ← 有跳变
METH=01 / METH=10，以及 0x40 / 0x50 / 0x54：只有 0x84   ← 无跳变
```

结论：

- 发生器、GMSL2 隧道、加串器 MFP7 复现，**整条链路本来就是通的**。
- 生效条件是 `FSYNC_METH = 00`（Manual）；`FSYNC_MODE` 取 `0b00`（纯隧道源）
  或 `0b01`（GPIO 输出）**都可以**。
- **不需要**把脉冲先注入解串器本地 MFP 再进隧道。上一版步骤 1 想验证的"本地 MFP 注入"
  路径不是必需的。

### 3.3 仍然成立的发现：MAX96724 GPIO 寄存器地址不是均匀步进

这一条与上一版一致，是一个独立的真实 Bug。从数据手册提取的实际地址（link0 `GPIO_B` 列）：

```
0x301 0x304 0x307 0x30A 0x30D  0x311  0x314 0x317 0x31A 0x31D  0x321
  +3    +3    +3    +3    +4     +3     +3    +3    +3    +4
```

**GPIO4 之后和 GPIO9 之后各有一个 1 字节空洞**（寄存器按 16 字节分页排布）：

| GPIO | A | B | C |
|---|---|---|---|
| 0–4 | `0x300 + n*3` | +1 | +2 |
| 5 | **0x310** | 0x311 | 0x312 |
| 6 | 0x313 | 0x314 | 0x315 |
| **7** | **0x316** | **0x317** | **0x318** |
| 8 | 0x319 | 0x31A | 0x31B |
| 9 | 0x31C | 0x31D | 0x31E |
| 10 | **0x320** | 0x321 | 0x322 |

原宏 `MAX96724_GPIO_A(x) = 0x300 + x*3` 对 pin 7 算出 `0x315`，而 `0x315` 实际是
**GPIO6 的 `GPIO_C`**。

**本轮新增发现**：link1/2/3 各有**自己的** `GPIO_B`/`GPIO_C` 对（存放
`GPIO_TX_ID_x`/`GPIO_TX_EN_x`/`TX_COMP_EN_x` 与 `GPIO_RX_ID_x`/`GPIO_RX_EN_x`/`GPIO_RECEIVED_x`），
基址分别为 `0x337…` / `0x36D…` / `0x3A4…`，同样带不规则空洞。
`GPIO_A` 只有 link0 一份，是全芯片共享的引脚方向寄存器。
现已在 `max96724.c` 里改为 4×11 的地址查表。

> 加串器（MAX9295A / MAX96717F）的 GPIO 寄存器是**均匀步进 3、没有空洞**
> （`GPIO_A(x) = 0x2BE + x*3`，GPIO7 = `0x2D3/4/5`，复位值 `0x83/0xA7/0x47`），
> 现有 `max96717.c` 的实现是正确的，已用回读验证。

### 3.4 其他

- DES 本地 MFP7 引脚：即使设 `OUT_DIS=0` + 推挽 + `GPIO_OUT=0`，`GPIO_IN` 仍恒读 1，
  本板上可能有外部上拉或被复用，**不适合作为本地观测点**。既然隧道直连可用，这一点已无影响。
- 停流后 `FSYNC_22 (0x4B6) = 0x00` 属正常（驱动在最后一路停流时关闭发生器）。
- 上一版所述"整机相机完全不出流的回归状态"**未能复现**，四路均正常出流。

---

## 4. 当前代码状态

| 文件 | 内容 | 状态 |
|---|---|---|
| `drivers/media/i2c/maxim-serdes/max_des.h` | `struct max_des_fsync`、`set_fsync` op、`fsync_active`、`MAX_DES_FSYNC_NO_GEN_PIN` | ✅ 已验证 |
| `drivers/media/i2c/maxim-serdes/max_des.c` | `max_des_parse_fsync_dt()`、`max_des_update_fsync()` 的 enable/disable 钩子与回滚 | ✅ 已验证 |
| `drivers/media/i2c/maxim-serdes/max96724.c` | FSYNC 寄存器模型、`max96724_set_fsync()`、GPIO 地址查表、`log_status` | ✅ FSYNC 路径已验证 |
| `drivers/media/i2c/maxim-serdes/max96717.c` | `max96717_parse_gpio_rx()`，写 `GPIO_A/B/C` | ✅ 已回读验证 |
| `drivers/media/i2c/isx031.c` | `sony,external-sync` → `isx031_framesync_reg_list` | ✅ 已验证 |
| `acpi/_des_common_max96724.asl` | `maxim,fsync-fps` / `-tx-id` / `-link-mask` / `-gen-pin` | ✅ |
| `acpi/_ser_common_max9295.asl` | `maxim,gpio-rx-pin` / `maxim,gpio-rx-id` | ✅ |
| `acpi/_cam_common_isx031.asl` | `sony,external-sync` | ✅ |
| `acpi/nodka_unitree/…_4x_sensing_isx031.asl` | 30 fps / TX_ID 0x0A / link mask 0x0F；4 通道 `GPIO_RX_PIN=7`、`GPIO_RX_ID=0x0A`、`EXTERNAL_SYNC=1` | ✅ |

### 4.1 尚未在硬件上跑过的代码路径

- `maxim,fsync-gen-pin`（`max96724_set_fsync_gen_pin()`）：本板不需要，属可选功能。
  其寄存器序列已用 I2C 手工验证，但**驱动代码本身未被执行过**。
- 无 `gen_pin` 时 `FSYNC_MODE` 的默认值由 `0b01`（GPIO out）改为 `0b00`（纯隧道源）。
  §3.2 的扫描证明两者都能工作，但 0.012 ms 的端到端实测是在 `0b01` 下取得的，
  **`0b00` 需要重启后复测**。
- 新编译的 DKMS 模块尚未生效（本平台热重载失败），当前运行的仍是旧模块。

---

## 5. 接下来的步骤

### 步骤 1（P0）— 重启后用新模块复测 ✅ 待执行

`/media/ndk/Dong_U1/scripts/rebuild_camera_driver.sh` 已构建安装成功，需 `sudo reboot` 生效。
重启后重跑 `script/fsync_phase_check.py -n 60`，确认：

- 相位差仍 < 100 µs（新默认 `FSYNC_MODE=0b00`）；
- `FSYNC_0` 推流中读回 `0x10`（而非旧模块的 `0x14`）；
- `FSYNC_22` bit6 `FSYNC_LOCKED = 1`，`FSYNC_ERR_CNT = 0`。

若 `0b00` 出现异常，把 `max96724_set_fsync()` 里的默认 `mode` 改回
`MAX96724_FSYNC_0_FSYNC_MODE_GPIO_OUT` 即可（已实测可用的配置）。

### 步骤 2（P1）— 长跑与状态检查

- 4 路并发长跑 30 分钟，统计掉帧与 `FSYNC_ERR_CNT (0x4B0)`。
- `v4l2-ctl --log-status` 检查 `fsync: locked / err_cnt`。

### 步骤 3（P2）— 收尾

- 更新 `doc/gmsl_fsync_plan.md` 的任务勾选状态。
- 回归测试 `acpi/nodka_unitree/` 下其他 overlay（未声明 fsync 属性的应完全不受影响）。
- 按 5 个 patch 拆分提交，英文 commit message，跑 `checkpatch.pl --strict`。

### 附：回退到自由运行（如需）

```
在 acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl 中
删除 4 个通道块里的 #define DESCH_CAM_EXTERNAL_SYNC 1
→ ./script/gen_ssdt.sh <asl> → sudo reboot
```

传感器回到自由运行模式（代价：无同步，相位差 6.5–6.9 ms）。

---

## 6. 有用的命令速查

```bash
# 编译并部署 SSDT
./script/gen_ssdt.sh acpi/nodka_unitree/ndk_unitree_max96724_mipi0_4x_sensing_isx031.asl
sudo reboot

# 编译并安装驱动（DKMS）
/media/ndk/Dong_U1/scripts/rebuild_camera_driver.sh        # 之后需 reboot
                                                            # 加 -r 尝试热重载（本平台会失败）

# 本开发环境的免密 root
export SUDO_ASKPASS=$PWD/script/askpass.sh && sudo -A <cmd>

# 关键寄存器
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xA0 r1   # DES FSYNC_0
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xA5 r1   # DES 周期 LSB（0x4A5-7，小端）
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xAF r1   # DES FSYNC_15
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xB0 r1   # DES FSYNC_ERR_CNT
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xB1 r1   # DES FSYNC_17 (TX_ID)
sudo -A i2ctransfer -y -f 0  w2@0x27 0x04 0xB6 r1   # DES FSYNC_22 (bit6 LOCKED)
sudo -A i2ctransfer -y -f 7  w2@0x40 0x02 0xD3 r1   # SER0 GPIO_A(7)，bit3 = 引脚电平 ★正确观测点
#   注意：SER 的 GPIO_C(0x2D5) bit6 是 RSVD，不是 GPIO_RECEIVED，不要用它观测

# 相位测量
python3 script/fsync_phase_check.py -n 60

# 链路总线映射：link0=i2c-7  link1=i2c-17  link2=i2c-20  link3=i2c-21

# 日志（dmesg 需要 root）
journalctl -k -b | grep -iE "isx031|max9671|max96724|fsync"
```
