/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: S36 GMSL camera configuration on PTL platform.
 *   One MAX96724 deserializer (DES0) on I2C0, with one S36 module
 *   physically connected to GMSL link 0.
 */

DefinitionBlock ("", "SSDT", 2, "", "IMG_IPU", 0x20260513)
{
    External (_SB.PC00, DeviceObj)

    Include ("_ipu.asl")

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            /*
             * iasl preprocessor does not support macro-in-macro recursion,
             * so DES_* values must be literal numbers.  Trailing comments
             * carry the symbolic name from acpi/_phy_macros_REFERENCE.md:
             *   PHY type:  0 = CPHY, 1 = DPHY
             *   DES PHY:   4..7 for max96724 internal TX PHY 0..3
             *   IPU port:  0..3 for SoC MIPI port 0..3
             */
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "_des_common_max96724.asl"

            // ---- Link 0 (the only physically populated link) ----
            #define DESCH_LINK_NUM 0
            #define DESCH_CH CH00
            #define DESCH_SER SER0
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH00"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH00.SER0"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH00.SER0
            #define DESCH_CAM CAM0
            #define DESCH_SER_GPIOREF ^^^SER0
            #define CAM_ALIAS 0x54, 0x55
            #define DESCH_RESET_GPIO_PIN    3
            #define DESCH_RESET_GPIO_PIN2   8
            #define DESCH_EXTRA_GPIO_PIN    7
            #define DESCH_CAM_FSIN_GPIO 1
            #include "_des_ch_common_s36.asl"
            #undef DESCH_RESET_GPIO_PIN
            #undef DESCH_RESET_GPIO_PIN2

            // DES-level cleanup
            #undef DES_PHY_TYPE
            #undef DES_I2C_ADDR
            #undef DES_INTERNAL_PHY
            #undef DES_TO_MIPI_PORT
            #undef DES_I2C_BUS
            #undef DES_PATH
            #undef DES_REF
            #undef DES_PIPE_STR_AUTOSELECT
        }
    }
}
