/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA board (PTL / IPU7) — Intel RealSense D405 GMSL camera on
 * GMSL input Link 1 (port B), whose deserializer CSI-2 output is wired to the
 * SoC MIPI2 port. STANDALONE D405 bring-up.
 *
 * Board difference vs. the NODKA "unitree" board:
 *   - This NODKA board exposes only TWO IPU MIPI input connectors, wired to SoC
 *     MIPI port 0 and MIPI port 2 (NOT port 1). The other sensing files in this
 *     directory cover mipi0; this file covers the mipi2 connector.
 *   - Each MIPI connector has its own MAX96724 deserializer @0x27. The I2C
 *     control-channel bus does NOT match the MIPI port number on this board:
 *     the two connectors sit on the ADJACENT I2C controllers, so
 *     mipi0 -> I2C0 and mipi2 -> I2C1 (NOT I2C2). Verified on hardware with
 *     `i2cget -y 1 0x27` (deserializer ACKs on i2c-1; i2c-2 has no device).
 *
 * The D405 itself is declared identically to the unitree reference
 * acpi/nodka_unitree/NDK_unitree_max96724_d405.asl — the only deltas are the
 * board-level DES_TO_MIPI_PORT (0 -> 2) and DES_I2C_BUS (I2C0 -> I2C1).
 *
 * Camera topology:
 *
 *                      MAX96724 (DES0, @0x27, I2C1)
 *                      ┌────────────────────────────┐
 * Link 0 (port A) ─────┤ (unused)                   │
 * Link 1 (port B) ─────┤ CH01 → SER1 (MAX9295A @0x40)├──→ PHY0 (cphy A)
 *    └─ CAM1 D405       │  └─ CAM1 (i2c alias 0x54) │            │
 * Link 2 (port C) ─────┤ (unused)                   │            ↓
 * Link 3 (port D) ─────┤ (unused)                   │       MIPI port 2
 *                      └────────────────────────────┘       (IPU7)
 *
 * Board / hardware configuration:
 *   - Platform IPU MIPI input port  : MIPI port 2   -> DES_TO_MIPI_PORT = 2
 *   - MAX96724 deserializer I2C addr : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus  : I2C1          -> DES_I2C_BUS = "\\_SB.PC00.I2C1"
 *   - DES -> IPU CSI-2 link type      : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")  : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *
 * Sensor physically connected on the GMSL inputs:
 *   - 1x D405 (RealSense D4xx) on GMSL Link 1 (port B) — MAX9295A serializer
 *
 * NOTE: "cphy A" (the DES->IPU output PHY, DES_INTERNAL_PHY) is a DIFFERENT thing
 *       from the GMSL input link A/B/C/D (DESCH_LINK_NUM). The output PHY is
 *       fixed by board routing (PHY0 = "cphy A" is the value verified on the
 *       NODKA/PTL platform). If I2C/GMSL-lock is OK but there is no video, sweep
 *       the internal PHY (DES_INTERNAL_PHY 4->5->6->7) as the nodka_unitree
 *       README documents.
 *
 * D405 specifics (assumed, verify on bring-up):
 *   - HID INTC10CD (D4XX), DPHY link camera-side, 2 data lanes
 *   - Serializer: MAX9295A (INTC1138), single PHY — do NOT use MAX9295D template.
 *     If dmesg shows the serializer probing wrong, swap the DESCH include below.
 *   - d4xx driver detects the exact model at runtime over I2C and forces 2 lanes,
 *     so the ACPI shape matches D457.
 *
 * iasl preprocessor does not support macro-in-macro recursion, so DES_* values
 * must be literal numbers. Trailing comments carry the symbolic name from
 * acpi/_phy_macros_REFERENCE.md:
 *   PHY type:  0 = CPHY, 1 = DPHY
 *   DES PHY:   4..7 for max96724 internal TX PHY 0..3
 *   IPU port:  0..3 for SoC MIPI port 0..3
 */

DefinitionBlock ("", "SSDT", 2, "", "IMG_IPU", 0x20260513)
{
    External (_SB.PC00, DeviceObj)

    Include ("../_ipu.asl")

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            /*
             * Reverse GMSL control-channel I2C speed for the whole DES/SER/CAM
             * chain on this board. NVIDIA reference platforms run this bus at
             * 100 kHz; our default template value is 400 kHz (0x00061A80), which
             * is too fast for the reverse tunnel under streaming stress and
             * wedges the channel (-121 / EREMOTEIO). Force 100 kHz (0x000186A0)
             * here to match NVIDIA and get 4x timing margin. Consumed by
             * _des_common_max96724.asl, _ser_common_max9295.asl and
             * _cam_common_d457.asl via their GMSL_I2C_SPEED #ifndef guard.
             */
            #define GMSL_I2C_SPEED        0x000186A0  /* 100 kHz reverse control channel */

            // ---- DES-level configuration (NODKA board, mipi2 connector) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      6           /* MAX96724_TX_PHY2 ("cphy C") - sweeping A->C to try to get video (was 4/cphy A) */
            #define DES_TO_MIPI_PORT      2           /* IPU_MIPI_PORT_2 (mipi2) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C1"   /* I2C bus 1 (mipi2 connector's control channel - verified via i2cget) */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "../_des_common_max96724.asl"

            // ---- D405 on GMSL input Link 1 (port B) ----
            #define DESCH_LINK_NUM 1
            #define DESCH_CH CH01
            #define DESCH_SER SER1
            #define DESCH_CAM CAM1
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH01"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH01.SER1"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH01.SER1
            #define DESCH_SER_GPIOREF ^^SER1
            #define CAM_ALIAS 0x54
            #define CAM_LANES 2
            #define DESCH_SER_X_VC Package () { 0 }
            #define DESCH_SER_Y_VC Package () { 1 }
            #define DESCH_SER_Z_VC Package () { 2 }
            #define DESCH_SER_U_VC Package () { 3 }
            #include "../_des_ch_common_d457.asl"

            // ---- DES-level cleanup ----
            #undef DES_PHY_TYPE
            #undef DES_I2C_ADDR
            #undef DES_INTERNAL_PHY
            #undef DES_TO_MIPI_PORT
            #undef DES_I2C_BUS
            #undef DES_PATH
            #undef DES_REF
            #undef DES_PIPE_STR_AUTOSELECT
            #undef GMSL_I2C_SPEED
        }
    }
}
