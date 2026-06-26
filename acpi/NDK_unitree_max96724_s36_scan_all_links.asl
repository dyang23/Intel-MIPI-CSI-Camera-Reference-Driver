/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA "unitree" board (PTL / IPU75XA) — S36 GMSL LINK SCAN.
 *
 * PURPOSE (diagnostic, one-shot):
 *   Configure ALL FOUR MAX96724 GMSL input links (A/B/C/D = link 0/1/2/3) as
 *   S36 simultaneously, boot ONCE, then read dmesg to discover which physical
 *   link the single S36 module is actually plugged into. The link whose full
 *   chain (max9295d serializer @0x40 + S36 sensor) probes successfully is the
 *   S36 port. The link with the 3H (or empty links) will fail to probe S36 —
 *   that is expected and is exactly the signal used to identify the S36 port.
 *
 *   After identifying the link, switch back to the clean single-link file
 *   NDK_unitree_max96724_s36_3H.asl and set DESCH_LINK_NUM accordingly.
 *
 * Board / hardware (same DES config as the single-link file):
 *   - IPU MIPI input port : 0    -> DES_TO_MIPI_PORT = 0   (mipi0)
 *   - MAX96724 I2C addr   : 0x27 -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 I2C bus    : 0    -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU PHY type : CPHY -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY : PHY0 -> DES_INTERNAL_PHY = 4  ("cphy A")
 *
 * Each link uses a UNIQUE camera alias pair to avoid any I2C alias collision
 * while all four are enabled at once:
 *   link 0 (A): 0x54, 0x55
 *   link 1 (B): 0x56, 0x57
 *   link 2 (C): 0x58, 0x59
 *   link 3 (D): 0x5a, 0x5b
 *
 * iasl preprocessor uses literal numbers (no macro recursion); see
 * acpi/_phy_macros_REFERENCE.md.
 */

DefinitionBlock ("", "SSDT", 2, "", "IMG_IPU", 0x20260513)
{
    External (_SB.PC00, DeviceObj)

    Include ("_ipu.asl")

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            // ---- DES-level configuration (NODKA unitree board) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "_des_common_max96724.asl"

            // ======================= Link 0 (port A) as S36 =======================
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

            // ======================= Link 1 (port B) as S36 =======================
            #define DESCH_LINK_NUM 1
            #define DESCH_CH CH01
            #define DESCH_SER SER1
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH01"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH01.SER1"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH01.SER1
            #define DESCH_CAM CAM1
            #define DESCH_SER_GPIOREF ^^^SER1
            #define CAM_ALIAS 0x56, 0x57
            #define DESCH_RESET_GPIO_PIN    3
            #define DESCH_RESET_GPIO_PIN2   8
            #define DESCH_EXTRA_GPIO_PIN    7
            #define DESCH_CAM_FSIN_GPIO 1
            #include "_des_ch_common_s36.asl"
            #undef DESCH_RESET_GPIO_PIN
            #undef DESCH_RESET_GPIO_PIN2

            // ======================= Link 2 (port C) as S36 =======================
            #define DESCH_LINK_NUM 2
            #define DESCH_CH CH02
            #define DESCH_SER SER2
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH02"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH02.SER2"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH02.SER2
            #define DESCH_CAM CAM2
            #define DESCH_SER_GPIOREF ^^^SER2
            #define CAM_ALIAS 0x58, 0x59
            #define DESCH_RESET_GPIO_PIN    3
            #define DESCH_RESET_GPIO_PIN2   8
            #define DESCH_EXTRA_GPIO_PIN    7
            #define DESCH_CAM_FSIN_GPIO 1
            #include "_des_ch_common_s36.asl"
            #undef DESCH_RESET_GPIO_PIN
            #undef DESCH_RESET_GPIO_PIN2

            // ======================= Link 3 (port D) as S36 =======================
            #define DESCH_LINK_NUM 3
            #define DESCH_CH CH03
            #define DESCH_SER SER3
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH03"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH03.SER3"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH03.SER3
            #define DESCH_CAM CAM3
            #define DESCH_SER_GPIOREF ^^^SER3
            #define CAM_ALIAS 0x5a, 0x5b
            #define DESCH_RESET_GPIO_PIN    3
            #define DESCH_RESET_GPIO_PIN2   8
            #define DESCH_EXTRA_GPIO_PIN    7
            #define DESCH_CAM_FSIN_GPIO 1
            #include "_des_ch_common_s36.asl"
            #undef DESCH_RESET_GPIO_PIN
            #undef DESCH_RESET_GPIO_PIN2

            // ---- DES-level cleanup ----
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
