/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA "unitree" board (PTL / IPU75XA) — two Intel RealSense
 * D457 GMSL cameras on one MAX96724 deserializer:
 *   - D457 #1 on GMSL input Link 0 (port A) — MAX9295A serializer   [already working]
 *   - D457 #2 on GMSL input Link 2 (port C) — MAX9295A serializer   [newly added]
 *
 * Goal: run BOTH cameras' RGB + Depth (+ IR + IMU) streams simultaneously.
 *
 * Board / hardware configuration (same DES config as the other unitree files):
 *   - Platform IPU MIPI input port  : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *   - MAX96724 deserializer I2C addr : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus  : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type      : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")  : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *
 * Both GMSL input links (Link 0 + Link 2) are muxed by the MAX96724 onto the
 * SAME output PHY0 ("cphy A") -> IPU MIPI port 0. The deserializer separates the
 * two links' streams by virtual channel.
 *
 * NOTE: "cphy A" (the DES->IPU output PHY, DES_INTERNAL_PHY) is a DIFFERENT thing
 *       from the GMSL input link A/B/C/D (DESCH_LINK_NUM). The output PHY is
 *       fixed by board routing (only PHY0 = "cphy A" produces frames on this
 *       board, verified via PHY sweep D->C->B->A on the S36 bring-up).
 *
 * D457 specifics (see acpi/max96724_rs_d457.asl reference):
 *   - HID INTC10CD (D4XX), DPHY link camera-side, 2 data lanes
 *   - Serializer: MAX9295A (INTC1138), single PHY — do NOT use MAX9295D template
 *   - Exposes four virtual channels X/Y/Z/U for depth/rgb/ir/imu streams
 *
 * VIRTUAL CHANNEL LAYOUT (important for running two D457s at once):
 *   The whole serdes stack is capped at 4 virtual channels (VC 0..3):
 *     drivers/media/i2c/maxim-serdes/max_serdes.h: MAX_SERDES_VC_ID_NUM = 4
 *   max_des.c / max_ser.c reject any VC >= 4 (-E2BIG), and d4xx.c vc_to_sensor()
 *   only maps VC 0/1/2/3 -> depth/rgb/ir/imu. So VC 4..7 does NOT exist here.
 *
 *   Both D457s emit their streams on LOCAL VC 0/1/2/3. We do NOT hand-assign
 *   output VCs in ACPI: the max_ser driver auto-remaps colliding VCs on the
 *   shared output PHY (max_ser_assign_vc_remaps(): first pipe keeps its VC, a
 *   colliding pipe gets the lowest free VC via ffz). Both channel blocks below
 *   therefore use the SAME local VC 0/1/2/3 and let the driver resolve it.
 *
 *   HARD LIMIT: one output PHY has only 4 VC slots total. Two D457s streaming
 *   depth+rgb = 4 streams = exactly fills VC 0..3 (this is the supported goal).
 *   If BOTH cameras additionally open IR or IMU, the total exceeds 4 VCs and
 *   the extra streams get "No free VC ID ... skipping remap" and no frames.
 *   Keep the two cameras to depth+rgb each for simultaneous capture.
 *
 * i2c aliases (must not collide on the DES ATR bus):
 *   - SER alias pool (DES-level, _des_common_max96724.asl): 0x44/0x45/0x46/0x47
 *     for Link 0/1/2/3 -> D457 #1 SER0 = 0x44, D457 #2 SER2 = 0x46 (automatic
 *     from DESCH_LINK_NUM).
 *   - Camera alias (per SER): D457 #1 CAM0 = 0x54, D457 #2 CAM2 = 0x56.
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
             * 100 kHz (clock-frequency = <100000>); our default template value
             * is 400 kHz (0x00061A80), which is too fast for the reverse tunnel
             * under streaming stress and wedges the channel (-121 / EREMOTEIO).
             * Force 100 kHz (0x000186A0) here to match NVIDIA and get 4x timing
             * margin. Consumed by _des_common_max96724.asl, _ser_common_max9295.asl
             * and _cam_common_d457.asl via their GMSL_I2C_SPEED #ifndef guard.
             */
            #define GMSL_I2C_SPEED        0x000186A0  /* 100 kHz reverse control channel */

            // ---- DES-level configuration (NODKA unitree board) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") - VERIFIED WORKING on this board */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            #define DES_PIPE_STR_AUTOSELECT 0
            #include "../_des_common_max96724.asl"

            // ---- D457 #1 on GMSL input Link 0 (port A) ----
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
            #undef DESCH_SER_X_VC
            #undef DESCH_SER_Y_VC
            #undef DESCH_SER_Z_VC
            #undef DESCH_SER_U_VC

            // ---- D457 #2 on GMSL input Link 2 (port C) ----
            // Same local VC 0/1/2/3 as D457 #1. The max_ser driver auto-remaps
            // the colliding VCs onto free slots on the shared output PHY0
            // (VC hard limit is 4 - see VC note in header). Do NOT use VC > 3.
            #define DESCH_LINK_NUM 2
            #define DESCH_CH CH02
            #define DESCH_SER SER2
            #define DESCH_CAM CAM2
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH02"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH02.SER2"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH02.SER2
            #define DESCH_SER_GPIOREF ^^SER2
            #define CAM_ALIAS 0x56
            #define CAM_LANES 2
            #define DESCH_SER_X_VC Package () { 0 }
            #define DESCH_SER_Y_VC Package () { 1 }
            #define DESCH_SER_Z_VC Package () { 2 }
            #define DESCH_SER_U_VC Package () { 3 }
            #include "../_des_ch_common_d457.asl"
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
            #undef DESCH_SER_X_VC
            #undef DESCH_SER_Y_VC
            #undef DESCH_SER_Z_VC
            #undef DESCH_SER_U_VC

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
