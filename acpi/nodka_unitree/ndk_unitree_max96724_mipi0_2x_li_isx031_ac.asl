/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA "unitree" board (PTL / IPU75XA) —
 * DIAGNOSTIC: 2x Leopard Imaging (LI) ISX031 GMSL cameras on Link 0 (port A)
 * and Link 2 (port C) only, behind one MAX96724 whose output is on MIPI0.
 *
 * Purpose: variable-isolation test. The 4x ISX031 config
 * (ndk_unitree_max96724_mipi0_4x_li_isx031.asl) brings up Links 0/1/3 but
 * fails Link 2's sensor probe (module ID read = 0x0fff). Yet the verified
 * ndk_unitree_max96724_mipi0_2x_d457_ac.asl brings up D457 on this SAME Link 2
 * with the SAME aliases (SER2=0x46, CAM2=0x56). This file mirrors that exact
 * 2-link (0 + 2) structure but with ISX031, to answer:
 *   - Link 2 works here (2 links)  -> the trigger is "all 4 links active"
 *     (resource/pipe/reverse-channel contention), not Link 2 itself.
 *   - Link 2 still fails here       -> it is specific to ISX031-on-Link-2,
 *     independent of link count.
 *
 * Board / hardware configuration (identical to the other mipi0 unitree files):
 *   - IPU MIPI input port             : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *   - MAX96724 deserializer I2C addr  : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus   : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type       : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")   : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *   - pipe-stream-autoselect           : disabled      -> matches d457_d457_ac
 */

DefinitionBlock ("", "SSDT", 2, "", "IMG_IPU", 0x20260513)
{
    External (_SB.PC00, DeviceObj)

    Include ("../_ipu.asl")

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            #define GMSL_I2C_SPEED        0x000186A0  /* 100 kHz reverse control channel */

            // ---- DES-level configuration (NODKA unitree board, mipi0 connector) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") - VERIFIED WORKING */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "../_des_common_max96724.asl"

            // ---- LI ISX031 #0 on GMSL input Link 0 (port A) ----
            #define DESCH_LINK_NUM 0
            #define DESCH_CH CH00
            #define DESCH_SER SER0
            #define DESCH_CAM CAM0
            #define DESCH_SER_I2C 0x62
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH00"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH00.SER0"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH00.SER0
            #define DESCH_SER_GPIOREF ^^SER0
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
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- LI ISX031 #2 on GMSL input Link 2 (port C) ----
            #define DESCH_LINK_NUM 2
            #define DESCH_CH CH02
            #define DESCH_SER SER2
            #define DESCH_CAM CAM2
            #define DESCH_SER_I2C 0x62
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH02"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH02.SER2"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH02.SER2
            #define DESCH_SER_GPIOREF ^^SER2
            /*
             * TEST: Link 2 camera alias changed 0x56 -> 0x55 to check the
             * "0x56 alias conflict" hypothesis. 0x55 is a value observed
             * working on Link 1 in the 4-link run. Still unique vs Link 0 (0x54).
             */
            #define CAM_ALIAS 0x55
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
            #undef DES_PIPE_STR_AUTOSELECT
            #undef GMSL_I2C_SPEED
        }
    }
}
