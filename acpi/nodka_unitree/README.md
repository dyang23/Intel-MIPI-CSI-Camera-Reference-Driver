# NODKA "unitree" 板 (PTL / IPU75XA) — SSDT overlay 说明

本目录下的 SSDT ASL 都是**同一块 NODKA "unitree" 板**上的 camera 配置。
硬件全部一致，区别只在**哪些 GMSL 输入 Link 被启用、每条 Link 上挂什么 camera**。

## 通用硬件配置（所有文件共用）

| 项 | 值 | 备注 |
| --- | --- | --- |
| 平台 | PTL / IPU75XA | Intel |
| Deserializer | MAX96724 | I²C 地址 `0x27`，位于 `\_SB.PC00.I2C0`（I2C bus 0） |
| DES → IPU 输出 PHY 类型 | **C-PHY** | `DES_PHY_TYPE = 0` |
| DES 内部 TX PHY | **PHY0** = "cphy A" | `DES_INTERNAL_PHY = 4`，PHY 扫描 (D→C→B→A) 后**只有 PHY A 能出图**，其它 PHY 虽然 I²C / GMSL link lock / mc-setup 都正常，但 `/dev/video0` 无字节，dmesg 报 isys `stream stop time out` |
| IPU MIPI 输入端口 | MIPI port 0 (mipi0) | `DES_TO_MIPI_PORT = 0` |

**术语区分（重要）：**
`"cphy A"`（DES→IPU 的输出 PHY，`DES_INTERNAL_PHY`）与 `GMSL 输入 Link A/B/C/D`（`DESCH_LINK_NUM`）是两个完全不同的概念，容易混。
- 前者是 MAX96724 → SoC 的方向，板上走线固定
- 后者是 camera → MAX96724 的方向，指的是板子外壳上标注 A/B/C/D 的四个物理接头

## GMSL 输入 Link ↔ 端口标号 ↔ ACPI 对象命名对照

MAX96724 有 4 条 GMSL 输入 Link，一一对应板上 4 个外部接头：

| 端口标号 | Link 编号 | ACPI channel | Serializer | Camera i²c-alias |
| --- | --- | --- | --- | --- |
| **port A** | Link 0 | `CH00` | `SER0`  (`\_SB.PC00.DES0.CH00.SER0`) | `0x44` |
| **port B** | Link 1 | `CH01` | `SER1`  (`\_SB.PC00.DES0.CH01.SER1`) | `0x45` |
| **port C** | Link 2 | `CH02` | `SER2`  (`\_SB.PC00.DES0.CH02.SER2`) | `0x46` |
| **port D** | Link 3 | `CH03` | `SER3`  (`\_SB.PC00.DES0.CH03.SER3`) | `0x47` |

Serializer 侧的 I²C 通信地址统一是 `0x40`（远端），MAX96724 会用上表的 alias 值把每条 Link 上的 SER 映射到 DES 侧不同的本地地址，避免总线冲突。相机的 alias 每个文件自行分配（见下）。

---

## 文件说明

### 1. `nodka_unitree_max96724_mixed_sensing_s36_shw3h.asl` — 生产配置（已验证工作）

**Camera 拓扑：**

```
                     MAX96724 (DES, @0x27, I2C0)
                     ┌────────────────────────────┐
Link 0 (port A) ─────┤ CH00 → SER0 (MAX9295D)     ├──→ PHY0 (cphy A)
   ├─ CAM0 ISX031    │  ├─ CAM0 (i2c alias 0x54)  │            │
   └─ CAM1 ISX031    │  └─ CAM1 (i2c alias 0x55)  │            ↓
                     │                            │       MIPI port 0
Link 1 (port B) ─────┤ CH01 → SER1 (MAX9295A)     │       (IPU75XA)
   └─ CAM1 ISX031    │  └─ CAM1 (i2c alias 0x55)  │
                     └────────────────────────────┘
                       Link 2/3 (port C/D) unused
```

- **port A (Link 0)**：S36 模组，用 **MAX9295D** 串行器（2 个 PHY），后接 **2×ISX031** 传感器
- **port B (Link 1)**：SHW3H 模组，用 **MAX9295A** 串行器（1 个 PHY），后接 **1×ISX031** 传感器

**何时用此文件：** 板上同时挂了 S36 和 SHW3H、且需要真正跑图像流的正式配置。

**注意：** 之前 max96717 驱动无条件写 `MIPI_RX0_PHY_CFG_A_AND_B`，会把只有 1 个 PHY 的 MAX9295A 也配成 A+B 拼合模式导致 Link 1 收不到数据。修复见 s36-DongYang 分支的 commit `media: i2c: max96717: Fix setting of MIPI_RX0_PHY_CFG_A_AND_B`。

---

### 2. `NDK_unitree_max96724_s36_3H.asl` — S36 单口 bring-up（3H 尚未启用）

**Camera 拓扑（当前实际启用）：**

```
                     MAX96724 (DES, @0x27, I2C0)
                     ┌────────────────────────────┐
Link 0 (port A) ─────┤ CH00 → SER0 (MAX9295D)     ├──→ PHY0 (cphy A)
   ├─ CAM0 ISX031    │  ├─ CAM0 (i2c alias 0x54)  │            │
   └─ CAM1 ISX031    │  └─ CAM1 (i2c alias 0x55)  │            ↓
                     │                            │       MIPI port 0
                     │  Link 1/2/3 未配置          │
                     └────────────────────────────┘
```

- 只在 **port A (Link 0)** 上启用了 S36（MAX9295D + 2×ISX031），alias `0x54, 0x55`
- 文件底部有 3H 的注释 placeholder（未启用），描述了要挂 3H 时怎么复制粘贴对应的 channel 块（改成 Link 1、CH01、SER1、`_des_ch_common_isx031.asl` 等）

**何时用此文件：**
- 已经确认 S36 挂在 port A 上、想先验证 S36 单独出图，再把 3H 加进来
- 或需要把 S36 换到 port B/C/D 试挂时，改一份就够（比 scan_all 干净得多）—— 具体每个 port 要改哪些字段见文件顶部的注释

---

### 3. `NDK_unitree_max96724_s36_scan_all_links.asl` — 全 Link 诊断（一次性）

**Camera 拓扑：**

```
                     MAX96724 (DES, @0x27, I2C0)
                     ┌────────────────────────────────┐
Link 0 (port A) ─────┤ CH00 → SER0 @0x40 ─ S36        ├──→ PHY0 (cphy A)
                     │        CAM0/CAM1 alias 0x54/55 │            │
Link 1 (port B) ─────┤ CH01 → SER1 @0x40 ─ S36        │            ↓
                     │        CAM/CAM  alias 0x56/57  │       MIPI port 0
Link 2 (port C) ─────┤ CH02 → SER2 @0x40 ─ S36        │
                     │        CAM/CAM  alias 0x58/59  │
Link 3 (port D) ─────┤ CH03 → SER3 @0x40 ─ S36        │
                     │        CAM/CAM  alias 0x5a/5b  │
                     └────────────────────────────────┘
```

**目的（诊断用，非生产）：** 集成商不知道 S36 实际插在哪个物理接头（A/B/C/D）时用。此文件把 4 条 Link 全部按 S36 (MAX9295D) 配好，每条 Link 用一组**互不冲突**的 camera i²c-alias（`0x54/55`, `0x56/57`, `0x58/59`, `0x5a/5b`），启动一次后读 dmesg：

- 有 S36 实体存在的那条 Link，`max9295d` serializer 和 ISX031 sensor 都会 probe 成功
- 其他没插 S36 的 Link，probe 会失败——**这是预期行为**，正是用来定位 S36 位置的信号

**用完就切回：** 确定 Link 编号后，改回 `NDK_unitree_max96724_s36_3H.asl` 并把 `DESCH_LINK_NUM` 设成实测值（或用生产文件 `nodka_unitree_max96724_mixed_sensing_s36_shw3h.asl`）。不要用 scan 文件跑正式流量。

---

## 编译

在仓库根目录：

```bash
bash script/gen_ssdt.sh acpi/nodka_unitree/<file>.asl
```

`script/gen_ssdt.sh` 已改为用 U 盘上的 iasl（`tools/acpica-unix-20260408/generate/unix/bin/iasl`），并带 `-I acpi` 让二级 include（`_ser_common_*.asl`、`_cam_common_*.asl` 等在 `acpi/` 根下的共享文件）能被解析。

## Include 依赖

本目录下的 asl 引用的所有共享文件都在 **父目录 `acpi/`** 里，用 `../` 前缀：

| 顶层文件 | 引用的共享文件 |
| --- | --- |
| 全部 | `../_ipu.asl` (ACPI `Include`), `../_des_common_max96724.asl` (`#include`) |
| 全部 | `../_des_ch_common_s36.asl` — 内部递归引用 `_ser_common_max9295d.asl` + `_cam_common_s36.asl` |
| mixed_s36_shw3h | `../_des_ch_common_isx031.asl` — 内部递归引用 `_ser_common_max9295.asl` + `_cam_common_isx031.asl` |

嵌套的二级 include 不用改路径（iasl `-I acpi` 会替它们兜底）。
