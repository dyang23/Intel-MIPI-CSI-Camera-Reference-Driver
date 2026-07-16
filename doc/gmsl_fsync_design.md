# GMSL 多相机快门同步 (FSYNC) 设计与开发计划

> 目标器件:MAX96724(反序列器 / deserializer)+ MAX9295(序列器 / serializer)+ ISX031(相机)
> 目标驱动:新驱动 `drivers/media/i2c/maxim-serdes/`(Maxim 官方框架),老驱动 `ipu6-drivers/.../max9x/` 仅作参考
> 文档状态:设计评审稿(编码前对齐用)
> 最后更新:2026-07-20

---

## 1. 需求背景

在环视 / 拼接 / 立体等场景中,多个相机的图像需要在**同一时刻曝光**,拼接出来的画面才有意义;
否则运动物体会在拼接缝处错位、双目视差失真。

典型用例:MIPI0 上挂 4 个同型号 ISX031,组成环视阵列,要求 4 路相机曝光快门在硬件层面对齐到同一帧率(如 30fps)。

### 期望的硬件方案(已确认可行)

```
MAX96724 内部 FSYNC 生成器 (25MHz 晶振, Manual 模式)
    │   周期 = f_clk / fps      (30fps → 25_000_000/30 = 833333 = 0x0CB735)
    ▼
GMSL2 反向通道 GPIO 隧道        (反序列器 FSYNC_TX_ID  ⇄  序列器 GPIO_RX_ID 匹配)
    ▼
MAX9295 的 MFP 引脚 (RX 模式)   收到隧道脉冲后在物理引脚复现
    ▼
ISX031 的 FSIN/XVS 引脚         (external pulse-based sync 从模式)
```

该链路与 MAX96724 数据手册第 “Frame Sync” 章节(`doc/max96724.txt:2466`)描述完全一致:

> "The MAX96724/F/R can generate FSYNC signal internally … and send it over to the sensor through the GMSL reverse channel … To generate the internal FSYNC, the MAX96724/F/R are programmed as masters."

相机同步手册明确推荐开启 **delay-compensated GPIO 模式**(`TX_COMP_EN`),以保证多路脉冲相位一致(`doc/max96717f.txt:3153`)。

---

## 2. 硬件寄存器机制(数据手册摘录)

### 2.1 MAX96724 FSYNC 生成器(寄存器块 0x04A0–0x04B7)

| 寄存器 | 偏移 | 关键字段 | 说明 |
|---|---|---|---|
| FSYNC_0 | `0x4A0` | bit4 `EN_VS_GEN` | 使能内部生成器 |
|  |  | bit3:2 `FSYNC_MODE` | `01` = 生成器开、GPIO 作 FSYNC 输出驱动从设备(隧道用此模式) |
|  |  | bit1:0 `FSYNC_METH` | `00` = Manual(用显式周期);`01` semi-auto;`10` auto |
|  |  | bit5 `FSYNC_OUT_PIN` | 本地输出引脚 MFP0/MFP7(隧道模式非必需) |
| FSYNC_1 | `0x4A1` | `FSYNC_PER_DIV` | 每几个 VSYNC 发一次(0 = 每帧) |
| FSYNC_2 | `0x4A2` | `MST_LINK_SEL` / `K_VAL` | semi/auto 的主链路与相位裕量 |
| FSYNC_5/6/7 | `0x4A5/6/7` | `FSYNC_PERIOD_L/M/H` | **24 位周期(LSB 优先)**,Manual 模式有效 |
| FSYNC_15 | `0x4AF` | bit7 `FS_GPIO_TYPE` | `1` = GMSL2 类型 |
|  |  | bit6 `FS_USE_XTAL` | `1` = 用 25MHz 晶振作时基(与视频无关,推荐) |
|  |  | bit4 `AUTO_FS_LINKS` | `1` = 所有使能链路;`0` = 用下面位图 |
|  |  | bit3:0 `FS_LINK_3..0` | **每链路选择位图(多相机分组的关键)** |
| FSYNC_17 | `0x4B1` | bit7:3 `FSYNC_TX_ID` | GMSL GPIO 通道 ID(复位 0x1E=30),须与序列器 RX_ID 匹配 |
| FSYNC_22 | `0x4B6` | bit6 `FSYNC_LOCKED` / bit7 `LOSS_OF_LOCK` | 锁定状态(调试用) |

**周期公式**:`FSYNC_PERIOD = f_clk / fps`,`FS_USE_XTAL=1` 时 `f_clk = 25 MHz`。
- 30 fps → 833333 = `0x0CB735` → L=`0x35`, M=`0xB7`, H=`0x0C`
- 60 fps → 416666 = `0x065B9A`;15 fps → 1666666 = `0x196E2A`

### 2.2 GMSL GPIO 隧道(两端 GPIO_A/B/C 三寄存器组)

| 端 | 组基址 | 寄存器 | 字段 | 作用 |
|---|---|---|---|---|
| 反序列器 (MAX96724) | `0x0300 + pin*3` | GPIO_A | bit1 `GPIO_TX_EN` / bit5 `TX_COMP_EN` | 使能该 pin 参与 GMSL2 发送 / 延时补偿 |
|  |  | GPIO_B | bit4:0 `GPIO_TX_ID` | 发送通道 ID(= FSYNC_TX_ID) |
| 序列器 (MAX9295) | `0x02BE + pin*3` | GPIO_A | bit2 `GPIO_RX_EN` / bit0 `GPIO_OUT_DIS` | 使能接收输出 / 清 0 才驱动引脚 |
|  |  | GPIO_B | bit5 `OUT_TYPE` | 推挽输出(驱动传感器 FSIN 用) |
|  |  | GPIO_C | bit4:0 `GPIO_RX_ID` | **接收通道 ID,须 = 反序列器 FSYNC_TX_ID** |

原理:GMSL 包内每个 GPIO 状态带一个 5 位通道 ID(共 32 个);发送端 `GPIO_TX_ID` 打标,接收端 `GPIO_RX_ID` 匹配后在本地引脚复现。

### 2.3 参考寄存器写序列(30fps,以某 GPIO 通道 ID = 0x0A、两端 MFP7 为例)

**反序列器 MAX96724:**
```
0x4B1 = (0x0A << 3)              ; FSYNC_TX_ID = 0x0A
0x4AF = 0xD0                     ; FS_GPIO_TYPE=1(GMSL2) | FS_USE_XTAL=1 | AUTO_FS_LINKS=1
0x4A5 = 0x35 ; 0x4A6 = 0xB7 ; 0x4A7 = 0x0C   ; 周期 833333(30fps)
<MFP7 GPIO_B>.GPIO_TX_ID = 0x0A ; <MFP7 GPIO_A>.GPIO_TX_EN=1 (可选 TX_COMP_EN=1)
0x4A0 = 0x14                     ; EN_VS_GEN=1 | FSYNC_MODE=01 | FSYNC_METH=00(Manual)
```

**序列器 MAX9295(每路,MFP7):**
```
<MFP7 GPIO_C>.GPIO_RX_ID = 0x0A
<MFP7 GPIO_A>.GPIO_RX_EN=1, GPIO_OUT_DIS=0 (可选 TX_COMP_EN=1)
<MFP7 GPIO_B>.OUT_TYPE=1         ; 推挽
```

**验证:** 读 `0x4B6` `FSYNC_LOCKED`=1;`0x4B0 FSYNC_ERR_CNT` 应保持 0;示波器抓 MFP7 应为 30Hz 脉冲。

---

## 3. 现状分析:核心功能尚未实现

| 位置 | 状态 |
|---|---|
| **新驱动 `maxim-serdes/`(主用)** | ❌ **完全无 FSYNC 生成器代码**;反序列器 `max96724.c` 连 gpiochip/MFP 抽象都没有。✅ 但序列器 `max96717.c` 的 GPIO 隧道底座**已就绪**(pinctrl + `maxim,tx-id`/`maxim,rx-id` + GPIO_A/B/C),序列器侧几乎可纯靠 ACPI pinctrl 配好。 |
| **老驱动 `max9x/`(已废弃)** | ⚠️ 只做一半:寄存器宏在 `max96724.h` 全定义,但 `max96724.c` 一个都没写;序列器有 `max96717_enable_frame_sync()`,但写死 GPIO8 RX_ID、靠 DT 属性 `fsync-tx-id` 触发 —— 而**所有 ACPI 表都没有该属性**,实际为空操作。 |
| **参考实现** | TI960 反序列器(imx390 平台)有完整的 `ti960_set_frame_sync()`,可作范式参考。 |
| **传感器 `isx031.c`(新)** | ✅ 已会把自身设为 external-pulse 从模式(`0x8AF0=0x01`,条件 `!irq_pin_flags`),并申请一个 `fsin` GPIO。 |

### 3.1 当前板级接线(4×ISX031 环视配置)

`acpi/nodka/nodka_max96724_4x_sensing_isx031_mipi0.asl`:4 路 CH00–CH03,各自 SER0–SER3(MAX9295A @0x40),
每个 SER 把 **MFP7** 作为 FSIN 引脚(`DESCH_SER_EXTRA_GPIO_PIN 7`),`fsin-gpios` 指向该序列器 MFP7,低有效。

### 3.2 关键问题(必须在实现中解决)

1. **当前 FSIN 是"主机经 I²C 驱动序列器 MFP7 且只静态拉低",既无周期脉冲、也无隧道配置** → 现在这 4 路相机实际上**并未硬件同步**(是否出图取决于 ISX031 无脉冲时是否自走,需上机确认)。
2. **引脚职责冲突**:"主机驱动 MFP7 输出" 与 "MFP7 作 GMSL-RX 隧道输出" **互斥**。要走本方案,ISX031 侧就**不能再 claim/驱动** 这个 `fsin` GPIO,MFP7 应配成 RX 模式。
3. **反序列器缺 GPIO 抽象**:`max96724.c` 没有 gpiochip/pinctrl,也没有任何 GPIO 隧道寄存器建模,生成器和 TX 隧道都要新写。

---

## 4. 何时开启同步(启用策略)

判据是"**是否要把多路画面当作同一帧联合使用**",而非单纯相机数量:

| 场景 | 是否开 | 说明 |
|---|---|---|
| 1 个相机 | 否 | 无对象可对齐 |
| 2/3/4 个**同型号**、做拼接/环视/立体 | **是** | 核心场景;用 `FS_LINK_x` 位图精确选中这几路 |
| 多相机但各自独立取流(不拼接) | 否(可选) | 同步无害但无意义,徒增耦合 |
| 混接**不同型号**(如 ISX031 + RealSense D457) | **不跨型号统一开** | 帧率/触发/时序不同;D457 是带自身同步的整机模块。正确做法:按"同型号同帧率且都支持外触发"**分组**分别同步(硬件 per-link 位图正好支持) |

### 启用方式:配置声明式 + 运行时可控(不纯靠数量自动判断)

1. **不建议**驱动仅凭"接了 N 个相机"自动开 —— 驱动无法区分"环视阵列"与"N 个独立用途"。
2. **主路径:ACPI/DT 声明** —— 由板级配置(最懂拓扑者)声明 fsync 组:哪些 link、fps、哪个 MFP、tx/rx id。开流时对这些 link 自动启用。换板零改码。
3. **补充:一个 v4l2 control** —— 运行时开关 / 改频率,便于调试与特殊用途。
4. **默认行为**:仅当板级配置声明了 fsync 组时才启用;未声明则保持现状(不同步)。

---

## 5. 架构设计

### 5.1 数据结构与配置

在共享层 `max_des.h` 的 `struct max_des` 增加 fsync 配置:

```c
struct max_des_fsync {
    bool     enabled;        /* 板级声明了 fsync 组才为真 */
    u32      fps;            /* 目标帧率,如 30 */
    bool     use_xtal;       /* 用 25MHz 晶振时基(默认真) */
    u8       tx_id;          /* GMSL GPIO 通道 ID(默认 0x1E) */
    u8       gen_gpio;       /* 反序列器承载脉冲的 GPIO/MFP 号 */
    u16      link_mask;      /* 参与同步的链路位图(bit0..3) */
    bool     comp_en;        /* delay 补偿 */
};
```

序列器侧的 `rx_id` 与 MFP 引脚,优先复用现有 `max96717` pinctrl 参数(`maxim,rx-id`),通过 ACPI 声明,尽量不新增序列器代码。

### 5.2 反序列器 ops 扩展

在 `struct max_des_ops`(`max_des.h`)增加:

```c
int (*set_fsync)(struct max_des *des, const struct max_des_fsync *cfg, bool enable);
```

在 `max96724.c` 实现 `max96724_set_fsync()`:
- 新增 FSYNC 与 GPIO 隧道寄存器 `#define`(0x4A0–0x4B6、0x0300+ 组);
- 按 §2.3 序列写寄存器;`enable=false` 时清 `EN_VS_GEN`;
- 遵循驱动"仅在真实变化时写硬件"的约定,避免打扰已在流的兄弟链路。

### 5.3 使能触发点(挂在开流路径)

`max_des.c` 的 `max_des_update_streams()` 中,`max_des_update_active(..., true)` 之后(约 line 2625)调用
`des->ops->set_fsync(des, &des->fsync, true)`;关流/回滚路径对称 `set_fsync(..., false)`。

### 5.4 序列器侧 MFP7 = RX 模式(解决冲突)

两种实现路径,择一:
- **A(优先,少改码)**:在 ACPI 里把 SER MFP7 配成 GMSL-RX(`maxim,rx-id` = tx_id、`GPIO_RX_EN`),并**移除该路 ISX031 的 `fsin-gpios`**,让 ISX031 不再 claim/驱动该 pin。
- **B(编码)**:反序列器在 link bring-up 时,通过 `max_ser.c` 导出的 helper 主动配置远端序列器 MFP7 的 RX_ID/RX_EN。

### 5.5 端到端框图

```
                 ┌──────────────── MAX96724 (DES) ──────────────┐
 25MHz XTAL ───▶ │ FSYNC gen (Manual, period=f/fps)             │
                 │        │ TX_ID=0x0A                           │
                 │        ▼                                      │
                 │  GPIO(TX_EN, TX_ID=0x0A, TX_COMP_EN) ─────────┼──┐ GMSL2 反向通道
                 │  FS_LINK_mask 选中 link 0..3                  │  │ (GPIO 隧道)
                 └───────────────────────────────────────────────┘  │
                                                                     ▼ (广播到各链路)
   ┌── MAX9295 #k (SER) ──┐                                   每路序列器:
   │ MFP7: RX_EN, RX_ID=0x0A, OUT_TYPE=推挽 ├──▶ ISX031 FSIN (external-sync 从模式)
   └──────────────────────┘
```

---

## 6. 开发计划(分阶段)

### 阶段 0 — 现状确认(上机,~0.5 天)
- 抓当前 4×ISX031 的 MFP7 波形,确认是否有脉冲、是否已同步;
- 记录 `irq_pin_flags` 在当前 ACPI 下的取值,确认 `isx031_framesync_reg` 是否已写入。
- **产出**:一份现状测量记录,作为对照基线。

### 阶段 1 — 反序列器 FSYNC 生成器(核心,~2 天)
- `max96724.c` 新增 FSYNC / GPIO 隧道寄存器定义与 `max96724_set_fsync()`;
- `max_des.h` 加 `struct max_des_fsync` 与 `set_fsync` op;
- 先用**硬编码 30fps + 固定 tx_id + AUTO_FS_LINKS** 打通,示波器验证 MFP(本地输出)脉冲。
- **产出**:反序列器能稳定产生 30Hz 脉冲;`FSYNC_LOCKED` 置位。

### 阶段 2 — GMSL 隧道 + 序列器 RX(~2 天)
- 反序列器承载 GPIO 配 `TX_EN/TX_ID/TX_COMP_EN`;
- 序列器 MFP7 配 `RX_EN/RX_ID/推挽`(优先走 ACPI 路径 A);
- **移除对应 ISX031 的 `fsin-gpios`**,解决引脚冲突;
- 示波器验证脉冲穿过 GMSL 到达序列器 MFP7 与传感器 FSIN。
- **产出**:单路端到端脉冲贯通。

### 阶段 3 — 多相机分组 + 使能策略(~2 天)
- `max_des_parse_dt()` 解析板级 fsync 组声明(fps / link_mask / tx_id / gpio);
- 用 `FS_LINK_x` 位图只选中环视组的 4 路;
- 在 `max_des_update_streams()` 挂 `set_fsync`,开/关流对称;
- 增加一个 v4l2 control 做运行时开关(可选,放后)。
- **产出**:4×ISX031 开流即同步,关流即停;混接场景不误开。

### 阶段 4 — 验证与固化(~1.5 天)
- 4 路同步验证:同时对准同一运动/闪烁光源,比对帧间相位;检查 `FSYNC_ERR_CNT`;
- 帧率切换(15/30/60)、S3/S4 休眠恢复、单路热插拔回归;
- 补文档与 ACPI 样例;patch 拆分(注意:**commit message 必须英文**)。
- **产出**:可评审的 patch 集 + 测试报告。

### 里程碑
| 阶段 | 交付 | 预计 |
|---|---|---|
| 0 | 现状基线 | 0.5d |
| 1 | 反序列器脉冲 | 2d |
| 2 | 端到端单路贯通 | 2d |
| 3 | 多相机分组 + 策略 | 2d |
| 4 | 验证固化 | 1.5d |

---

## 7. 风险与待确认项

1. **ISX031 external-pulse 从模式的确切行为**:无脉冲时是否自走、脉冲极性/最小宽度/建立时间要求 —— 需查 ISX031 手册 `doc/SG3S-ISX031C-GMSL2F-Hxxx_en.pdf` 或实测。
2. **MFP7 是否被其它功能占用**:当前 ACPI 已把 MFP7 作 host-GPIO,改 RX 后原用途是否还需要。
3. **delay 补偿**:4 路 GMSL 线缆长度不同可能导致相位差,`TX_COMP_EN` 是否够用需实测。
4. **与老驱动共存**:本方案只改新驱动;老驱动保持不动。
5. **上游可维护性**:优先在共享层加通用 `set_fsync` op,便于其它反序列器(如 max9296a)将来复用。

---

## 8. 关键文件索引

| 文件 | 作用 |
|---|---|
| `drivers/media/i2c/maxim-serdes/max96724.c` | 反序列器:新增 FSYNC 生成器 + GPIO 隧道 TX(阶段 1/2) |
| `drivers/media/i2c/maxim-serdes/max_des.{c,h}` | 共享层:`struct max_des_fsync`、`set_fsync` op、解析与使能钩子(阶段 1/3) |
| `drivers/media/i2c/maxim-serdes/max96717.c` | 序列器:GPIO 隧道底座已就绪,优先 ACPI 复用(阶段 2) |
| `drivers/media/i2c/isx031.c` | 传感器:external-sync 已就绪;需处理 `fsin` gpio 冲突(阶段 2) |
| `acpi/nodka/nodka_max96724_4x_sensing_isx031_mipi0.asl` | 4×环视板级配置:声明 fsync 组、MFP7 RX、移除 fsin-gpios(阶段 2/3) |
| `doc/max96724.txt` / `doc/max9295d.txt` / `doc/max96717f.txt` | 数据手册(FSYNC 与 GPIO 隧道寄存器出处) |

---

*本文档为编码前设计评审稿;阶段 0 现状确认结果可能微调阶段 1 起始假设。*
