// SPDX-License-Identifier: GPL-2.0
// Copyright (c) 2025 Intel Corporation.
//
// Common template for ISX031 deserializer ATR channel device.
// Uses IASL C-preprocessor macros to eliminate per-channel file duplication.
//
// DES-level defines (set once before all channels, caller undefs after):
//   DESCH_SER_I2C     - Serializer I2C address (e.g., 0x40)
//   DESCH_DES_PATH    - DES ACPI path string (e.g., "\\_SB.PC00.DES0")
//   DESCH_DES_REF     - DES ACPI namespace reference (e.g., \_SB.PC00.DES0)
//
// Channel-level defines (set per channel, auto-cleaned by this template):
//   DESCH_LINK_NUM    - Channel number (0, 1, 2, 3) - used for _ADR, reg, and SER remote port
//   DESCH_CH          - Channel device name (e.g., CH00)
//   DESCH_SER         - Serializer device name (e.g., SER0)
//   DESCH_CAM         - Camera device name (e.g., CAM0)
//   DESCH_CH_PATH     - Channel ACPI path string (e.g., "\\_SB.PC00.DES0.CH00")
//   DESCH_SER_PATH    - Serializer ACPI path string (e.g., "\\_SB.PC00.DES0.CH00.SER0")
//   DESCH_SER_REF     - Serializer ACPI namespace reference (e.g., \_SB.PC00.DES0.CH00.SER0)
//   DESCH_SER_GPIOREF - GPIO reference for CAM reset (e.g., ^^SER0)
//
// Optional defines:
//   DESCH_EXTRA_GPIO_PIN  - Additional GPIO pin number (e.g., 7 for fsin)
//   DESCH_CAM_FSIN_GPIO   - If defined, adds fsin-gpios property to CAM _DSD

Device (DESCH_CH)
{
    Name (_ADR, DESCH_LINK_NUM) // _ADR: Address for the channel (e.g. 0 for Link 0, 1 for Link 1)
    Name (_DSD, Package ()
    {
        ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
        Package ()
        {
            Package () { "reg", DESCH_LINK_NUM },       // used by i2c-atr driver. Represents the channel / link number
        }
    })

    Device (DESCH_SER)
    {
        #include "_ser_common_max9295d.asl"

        Device (CH00)
        {
            Name (_ADR, 0)
            Name (_DSD, Package ()
            {
                ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
                Package ()
                {
                    Package () { "reg", 0 },
                }
            })
            Device (CAM0)
            {
                #define SERCH_CAM_I2C 0x1a
                #define CAM_CSI_REMOTE_PORT 0
                #define DESCH_SER_GPIOREF ^^^SER1
                #define DESCH_SER_GPIORESETID 0
                #define DESCH_SER_GPIOFSINID 2
                #define DESCH_CAM_FSIN_GPIO 1
                #include "_cam_common_s36.asl"
                #undef DESCH_CAM_FSIN_GPIO
                #undef DESCH_SER_GPIORESETID
                #undef DESCH_SER_GPIOFSINID
                #undef DESCH_SER_GPIOREF
                #undef CAM_CSI_REMOTE_PORT
                #undef SERCH_CAM_I2C
            }
        }

        Device (CH01)
        {
            Name (_ADR, 1)
            Name (_DSD, Package ()
            {
                ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
                Package ()
                {
                    Package () { "reg", 1 },
                }
            })
            Device (CAM1)
            {
                #define SERCH_CAM_I2C 0x1b
                #define CAM_CSI_REMOTE_PORT 1
                #define DESCH_SER_GPIOREF ^^^SER1
                #define DESCH_SER_GPIORESETID 1
                #include "_cam_common_s36.asl"
                #undef DESCH_CAM_FSIN_GPIO
                #undef DESCH_SER_GPIORESETID
                #undef DESCH_SER_GPIOREF
                #undef CAM_CSI_REMOTE_PORT
                #undef SERCH_CAM_I2C
            }
        }
    }
}

// Clean up channel-level defines for safe reuse
#undef DESCH_LINK_NUM
#undef DESCH_CH
#undef DESCH_SER
#undef DESCH_CAM
#undef DESCH_CH_PATH
#undef DESCH_SER_I2C
#undef DESCH_SER_PATH
#undef DESCH_SER_REF
#ifdef SER_ALIAS
#undef SER_ALIAS
#endif
#undef DESCH_SER_GPIOREF
#ifdef DESCH_EXTRA_GPIO_PIN
#undef DESCH_EXTRA_GPIO_PIN
#endif
#undef DESCH_RESET_GPIO_PIN
#ifdef DESCH_CAM_FSIN_GPIO
#undef DESCH_CAM_FSIN_GPIO
#endif
#undef CAM_ALIAS