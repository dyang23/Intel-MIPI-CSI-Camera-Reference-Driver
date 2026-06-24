/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA "unitree" board — S36 GMSL camera bring-up.
 *
 * Board / hardware configuration (provided by integrator):
 *   - Platform IPU MIPI input port  : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *   - MAX96724 deserializer I2C addr : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus  : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type      : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")  : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *
 * Sensors physically connected on the GMSL inputs:
 *   - 1x S36  (this file brings it up first)
 *   - 1x 3H   (not enabled yet — see "3H placeholder" note at the bottom)
 *
 * ============================ READ ME — link identification ============================
 * The integrator is unsure which GMSL *input* connector (A/B/C/D = link 0/1/2/3)
 * the S36 cable is plugged into. This file starts with the S36 on LINK 0 (port A).
 *
 * NOTE: "cphy A" (the DES->IPU output PHY, DES_INTERNAL_PHY) is a DIFFERENT thing
 *       from the GMSL input link A/B/C/D (DESCH_LINK_NUM). Do not confuse them.
 *       The output PHY is fixed by board routing; only the input link is unknown.
 *
 * To try another GMSL input link, change ALL of the per-channel defines in the
 * "Link N" block below consistently:
 *   port A -> DESCH_LINK_NUM 0, CH00, SER0, "...CH00", "...CH00.SER0", i2c-alias 0x44
 *   port B -> DESCH_LINK_NUM 1, CH01, SER1, "...CH01", "...CH01.SER1", i2c-alias 0x45
 *   port C -> DESCH_LINK_NUM 2, CH02, SER2, "...CH02", "...CH02.SER2", i2c-alias 0x46
 *   port D -> DESCH_LINK_NUM 3, CH03, SER3, "...CH03", "...CH03.SER3", i2c-alias 0x47
 * (The DES i2c-alias-pool {0x44,0x45,0x46,0x47} in _des_common_max96724.asl already
 *  covers all four links, so only the channel block needs editing.)
 *
 * After each change: recompile with iasl, regenerate the initramfs with
 * script/gen_ssdt.sh, reboot, and check dmesg for max96724 / max9295d link lock
 * and S36 camera probe to confirm which link the S36 is really on.
 * =====================================================================================
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

    Include ("_ipu.asl")

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            // ---- DES-level configuration (NODKA unitree board) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") - VERIFIED WORKING (PHY sweep D->C->B->A) */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "_des_common_max96724.asl"

            // ---- S36 on GMSL input Link 0 (port A) ----
            // Change this whole block to Link 1/2/3 (port B/C/D) if the S36
            // does not come up here — see the "link identification" note above.
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

            /*
             * ---- 3H placeholder (NOT enabled yet) ----
             * Once the S36 link is confirmed, add the 3H on whichever remaining
             * link it is wired to, modelled after the mixed reference file
             * acpi/max96724_mixed_sensing_s36_shw3h.asl (the 3H channel there
             * uses _des_ch_common_isx031.asl). Example skeleton:
             *
             *   #define DESCH_LINK_NUM 1
             *   #define DESCH_CH CH01
             *   #define DESCH_SER SER1
             *   #define DESCH_CAM CAM1
             *   #define DESCH_SER_I2C 0x40
             *   #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH01"
             *   #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH01.SER1"
             *   #define DESCH_SER_REF \_SB.PC00.DES0.CH01.SER1
             *   #define DESCH_SER_GPIOREF ^^SER1
             *   #define DESCH_SER_EXTRA_GPIO_PIN 7
             *   #define DESCH_CAM_FSIN_GPIO 1
             *   #define CAM_ALIAS 0x55
             *   #define CAM_LANES 4
             *   #include "_des_ch_common_isx031.asl"
             */

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
