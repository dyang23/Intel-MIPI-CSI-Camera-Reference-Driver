/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA board (PTL / IPU7) — Intel RealSense D4XX (D405/D457)
 * GMSL camera on GMSL input Link 0 (port A), whose deserializer CSI-2 output is
 * wired to the SoC MIPI0 port.
 *
 * Rationale: the mipi2 bring-up (nodka_max96724_d405_mipi2.asl) never got a
 * link / video path up (STREAMON -> -121, PHY sweep A..C did not help). The
 * mipi0 connector, on the other hand, is proven-good with the 4x Sensing ISX031
 * config (nodka_max96724_4x_sensing_isx031_mipi0.asl streams). So this file
 * reuses the mipi0 DES-level block VERBATIM (I2C0, DES_TO_MIPI_PORT=0,
 * DES_INTERNAL_PHY=4 / cphy A) and just drops the single D4XX camera onto
 * GMSL Link 0 (port A). Move the D4XX GMSL cable to the mipi0 connector's
 * Link 0 / port A input before booting this.
 *
 * Camera topology:
 *
 *                      MAX96724 (DES0, @0x27, I2C0)
 *                      ┌────────────────────────────┐
 * Link 0 (port A) ─────┤ CH00 → SER0 (MAX9295A @0x40)├──→ PHY0 (cphy A)
 *    └─ CAM0 D4XX       │  └─ CAM0 (i2c alias 0x54) │            │
 * Link 1 (port B) ─────┤ (unused)                   │            ↓
 * Link 2 (port C) ─────┤ (unused)                   │       MIPI port 0
 * Link 3 (port D) ─────┤ (unused)                   │       (IPU7)
 *                      └────────────────────────────┘
 *
 * Board / hardware configuration (identical to the proven ISX031 mipi0 file):
 *   - IPU MIPI input port             : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *   - MAX96724 deserializer I2C addr  : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus   : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type       : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")   : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *
 * Camera-side (from nodka_max96724_d405_mipi2.asl):
 *   - HID INTC10CD (D4XX), 2 data lanes; d4xx driver detects the exact model
 *     over I2C at runtime, so the ACPI shape matches D457/D405 alike.
 *   - Serializer: MAX9295A (INTC1138), single PHY.
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
             * here to match NVIDIA and get 4x timing margin.
             */
            #define GMSL_I2C_SPEED        0x000186A0  /* 100 kHz reverse control channel */

            // ---- DES-level configuration (NODKA board, mipi0 connector) ----
            // Copied verbatim from the proven nodka_max96724_4x_sensing_isx031_mipi0.asl
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") - proven on mipi0 */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 (mipi0 connector's control channel) */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "../_des_common_max96724.asl"

            // ---- D4XX on GMSL input Link 0 (port A) ----
            #define DESCH_LINK_NUM 0
            #define DESCH_CH CH00
            #define DESCH_SER SER0
            #define DESCH_CAM CAM0
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH00"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH00.SER0"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH00.SER0
            #define DESCH_SER_GPIOREF ^^SER0
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
