/*
 * SPDX-License-Identifier: GPL-2.0
 * Copyright (c) 2026 Intel Corporation.
 *
 * SER-level defines expected by caller:
 *   DES_REF              - Reference to parent DES (e.g. \_SB.PC00.DESx), used in _DEP
 *   DES_PATH             - Path to parent DES (e.g. "\\_SB.PC00.DESx"), used in CSI2Bus
 *   DESCH_CH_PATH        - Path to DES channel (e.g. "\\_SB.PC00.DESx.CHxx"), used in I2cSerialBusV2
 *   DESCH_SER_PATH       - Path to SER (e.g. "\\_SB.PC00.DESx.CHxx.SERx"), used in GpioIo
 *   DESCH_LINK_NUM       - DES channel number (e.g. 0 for CH00, 1 for CH01), used in CSI2Bus
 *   DESCH_SER_I2C        - SER I2C slave address (e.g. 0x40, 0x62), used in I2cSerialBusV2
 *   CAM_ALIAS            - Camera alias I2C address used in i2c-alias-pool in _DSD
 *   DESCH_SER_EXTRA_GPIO_PIN - (Optional) SER Extra GPIO pin number, used in GpioIo
 *   DESCH_SER_X/Y/Z/U_VC - (Optional) SER VC filter for Pipe X/Y/Z/U, specifically for MAX96717 driver
 */

Method (_STA, 0, NotSerialized) // _STA: Status
{
        Return (0x0F)
}

Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
{
        Return ("INTC1140") // MAX9295D
}

Name(_CRS, ResourceTemplate ()  // _CRS: Current Resource Settings
{
    /*
     * mipi-disco-img.c will use the information in CSI2Bus to create fwnode.
     * SERx Local Port -> DESx Remote Port
     * SERx PRT1 -> DESx PRT0/1/2/3
     */
    CSI2Bus(
        DeviceInitiated,        // SlaveMode
        1,                      // PhyType (1 for DPHY)
        2,                      // LocalPort (MAX9295D's PHY is PRT2)
        DES_PATH,         // ResourceSource (Path to parent DES, e.g. "\\_SB.PC00.DESx")
        DESCH_LINK_NUM,         // ResourceSourceIndex (e.g. 0/1/2/3 for parent DES PRT0/1/2/3)
        ,                       // ResourceUsage
        ,                       // DescriptorName
        )                       // VendorData

    I2cSerialBusV2 (
        DESCH_SER_I2C,          // SlaveAddress (e.g. 0x40, 0x62 based on Serializer Hardware)
        ControllerInitiated,    // SlaveMode
        0x00061A80,             // ConnectionSpeed
        AddressingMode7Bit,     // AddressingMode
        DESCH_CH_PATH,          // ResourceSource (e.g. "\\_SB.PC00.DESx.CHxx") based on which Link
        0x00,                   // ResourceSourceIndex
        ResourceConsumer,       // ResourceUsage
        ,                       // DescriptorName
        Exclusive,              // Shared
        )                       // VendorData

    GpioIo (
        Exclusive,              // Shared (Not shared)
        PullNone,               // PinConfig (No need for pulls)
        0,                      // DebounceTimeout
        0,                      // DriveStrength
        IoRestrictionOutputOnly,// ResourceSource (Only used as output)
        DESCH_SER_PATH,         // ResourceSourceIndex (Path to SER GPIO controller, e.g. "\\_SB.PC00.DESx.CHxx.SERx" based on which Link)
        0)                      // ResourceUsage (Must be 0)
    {
        DESCH_RESET_GPIO_PIN,
#ifdef DESCH_RESET_GPIO_PIN2
        DESCH_RESET_GPIO_PIN2,
#endif
#ifdef DESCH_EXTRA_GPIO_PIN
        DESCH_EXTRA_GPIO_PIN,
#endif
    }
})

Name (_DEP, Package (0x01)  // _DEP: Dependencies
{
    DES_REF
})

Name (_DSD, Package ()  // _DSD: Device-Specific Data
{
#ifdef CAM_ALIAS
        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"), // Device Properties for _DSD
        Package ()
        {
        // I2C alias pool used by i2c-atr driver.
        // Address called out in the pool is used as Camera Alias Address.
        Package () { "i2c-alias-pool",  Package() { CAM_ALIAS } },
        },
#endif
        ToUUID("dbb8e3e6-5886-4ba6-8795-1319f52a966b"), // Hierarchical Data Extension
        Package ()
        {
        Package () { "mipi-img-port-0", "PRT0" }, // Connected to CAM0 (used by CAM0 CSI2Bus ResourceSourceIndex)
        Package () { "mipi-img-port-1", "PRT1" }, // Connected to CAM1 (used by CAM1 CSI2Bus ResourceSourceIndex)
        Package () { "mipi-img-port-2", "PRT2" }, // Connected to DESx PRTx (used by SERx CSI2Bus LocalPort)
    #ifdef DESCH_SER_X_VC
        Package () { "Pipe-X", "PIPX" }, // Pipe X
        #endif
    #ifdef DESCH_SER_Y_VC
        Package () { "Pipe-Y", "PIPY" }, // Pipe Y
        #endif
    #ifdef DESCH_SER_Z_VC
        Package () { "Pipe-Z", "PIPZ" }, // Pipe Z
        #endif
    #ifdef DESCH_SER_U_VC
        Package () { "Pipe-U", "PIPU" }, // Pipe U
        #endif
        }
})

Name (PRT0, Package()
{
        ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
        Package ()
        {
        Package () { "mipi-img-clock-lanes", 0 },
    #if CAM_LANES == 4
        Package () { "mipi-img-data-lanes", Package() { 1, 2, 3, 4 } },
    #elif CAM_LANES == 2
        Package () { "mipi-img-data-lanes", Package() { 1, 2 } },
    #else
        Package () { "mipi-img-data-lanes", Package() { 1, 2, 3, 4 } },
    #endif
        },
})

Name (PRT1, Package()
{
        ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
        Package ()
        {
        Package () { "mipi-img-clock-lanes", 0 },
    #if CAM_LANES == 4
        Package () { "mipi-img-data-lanes", Package() { 1, 2, 3, 4 } },
    #elif CAM_LANES == 2
        Package () { "mipi-img-data-lanes", Package() { 1, 2 } },
    #else
        Package () { "mipi-img-data-lanes", Package() { 1, 2, 3, 4 } },
    #endif
        },
})

Name (PRT2, Package()
{
        ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"),
        Package ()
        {
        Package () { "mipi-img-clock-lanes", 0 },
        Package () { "mipi-img-data-lanes", Package() { 1, 2, 3, 4 } },
        },
})

#ifdef DESCH_SER_X_VC
Name (PIPX, Package()
{
    ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"), // Device Properties
        Package ()
        {
        Package () { "vc-id", DESCH_SER_X_VC }, // VC filter for pipe X
        },
})
#endif

#ifdef DESCH_SER_Y_VC
Name (PIPY, Package()
{
    ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"), // Device Properties
        Package ()
        {
        Package () { "vc-id", DESCH_SER_Y_VC }, // VC filter for pipe Y
        },
})
#endif

#ifdef DESCH_SER_Z_VC
Name (PIPZ, Package()
{
    ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"), // Device Properties
        Package ()
        {
        Package () { "vc-id", DESCH_SER_Z_VC }, // VC filter for pipe Z
        },
})
#endif

#ifdef DESCH_SER_U_VC
Name (PIPU, Package()
{
    ToUUID("daffd814-6eba-4d8c-8a91-bc9bbf4aa301"), // Device Properties
        Package ()
        {
        Package () { "vc-id", DESCH_SER_U_VC }, // VC filter for pipe U
        },
})
#endif