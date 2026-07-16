/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA board (PTL / IPU7) —
 * 1x Sensing (森云) ISX031 GMSL camera behind one MAX96724 deserializer,
 * whose CSI-2 output is wired to the SoC MIPI0 port.
 *
 * This is the single-link (Link A only) variant of
 * acpi/nodka/nodka_max96724_4x_sensing_isx031_mipi0.asl — the DES-level
 * configuration is identical; only GMSL input Link 0 (port A) is populated.
 *
 * Camera topology:
 *
 *                      MAX96724 (DES0, @0x27, I2C0)
 *                      ┌────────────────────────────┐
 * Link 0 (port A) ─────┤ CH00 → SER0 (MAX9295A @0x40)├──→ PHY0 (cphy A)
 *    └─ CAM0 ISX031     │  └─ CAM0 (i2c alias 0x54) │         │
 *                      └────────────────────────────┘         ↓
 *                                                        MIPI port 0
 *                                                          (IPU7)
 *
 * Vendor note — this is the Sensing (森云) ISX031 module, NOT Leopard Imaging:
 *   - Serializer remote I2C address is 0x40 (LI uses 0x62).
 *   - Each MAX9295A exposes an extra GPIO (MFP7) and each ISX031 gets an
 *     fsin-gpios resource for frame-sync. See acpi/max96724_sensing_isx031.asl
 *     for the single-link Sensing reference.
 *
 * Board / hardware configuration:
 *   - IPU MIPI input port             : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *       ^ The Sensing ISX031 module here is connected to the board's mipi0
 *         GMSL connector, whose reverse control channel is on I2C bus 0.
 *   - MAX96724 deserializer I2C addr  : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus   : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type       : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")   : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *
 * NOTE: "cphy A" (the DES->IPU output PHY, DES_INTERNAL_PHY) is a DIFFERENT
 *       thing from the GMSL input link A/B/C/D (DESCH_LINK_NUM). The output PHY
 *       is fixed by board routing. PHY0 = "cphy A" is the value verified on the
 *       NODKA/PTL platform. If I2C/GMSL-lock is OK but there is no video, sweep
 *       the internal PHY (DES_INTERNAL_PHY 4->5->6->7) the same way the
 *       nodka_unitree README documents.
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
             * chain on this board. Template default is 400 kHz (0x00061A80).
             *
             * The 100 kHz value (0x000186A0) was required by the D457 depth
             * camera, whose reverse tunnel wedged at 400 kHz (-121 / EREMOTEIO).
             * The 4x Sensing ISX031 build, by contrast, worked at 400 kHz.
             * When this file inherited 100 kHz from the 4x source, the ISX031
             * serializer/sensor became unreachable over the tunnel at stream-on
             * (-121 at enable_streams; MAX96717 @0x40 / ISX031 @0x1a NAK on the
             * reverse channel). Restore 400 kHz to match the known-good ISX031
             * configuration. Consumed by _des_common_max96724.asl /
             * _ser_common_max9295.asl / _cam_common_isx031.asl via their
             * GMSL_I2C_SPEED #ifndef guard.
             */
            #define GMSL_I2C_SPEED        0x00061A80  /* 400 kHz reverse control channel (ISX031 known-good) */

            // ---- DES-level configuration (NODKA board, mipi0 connector) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #include "../_des_common_max96724.asl"

            // ---- Sensing ISX031 #0 on GMSL input Link 0 (port A) ----
            #define DESCH_LINK_NUM 0
            #define DESCH_CH CH00
            #define DESCH_SER SER0
            #define DESCH_CAM CAM0
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH00"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH00.SER0"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH00.SER0
            #define DESCH_SER_GPIOREF ^^SER0
            #define DESCH_SER_EXTRA_GPIO_PIN 7
            #define DESCH_CAM_FSIN_GPIO 1
            #define CAM_ALIAS 0x54
            #define CAM_LANES 4
            #include "../_des_ch_common_isx031.asl"
            #undef DESCH_LINK_NUM
            #undef DESCH_CH
            #undef DESCH_SER
            #undef DESCH_CAM
            #undef DESCH_SER_I2C
            #undef DESCH_CH_PATH
            #undef DESCH_SER_PATH
            #undef DESCH_SER_REF
            #undef DESCH_SER_GPIOREF
            #undef DESCH_SER_EXTRA_GPIO_PIN
            #undef DESCH_CAM_FSIN_GPIO
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- DES-level cleanup ----
            #undef DES_PHY_TYPE
            #undef DES_I2C_ADDR
            #undef DES_INTERNAL_PHY
            #undef DES_TO_MIPI_PORT
            #undef DES_I2C_BUS
            #undef DES_PATH
            #undef DES_REF
            #undef GMSL_I2C_SPEED
        }
    }
}
