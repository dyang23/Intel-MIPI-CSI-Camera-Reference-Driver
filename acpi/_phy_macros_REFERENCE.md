# ACPI CSI-2 PHY / Port Field Reference

> **Note**: iasl's preprocessor does NOT support macro-in-macro recursion.
> A pattern like
> ```c
> #define MAX96724_TX_PHY0    4
> #define DES_INTERNAL_PHY    MAX96724_TX_PHY0   // expands once -> "MAX96724_TX_PHY0"
>                                                // never gets re-expanded to "4"
> ```
> fails with `Invalid character (#)` errors.  So the SSDT ASL files use
> literal numbers and rely on this reference + inline comments for
> readability.

ACPI 6.5 §6.4.3.8.2.4 (CSI-2 Connection Resource Descriptor) encodes:
- `PhyType`            : 0 = CPHY, 1 = DPHY
- `LocalPort`          : per-vendor encoded port id (max96724 uses 4..7 for PHY0..3)
- `ResourceSourceIndex`: the SoC-side MIPI port number

When editing an SSDT (e.g. `max96724_sensing_s36.asl`), use these tables
to choose the right literal numeric value.

---

## CSI-2 PHY Type — `DES_PHY_TYPE` value in CSI2Bus()

| Symbolic name           | Literal | When to use                           |
|-------------------------|---------|---------------------------------------|
| `CSI2_PHY_TYPE_CPHY`    | `0`     | C-PHY (3-wire trio)                   |
| `CSI2_PHY_TYPE_DPHY`    | `1`     | D-PHY (differential pairs)            |

---

## MAX96724 internal CSI-2 TX PHY — `DES_INTERNAL_PHY` value

MAX96724 has 4 CSI-2 output PHYs (TX_PHY0..3); the ACPI LocalPort
encoding for them is 4..7 respectively.

| Symbolic name        | Literal |
|----------------------|---------|
| `MAX96724_TX_PHY0`   | `4`     |
| `MAX96724_TX_PHY1`   | `5`     |
| `MAX96724_TX_PHY2`   | `6`     |
| `MAX96724_TX_PHY3`   | `7`     |

---

## Intel IPU SoC-side MIPI input port — `DES_TO_MIPI_PORT` value

On Intel IPU each MIPI port has a fixed 1:1 mapping to a CSI-2 PHY,
so only the port number is exposed.

| Symbolic name        | Literal |
|----------------------|---------|
| `IPU_MIPI_PORT_0`    | `0`     |
| `IPU_MIPI_PORT_1`    | `1`     |
| `IPU_MIPI_PORT_2`    | `2`     |
| `IPU_MIPI_PORT_3`    | `3`     |

---

## Recommended caller pattern

```c
#define DES_PHY_TYPE       0    /* CSI2_PHY_TYPE_CPHY */
#define DES_INTERNAL_PHY   4    /* MAX96724_TX_PHY0 */
#define DES_TO_MIPI_PORT   0    /* IPU_MIPI_PORT_0 */
```

The trailing `/* ... */` comment makes the literal self-documenting
without depending on macro recursion.
