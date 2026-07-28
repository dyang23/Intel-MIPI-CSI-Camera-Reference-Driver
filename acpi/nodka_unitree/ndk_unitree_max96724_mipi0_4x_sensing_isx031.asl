/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SSDT overlay: NODKA "unitree" board (PTL / IPU75XA) —
 * 4x Sensing (森云) ISX031 GMSL cameras behind one MAX96724 deserializer,
 * whose CSI-2 output is wired to the SoC MIPI0 port.
 *
 * Relation to the neighbouring files in this directory:
 *   - ndk_unitree_max96724_mipi0_1x_sensing_isx031.asl : same Sensing module,
 *     Link 0 only. This file fans that channel block out to all four links.
 *   - ndk_unitree_max96724_mipi0_4x_li_isx031.asl      : same 4-link topology
 *     but with Leopard Imaging modules (SER remote I2C 0x62, no extra SER GPIO,
 *     no camera fsin-gpios).
 *
 * Camera topology:
 *
 *                         MAX96724 (DES0, @0x27, I2C0)
 *                       ┌──────────────────────────────┐
 * Link 0 (port A) ──────┤ CH00 → SER0 (MAX9295A @0x40) ├──┐
 *    └─ CAM0 ISX031     │  └─ CAM0 (i2c alias 0x54)    │  │
 * Link 1 (port B) ──────┤ CH01 → SER1 (MAX9295A @0x40) │  │
 *    └─ CAM1 ISX031     │  └─ CAM1 (i2c alias 0x55)    │  ├─→ PHY0 (cphy A)
 * Link 2 (port C) ──────┤ CH02 → SER2 (MAX9295A @0x40) │  │        │
 *    └─ CAM2 ISX031     │  └─ CAM2 (i2c alias 0x56)    │  │        ↓
 * Link 3 (port D) ──────┤ CH03 → SER3 (MAX9295A @0x40) │  │   MIPI port 0
 *    └─ CAM3 ISX031     │  └─ CAM3 (i2c alias 0x57)    │  │   (IPU75XA)
 *                       └──────────────────────────────┘──┘
 *
 * Vendor note — these are Sensing (森云) ISX031 modules, NOT Leopard Imaging:
 *   - Serializer remote I2C address is 0x40 (LI uses 0x62).
 *   - Each MAX9295A exposes an extra GPIO (MFP7) and each ISX031 gets an
 *     fsin-gpios resource for frame-sync. See acpi/max96724_sensing_isx031.asl
 *     for the single-link Sensing reference.
 *   - SER-side i2c aliases are auto-assigned from the DES alias pool by
 *     DESCH_LINK_NUM (Link 0..3 -> 0x44/0x45/0x46/0x47); only the camera
 *     aliases (0x54..0x57) are hand-assigned here and must not collide.
 *
 * Board / hardware configuration:
 *   - IPU MIPI input port             : MIPI port 0   -> DES_TO_MIPI_PORT = 0
 *   - MAX96724 deserializer I2C addr  : 0x27          -> DES_I2C_ADDR = 0x0027
 *   - MAX96724 deserializer I2C bus   : I2C0          -> DES_I2C_BUS = "\\_SB.PC00.I2C0"
 *   - DES -> IPU CSI-2 link type      : C-PHY         -> DES_PHY_TYPE = 0
 *   - DES internal TX PHY ("cphy A")  : TX_PHY0 = 4   -> DES_INTERNAL_PHY = 4
 *       ^ VERIFIED WORKING on this board (README PHY sweep D->C->B->A: only
 *         PHY0 produces frames on mipi0).
 *
 * NOTE: "cphy A" (the DES->IPU output PHY, DES_INTERNAL_PHY) is a DIFFERENT
 *       thing from the GMSL input link A/B/C/D (DESCH_LINK_NUM). The output PHY
 *       is fixed by board routing.
 *
 * KNOWN HARDWARE LIMITATION (4 cameras at once on this board):
 *       REPORT_4x_isx031_portC_power.md in this directory documents that with
 *       all four ISX031 modules plugged in, port C (Link 2) intermittently
 *       fails — serializer -121 (EREMOTEIO) on the reverse channel, or sensor
 *       module-ID read 0x0fff — and recovers as soon as the port B/D cameras
 *       are unplugged. Root cause is the camera power (PoC) budget, NOT this
 *       ACPI table: Links 0/1/3 coming up proves the 4-link template is
 *       correct. Expect the same behaviour here until the power rail is fixed.
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
             * 400 kHz is the known-good value for the ISX031 modules on this
             * board: ndk_unitree_max96724_mipi0_1x_sensing_isx031.asl documents
             * that when it inherited 100 kHz (0x000186A0) from a D457-derived
             * source, the MAX9295A @0x40 / ISX031 @0x1a became unreachable over
             * the reverse tunnel at stream-on (-121 at enable_streams). The
             * 100 kHz value is only needed by the D457 depth camera.
             *
             * If the reverse channel wedges under 4-camera streaming stress,
             * 0x000186A0 (100 kHz, the NVIDIA reference value) is the fallback
             * to try — note that per REPORT_4x_isx031_portC_power.md it did NOT
             * fix the port C failure, which is a power problem. Consumed by
             * _des_common_max96724.asl / _ser_common_max9295.asl /
             * _cam_common_isx031.asl via their GMSL_I2C_SPEED #ifndef guard.
             */
            #define GMSL_I2C_SPEED        0x00061A80  /* 400 kHz reverse control channel (ISX031 known-good) */

            // ---- DES-level configuration (NODKA unitree board, mipi0 connector) ----
            #define DES_PHY_TYPE          0           /* CSI2_PHY_TYPE_CPHY */
            #define DES_I2C_ADDR          0x0027      /* MAX96724 @ 0x27 */
            #define DES_INTERNAL_PHY      4           /* MAX96724_TX_PHY0 ("cphy A") - VERIFIED WORKING */
            #define DES_TO_MIPI_PORT      0           /* IPU_MIPI_PORT_0 (mipi0) */
            #define DES_I2C_BUS           "\\_SB.PC00.I2C0"   /* I2C bus 0 */
            #define DES_PATH              "\\_SB.PC00.DES0"
            #define DES_REF               \_SB.PC00.DES0
            /*
             * Disable MAX96724 pipe-stream-autoselect, matching the 4x LI
             * sibling (ndk_unitree_max96724_mipi0_4x_li_isx031.asl): with four
             * links aggregated onto one output PHY, making the DES pipe/stream
             * mapping explicit per link is the configuration that has been
             * exercised on this board. Remove this define to fall back to the
             * driver default (autoselect enabled), which is what the 1x Sensing
             * file uses.
             */
            #define DES_PIPE_STR_AUTOSELECT 0
            /*
             * Frame sync group: the four ISX031 modules are used as one
             * surround view set, so they share a common shutter.
             *
             * The MAX96724 generates a 30Hz pulse off its 25MHz crystal and
             * pushes it into GMSL GPIO tunnel channel 0x0A directly, without
             * going through one of its own pins. Each MAX9295A reproduces that
             * channel on its MFP7 (DESCH_SER_GPIO_RX_PIN /
             * DESCH_SER_GPIO_RX_ID below), which is wired to the sensor's FSIN
             * input, and each ISX031 is put in external pulse mode by
             * DESCH_CAM_EXTERNAL_SYNC.
             *
             * The serializer MFP7 is therefore no longer a host driven GPIO:
             * the previous DESCH_SER_EXTRA_GPIO_PIN / DESCH_CAM_FSIN_GPIO pair
             * only ever held the line statically low, which left the sensors
             * free running and out of phase with each other.
             *
             * Keep DES_FSYNC_TX_ID and every DESCH_SER_GPIO_RX_ID identical,
             * they are the two ends of the same tunnel channel.
             */
            #define DES_FSYNC_FPS         30          /* Frames per second */
            #define DES_FSYNC_TX_ID       0x0A        /* GMSL GPIO tunnel channel */
            #define DES_FSYNC_LINK_MASK   0x0F        /* Links 0..3 */
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
            #define DESCH_SER_GPIO_RX_PIN 7
            #define DESCH_SER_GPIO_RX_ID 0x0A
            #define DESCH_CAM_EXTERNAL_SYNC 1
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
            #undef DESCH_SER_GPIO_RX_PIN
            #undef DESCH_SER_GPIO_RX_ID
            #undef DESCH_CAM_EXTERNAL_SYNC
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- Sensing ISX031 #1 on GMSL input Link 1 (port B) ----
            #define DESCH_LINK_NUM 1
            #define DESCH_CH CH01
            #define DESCH_SER SER1
            #define DESCH_CAM CAM1
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH01"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH01.SER1"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH01.SER1
            #define DESCH_SER_GPIOREF ^^SER1
            #define DESCH_SER_GPIO_RX_PIN 7
            #define DESCH_SER_GPIO_RX_ID 0x0A
            #define DESCH_CAM_EXTERNAL_SYNC 1
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
            #undef DESCH_SER_GPIO_RX_PIN
            #undef DESCH_SER_GPIO_RX_ID
            #undef DESCH_CAM_EXTERNAL_SYNC
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- Sensing ISX031 #2 on GMSL input Link 2 (port C) ----
            #define DESCH_LINK_NUM 2
            #define DESCH_CH CH02
            #define DESCH_SER SER2
            #define DESCH_CAM CAM2
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH02"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH02.SER2"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH02.SER2
            #define DESCH_SER_GPIOREF ^^SER2
            #define DESCH_SER_GPIO_RX_PIN 7
            #define DESCH_SER_GPIO_RX_ID 0x0A
            #define DESCH_CAM_EXTERNAL_SYNC 1
            #define CAM_ALIAS 0x56
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
            #undef DESCH_SER_GPIO_RX_PIN
            #undef DESCH_SER_GPIO_RX_ID
            #undef DESCH_CAM_EXTERNAL_SYNC
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- Sensing ISX031 #3 on GMSL input Link 3 (port D) ----
            #define DESCH_LINK_NUM 3
            #define DESCH_CH CH03
            #define DESCH_SER SER3
            #define DESCH_CAM CAM3
            #define DESCH_SER_I2C 0x40
            #define DESCH_CH_PATH "\\_SB.PC00.DES0.CH03"
            #define DESCH_SER_PATH "\\_SB.PC00.DES0.CH03.SER3"
            #define DESCH_SER_REF \_SB.PC00.DES0.CH03.SER3
            #define DESCH_SER_GPIOREF ^^SER3
            #define DESCH_SER_GPIO_RX_PIN 7
            #define DESCH_SER_GPIO_RX_ID 0x0A
            #define DESCH_CAM_EXTERNAL_SYNC 1
            #define CAM_ALIAS 0x57
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
            #undef DESCH_SER_GPIO_RX_PIN
            #undef DESCH_SER_GPIO_RX_ID
            #undef DESCH_CAM_EXTERNAL_SYNC
            #undef CAM_ALIAS
            #undef CAM_LANES

            // ---- DES-level cleanup ----
            #undef DES_FSYNC_FPS
            #undef DES_FSYNC_TX_ID
            #undef DES_FSYNC_LINK_MASK
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
