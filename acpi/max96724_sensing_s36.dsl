/*
 * Intel ACPI Component Architecture
 * AML/ASL+ Disassembler version 20260408 (64-bit version)
 * Copyright (c) 2000 - 2026 Intel Corporation
 * 
 * Disassembling to symbolic ASL+ operators
 *
 * Disassembly of /media/user/Dong_U11/dev/Intel-MIPI-CSI-Camera-Reference-Driver/acpi/max96724_sensing_s36.aml
 *
 * Original Table Header:
 *     Signature        "SSDT"
 *     Length           0x00000BF5 (3061)
 *     Revision         0x02
 *     Checksum         0x83
 *     OEM ID           ""
 *     OEM Table ID     "IMG_IPU"
 *     OEM Revision     0x20260513 (539362579)
 *     Compiler ID      "INTL"
 *     Compiler Version 0x20260408 (539362312)
 */
DefinitionBlock ("", "SSDT", 2, "", "IMG_IPU", 0x20260513)
{
    External (_SB_.PC00, DeviceObj)
    External (_SB_.PC00.IPU0, DeviceObj)

    Scope (\_SB.PC00.IPU0)
    {
        Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
        {
            ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
            Package (0x04)
            {
                Package (0x02)
                {
                    "mipi-img-port-0", 
                    "PRT0"
                }, 

                Package (0x02)
                {
                    "mipi-img-port-1", 
                    "PRT1"
                }, 

                Package (0x02)
                {
                    "mipi-img-port-2", 
                    "PRT2"
                }, 

                Package (0x02)
                {
                    "mipi-img-port-3", 
                    "PRT3"
                }
            }
        })
        Name (PRT0, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
            Package (0x01)
            {
                Package (0x02)
                {
                    "mipi-img-data-lanes", 
                    Package (0x04)
                    {
                        One, 
                        0x02, 
                        0x03, 
                        0x04
                    }
                }
            }
        })
        Name (PRT1, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
            Package (0x01)
            {
                Package (0x02)
                {
                    "mipi-img-data-lanes", 
                    Package (0x04)
                    {
                        One, 
                        0x02, 
                        0x03, 
                        0x04
                    }
                }
            }
        })
        Name (PRT2, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
            Package (0x01)
            {
                Package (0x02)
                {
                    "mipi-img-data-lanes", 
                    Package (0x04)
                    {
                        One, 
                        0x02, 
                        0x03, 
                        0x04
                    }
                }
            }
        })
        Name (PRT3, Package (0x02)
        {
            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
            Package (0x01)
            {
                Package (0x02)
                {
                    "mipi-img-data-lanes", 
                    Package (0x04)
                    {
                        One, 
                        0x02, 
                        0x03, 
                        0x04
                    }
                }
            }
        })
    }

    Scope (\_SB.PC00)
    {
        Device (DES0)
        {
            Name (_UID, Zero)  // _UID: Unique ID
            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
            {
                Return ("INTC1139")
            }

            Method (_STA, 0, NotSerialized)  // _STA: Status
            {
                Return (0x0F)
            }

            Name (_DEP, Package (0x01)  // _DEP: Dependencies
            {
                \_SB.PC00.IPU0, 
            })
            Name (_CRS, Buffer (0x3E)  // _CRS: Current Resource Settings
            {
                /* 0000 */  0x8E, 0x18, 0x00, 0x01, 0x00, 0x04, 0x03, 0x18,  // ........
                /* 0008 */  0x00, 0x01, 0x00, 0x00, 0x5C, 0x5F, 0x53, 0x42,  // ....\_SB
                /* 0010 */  0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x49, 0x50,  // .PC00.IP
                /* 0018 */  0x55, 0x30, 0x00, 0x8E, 0x1E, 0x00, 0x02, 0x00,  // U0......
                /* 0020 */  0x01, 0x02, 0x00, 0x00, 0x01, 0x06, 0x00, 0x80,  // ........
                /* 0028 */  0x1A, 0x06, 0x00, 0x27, 0x00, 0x5C, 0x5F, 0x53,  // ...'.\_S
                /* 0030 */  0x42, 0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x49,  // B.PC00.I
                /* 0038 */  0x32, 0x43, 0x30, 0x00, 0x79, 0x00               // 2C0.y.
            })
            Name (_DSD, Package (0x04)  // _DSD: Device-Specific Data
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x02)
                {
                    Package (0x02)
                    {
                        "i2c-alias-pool", 
                        Package (0x04)
                        {
                            0x44, 
                            0x45, 
                            0x46, 
                            0x47
                        }
                    }, 

                    Package (0x02)
                    {
                        "pipe-stream-autoselect", 
                        Zero
                    }
                }, 

                ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                Package (0x05)
                {
                    Package (0x02)
                    {
                        "mipi-img-port-0", 
                        "PRT0"
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-port-1", 
                        "PRT1"
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-port-2", 
                        "PRT2"
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-port-3", 
                        "PRT3"
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-port-6", 
                        "PRT6"
                    }
                }
            })
            Name (PRT0, Package (0x02)
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x02)
                {
                    Package (0x02)
                    {
                        "mipi-img-clock-lanes", 
                        Zero
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-data-lanes", 
                        Package (0x04)
                        {
                            One, 
                            0x02, 
                            0x03, 
                            0x04
                        }
                    }
                }
            })
            Name (PRT1, Package (0x02)
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x02)
                {
                    Package (0x02)
                    {
                        "mipi-img-clock-lanes", 
                        Zero
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-data-lanes", 
                        Package (0x04)
                        {
                            One, 
                            0x02, 
                            0x03, 
                            0x04
                        }
                    }
                }
            })
            Name (PRT2, Package (0x02)
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x02)
                {
                    Package (0x02)
                    {
                        "mipi-img-clock-lanes", 
                        Zero
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-data-lanes", 
                        Package (0x04)
                        {
                            One, 
                            0x02, 
                            0x03, 
                            0x04
                        }
                    }
                }
            })
            Name (PRT3, Package (0x02)
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x02)
                {
                    Package (0x02)
                    {
                        "mipi-img-clock-lanes", 
                        Zero
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-data-lanes", 
                        Package (0x04)
                        {
                            One, 
                            0x02, 
                            0x03, 
                            0x04
                        }
                    }
                }
            })
            Name (PRT6, Package (0x02)
            {
                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                Package (0x03)
                {
                    Package (0x02)
                    {
                        "mipi-img-clock-lanes", 
                        Zero
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-data-lanes", 
                        Package (0x02)
                        {
                            One, 
                            0x02
                        }
                    }, 

                    Package (0x02)
                    {
                        "mipi-img-link-frequencies", 
                        Package (0x01)
                        {
                            0x3B9ACA00
                        }
                    }
                }
            })
            Device (CH00)
            {
                Name (_ADR, Zero)  // _ADR: Address
                Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                {
                    ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                    Package (0x01)
                    {
                        Package (0x02)
                        {
                            "reg", 
                            Zero
                        }
                    }
                })
                Device (SER0)
                {
                    Method (_STA, 0, NotSerialized)  // _STA: Status
                    {
                        Return (0x0F)
                    }

                    Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
                    {
                        Return ("INTC1140")
                    }

                    Name (_CRS, Buffer (0x79)  // _CRS: Current Resource Settings
                    {
                        /* 0000 */  0x8E, 0x18, 0x00, 0x01, 0x00, 0x04, 0x03, 0x09,  // ........
                        /* 0008 */  0x00, 0x01, 0x00, 0x00, 0x5C, 0x5F, 0x53, 0x42,  // ....\_SB
                        /* 0010 */  0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x44, 0x45,  // .PC00.DE
                        /* 0018 */  0x53, 0x30, 0x00, 0x8E, 0x23, 0x00, 0x02, 0x00,  // S0..#...
                        /* 0020 */  0x01, 0x02, 0x00, 0x00, 0x01, 0x06, 0x00, 0x80,  // ........
                        /* 0028 */  0x1A, 0x06, 0x00, 0x40, 0x00, 0x5C, 0x5F, 0x53,  // ...@.\_S
                        /* 0030 */  0x42, 0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x44,  // B.PC00.D
                        /* 0038 */  0x45, 0x53, 0x30, 0x2E, 0x43, 0x48, 0x30, 0x30,  // ES0.CH00
                        /* 0040 */  0x00, 0x8C, 0x33, 0x00, 0x01, 0x01, 0x01, 0x00,  // ..3.....
                        /* 0048 */  0x02, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00, 0x17,  // ........
                        /* 0050 */  0x00, 0x00, 0x1D, 0x00, 0x36, 0x00, 0x00, 0x00,  // ....6...
                        /* 0058 */  0x03, 0x00, 0x08, 0x00, 0x07, 0x00, 0x5C, 0x5F,  // ......\_
                        /* 0060 */  0x53, 0x42, 0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E,  // SB.PC00.
                        /* 0068 */  0x44, 0x45, 0x53, 0x30, 0x2E, 0x43, 0x48, 0x30,  // DES0.CH0
                        /* 0070 */  0x30, 0x2E, 0x53, 0x45, 0x52, 0x30, 0x00, 0x79,  // 0.SER0.y
                        /* 0078 */  0x00                                             // .
                    })
                    Name (_DEP, Package (0x01)  // _DEP: Dependencies
                    {
                        \_SB.PC00.DES0, 
                    })
                    Name (_DSD, Package (0x04)  // _DSD: Device-Specific Data
                    {
                        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                        Package (0x01)
                        {
                            Package (0x02)
                            {
                                "i2c-alias-pool", 
                                Package (0x02)
                                {
                                    0x54, 
                                    0x55
                                }
                            }
                        }, 

                        ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                        Package (0x03)
                        {
                            Package (0x02)
                            {
                                "mipi-img-port-0", 
                                "PRT0"
                            }, 

                            Package (0x02)
                            {
                                "mipi-img-port-1", 
                                "PRT1"
                            }, 

                            Package (0x02)
                            {
                                "mipi-img-port-2", 
                                "PRT2"
                            }
                        }
                    })
                    Name (PRT0, Package (0x02)
                    {
                        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                        Package (0x02)
                        {
                            Package (0x02)
                            {
                                "mipi-img-clock-lanes", 
                                Zero
                            }, 

                            Package (0x02)
                            {
                                "mipi-img-data-lanes", 
                                Package (0x04)
                                {
                                    One, 
                                    0x02, 
                                    0x03, 
                                    0x04
                                }
                            }
                        }
                    })
                    Name (PRT1, Package (0x02)
                    {
                        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                        Package (0x02)
                        {
                            Package (0x02)
                            {
                                "mipi-img-clock-lanes", 
                                Zero
                            }, 

                            Package (0x02)
                            {
                                "mipi-img-data-lanes", 
                                Package (0x04)
                                {
                                    One, 
                                    0x02, 
                                    0x03, 
                                    0x04
                                }
                            }
                        }
                    })
                    Name (PRT2, Package (0x02)
                    {
                        ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                        Package (0x02)
                        {
                            Package (0x02)
                            {
                                "mipi-img-clock-lanes", 
                                Zero
                            }, 

                            Package (0x02)
                            {
                                "mipi-img-data-lanes", 
                                Package (0x04)
                                {
                                    One, 
                                    0x02, 
                                    0x03, 
                                    0x04
                                }
                            }
                        }
                    })
                    Device (CH00)
                    {
                        Name (_ADR, Zero)  // _ADR: Address
                        Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                        {
                            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                            Package (0x01)
                            {
                                Package (0x02)
                                {
                                    "reg", 
                                    Zero
                                }
                            }
                        })
                        Device (CAM0)
                        {
                            Method (_STA, 0, NotSerialized)  // _STA: Status
                            {
                                Return (0x0F)
                            }

                            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
                            {
                                Return ("INTC113C")
                            }

                            Name (_CRS, Buffer (0x52)  // _CRS: Current Resource Settings
                            {
                                /* 0000 */  0x8E, 0x22, 0x00, 0x01, 0x00, 0x04, 0x03, 0x01,  // ."......
                                /* 0008 */  0x00, 0x01, 0x00, 0x00, 0x5C, 0x5F, 0x53, 0x42,  // ....\_SB
                                /* 0010 */  0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x44, 0x45,  // .PC00.DE
                                /* 0018 */  0x53, 0x30, 0x2E, 0x43, 0x48, 0x30, 0x30, 0x2E,  // S0.CH00.
                                /* 0020 */  0x53, 0x45, 0x52, 0x30, 0x00, 0x8E, 0x28, 0x00,  // SER0..(.
                                /* 0028 */  0x02, 0x00, 0x01, 0x02, 0x00, 0x00, 0x01, 0x06,  // ........
                                /* 0030 */  0x00, 0x80, 0x1A, 0x06, 0x00, 0x1A, 0x00, 0x5C,  // .......\
                                /* 0038 */  0x5F, 0x53, 0x42, 0x2E, 0x50, 0x43, 0x30, 0x30,  // _SB.PC00
                                /* 0040 */  0x2E, 0x44, 0x45, 0x53, 0x30, 0x2E, 0x43, 0x48,  // .DES0.CH
                                /* 0048 */  0x30, 0x30, 0x2E, 0x53, 0x45, 0x52, 0x30, 0x00,  // 00.SER0.
                                /* 0050 */  0x79, 0x00                                       // y.
                            })
                            Name (_DEP, Package (0x01)  // _DEP: Dependencies
                            {
                                \_SB.PC00.DES0.CH00.SER0, 
                            })
                            Name (_DSD, Package (0x04)  // _DSD: Device-Specific Data
                            {
                                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                                Package (0x03)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-clock-frequency", 
                                        0x05B8D800
                                    }, 

                                    Package (0x02)
                                    {
                                        "reset-gpios", 
                                        Package (0x04)
                                        {
                                            ^^^SER0, , 
                                            Zero, 
                                            Zero, 
                                            One
                                        }
                                    }, 

                                    Package (0x02)
                                    {
                                        "fsin-gpios", 
                                        Package (0x04)
                                        {
                                            ^^^SER0, , 
                                            Zero, 
                                            0x02, 
                                            One
                                        }
                                    }
                                }, 

                                ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                                Package (0x01)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-port-0", 
                                        "PRT0"
                                    }
                                }
                            })
                            Name (PRT0, Package (0x02)
                            {
                                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                                Package (0x03)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-clock-lanes", 
                                        Zero
                                    }, 

                                    Package (0x02)
                                    {
                                        "mipi-img-data-lanes", 
                                        Package (0x04)
                                        {
                                            One, 
                                            0x02, 
                                            0x03, 
                                            0x04
                                        }
                                    }, 

                                    Package (0x02)
                                    {
                                        "mipi-img-link-frequencies", 
                                        Package (0x01)
                                        {
                                            0x23C34600
                                        }
                                    }
                                }
                            })
                        }
                    }

                    Device (CH01)
                    {
                        Name (_ADR, One)  // _ADR: Address
                        Name (_DSD, Package (0x02)  // _DSD: Device-Specific Data
                        {
                            ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                            Package (0x01)
                            {
                                Package (0x02)
                                {
                                    "reg", 
                                    One
                                }
                            }
                        })
                        Device (CAM1)
                        {
                            Method (_STA, 0, NotSerialized)  // _STA: Status
                            {
                                Return (0x0F)
                            }

                            Method (_HID, 0, NotSerialized)  // _HID: Hardware ID
                            {
                                Return ("INTC113C")
                            }

                            Name (_CRS, Buffer (0x52)  // _CRS: Current Resource Settings
                            {
                                /* 0000 */  0x8E, 0x22, 0x00, 0x01, 0x01, 0x04, 0x03, 0x01,  // ."......
                                /* 0008 */  0x00, 0x01, 0x00, 0x00, 0x5C, 0x5F, 0x53, 0x42,  // ....\_SB
                                /* 0010 */  0x2E, 0x50, 0x43, 0x30, 0x30, 0x2E, 0x44, 0x45,  // .PC00.DE
                                /* 0018 */  0x53, 0x30, 0x2E, 0x43, 0x48, 0x30, 0x30, 0x2E,  // S0.CH00.
                                /* 0020 */  0x53, 0x45, 0x52, 0x30, 0x00, 0x8E, 0x28, 0x00,  // SER0..(.
                                /* 0028 */  0x02, 0x00, 0x01, 0x02, 0x00, 0x00, 0x01, 0x06,  // ........
                                /* 0030 */  0x00, 0x80, 0x1A, 0x06, 0x00, 0x1B, 0x00, 0x5C,  // .......\
                                /* 0038 */  0x5F, 0x53, 0x42, 0x2E, 0x50, 0x43, 0x30, 0x30,  // _SB.PC00
                                /* 0040 */  0x2E, 0x44, 0x45, 0x53, 0x30, 0x2E, 0x43, 0x48,  // .DES0.CH
                                /* 0048 */  0x30, 0x30, 0x2E, 0x53, 0x45, 0x52, 0x30, 0x00,  // 00.SER0.
                                /* 0050 */  0x79, 0x00                                       // y.
                            })
                            Name (_DEP, Package (0x01)  // _DEP: Dependencies
                            {
                                \_SB.PC00.DES0.CH00.SER0, 
                            })
                            Name (_DSD, Package (0x04)  // _DSD: Device-Specific Data
                            {
                                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                                Package (0x02)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-clock-frequency", 
                                        0x05B8D800
                                    }, 

                                    Package (0x02)
                                    {
                                        "reset-gpios", 
                                        Package (0x04)
                                        {
                                            ^^^SER0, , 
                                            Zero, 
                                            One, 
                                            One
                                        }
                                    }
                                }, 

                                ToUUID ("dbb8e3e6-5886-4ba6-8795-1319f52a966b") /* Hierarchical Data Extension */, 
                                Package (0x01)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-port-0", 
                                        "PRT0"
                                    }
                                }
                            })
                            Name (PRT0, Package (0x02)
                            {
                                ToUUID ("daffd814-6eba-4d8c-8a91-bc9bbf4aa301") /* Device Properties for _DSD */, 
                                Package (0x03)
                                {
                                    Package (0x02)
                                    {
                                        "mipi-img-clock-lanes", 
                                        Zero
                                    }, 

                                    Package (0x02)
                                    {
                                        "mipi-img-data-lanes", 
                                        Package (0x04)
                                        {
                                            One, 
                                            0x02, 
                                            0x03, 
                                            0x04
                                        }
                                    }, 

                                    Package (0x02)
                                    {
                                        "mipi-img-link-frequencies", 
                                        Package (0x01)
                                        {
                                            0x23C34600
                                        }
                                    }
                                }
                            })
                        }
                    }
                }
            }
        }
    }
}

