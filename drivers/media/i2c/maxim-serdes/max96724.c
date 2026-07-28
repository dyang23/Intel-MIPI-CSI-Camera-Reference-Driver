// SPDX-License-Identifier: GPL-2.0
/*
 * Maxim MAX96724 Quad GMSL2 Deserializer Driver
 *
 * Copyright (C) 2025 Analog Devices Inc.
 */

#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/i2c.h>
#include <linux/module.h>
#include <linux/of_graph.h>
#include <linux/regmap.h>

#include "max_des.h"

#define MAX96724_REG0				0x0

#define MAX96724_REG6				0x6
#define MAX96724_REG6_LINK_EN			GENMASK(3, 0)

#define MAX96724_DEBUG_EXTRA			0x9
#define MAX96724_DEBUG_EXTRA_PCLK_SRC		GENMASK(1, 0)
#define MAX96724_DEBUG_EXTRA_PCLK_SRC_25MHZ	0b00
#define MAX96724_DEBUG_EXTRA_PCLK_SRC_75MHZ	0b01
#define MAX96724_DEBUG_EXTRA_PCLK_SRC_USE_PIPE	0b10

#define MAX96724_REG26(x)			(0x10 + (x) / 2)
#define MAX96724_REG26_RX_RATE_PHY(x)		(GENMASK(1, 0) << (4 * ((x) % 2)))
#define MAX96724_REG26_RX_RATE_3GBPS		0b01
#define MAX96724_REG26_RX_RATE_6GBPS		0b10

#define MAX96724_PWR1				0x13
#define MAX96724_PWR1_RESET_ALL			BIT(6)

#define MAX96724_CTRL1				0x18
#define MAX96724_CTRL1_RESET_ONESHOT		GENMASK(3, 0)

/* Per-link GMSL lock status: link 0 in CTRL3 (0x1a), links 1..3 at 0x0a.. */
#define MAX96724_LINK_LOCK(link)		((link) == 0 ? 0x1a : 0x0a + ((link) - 1))
#define MAX96724_LINK_LOCK_LOCKED		BIT(3)
#define MAX96724_LINK_LOCK_TIMEOUT_MS		200

#define MAX96724_VIDEO_PIPE_SEL(p)		(0xf0 + (p) / 2)
#define MAX96724_VIDEO_PIPE_SEL_STREAM(p)	(GENMASK(1, 0) << (4 * ((p) % 2)))
#define MAX96724_VIDEO_PIPE_SEL_LINK(p)		(GENMASK(3, 2) << (4 * ((p) % 2)))

#define MAX96724_VIDEO_PIPE_EN			0xf4
#define MAX96724_VIDEO_PIPE_EN_MASK(p)		BIT(p)
#define MAX96724_VIDEO_PIPE_EN_STREAM_SEL_ALL	BIT(4)

#define MAX96724_VPRBS(p)			(0x1dc + (p) * 0x20)
#define MAX96724_VPRBS_VIDEO_LOCK		BIT(0)
#define MAX96724_VPRBS_PATGEN_CLK_SRC		BIT(7)
#define MAX96724_VPRBS_PATGEN_CLK_SRC_150MHZ	0b0
#define MAX96724_VPRBS_PATGEN_CLK_SRC_375MHZ	0b1

#define MAX96724_BACKTOP12			0x40b
#define MAX96724_BACKTOP12_CSI_OUT_EN		BIT(1)

#define MAX96724_BACKTOP21(p)			(0x414 + (p) / 4 * 0x20)
#define MAX96724_BACKTOP21_BPP8DBL(p)		BIT(4 + (p) % 4)

#define MAX96724_BACKTOP22(x)			(0x415 + (x) * 0x3)
#define MAX96724_BACKTOP22_PHY_CSI_TX_DPLL	GENMASK(4, 0)
#define MAX96724_BACKTOP22_PHY_CSI_TX_DPLL_EN	BIT(5)

#define MAX96724_BACKTOP24(p)			(0x417 + (p) / 4 * 0x20)
#define MAX96724_BACKTOP24_BPP8DBL_MODE(p)	BIT(4 + (p) % 4)

#define MAX96724_BACKTOP30(p)			(0x41d + (p) / 4 * 0x20)
#define MAX96724_BACKTOP30_BPP10DBL3		BIT(4)
#define MAX96724_BACKTOP30_BPP10DBL3_MODE	BIT(5)

#define MAX96724_BACKTOP31(p)			(0x41e + (p) / 4 * 0x20)
#define MAX96724_BACKTOP31_BPP10DBL2		BIT(6)
#define MAX96724_BACKTOP31_BPP10DBL2_MODE	BIT(7)

#define MAX96724_BACKTOP32(p)			(0x41f + (p) / 4 * 0x20)
#define MAX96724_BACKTOP32_BPP12(p)		BIT(p)
#define MAX96724_BACKTOP32_BPP10DBL0		BIT(4)
#define MAX96724_BACKTOP32_BPP10DBL0_MODE	BIT(5)
#define MAX96724_BACKTOP32_BPP10DBL1		BIT(6)
#define MAX96724_BACKTOP32_BPP10DBL1_MODE	BIT(7)

/*
 * Multi-function pin registers.
 *
 * GPIO_A holds the pin direction and is shared by every link, GPIO_B and
 * GPIO_C hold the tunnel channel ids. Only link 0 keeps all three adjacent;
 * links 1 to 3 have their own GPIO_B/GPIO_C blocks elsewhere, with the
 * transmit and receive enables folded into the spare bits.
 *
 * None of the blocks is evenly strided: the per-pin registers are packed into
 * 16 byte pages, which leaves a hole every time a page runs out. Computing the
 * address as a plain multiple of the pin number lands on a neighbouring pin's
 * registers, so the addresses are tabulated instead.
 */
#define MAX96724_NUM_LINKS			4
#define MAX96724_GPIO_NUM			11

static const u16 max96724_gpio_b_regs[MAX96724_NUM_LINKS][MAX96724_GPIO_NUM] = {
	{ 0x301, 0x304, 0x307, 0x30a, 0x30d, 0x311, 0x314, 0x317, 0x31a, 0x31d, 0x321 },
	{ 0x337, 0x33a, 0x33d, 0x341, 0x344, 0x347, 0x34a, 0x34d, 0x351, 0x354, 0x357 },
	{ 0x36d, 0x371, 0x374, 0x377, 0x37a, 0x37d, 0x381, 0x384, 0x387, 0x38a, 0x38d },
	{ 0x3a4, 0x3a7, 0x3aa, 0x3ad, 0x3b1, 0x3b4, 0x3b7, 0x3ba, 0x3bd, 0x3c1, 0x3c4 },
};

#define MAX96724_GPIO_A(pin)			(max96724_gpio_b_regs[0][pin] - 1)
#define MAX96724_GPIO_A_GPIO_OUT_DIS		BIT(0)
#define MAX96724_GPIO_A_GPIO_TX_EN		BIT(1)
#define MAX96724_GPIO_A_GPIO_RX_EN		BIT(2)
#define MAX96724_GPIO_A_GPIO_IN			BIT(3)
#define MAX96724_GPIO_A_GPIO_OUT		BIT(4)
#define MAX96724_GPIO_A_TX_COMP_EN		BIT(5)
#define MAX96724_GPIO_A_RES_CFG			BIT(7)

#define MAX96724_GPIO_B(link, pin)		(max96724_gpio_b_regs[link][pin])
#define MAX96724_GPIO_B_GPIO_TX_ID		GENMASK(4, 0)
/* Link 0 drives the pin, so it carries the output type instead of an enable. */
#define MAX96724_GPIO_B_OUT_TYPE		BIT(5)
#define MAX96724_GPIO_B_GPIO_TX_EN		BIT(5)
#define MAX96724_GPIO_B_TX_COMP_EN		BIT(6)

#define MAX96724_GPIO_C(link, pin)		(max96724_gpio_b_regs[link][pin] + 1)
#define MAX96724_GPIO_C_GPIO_RX_ID		GENMASK(4, 0)
#define MAX96724_GPIO_C_GPIO_RX_EN		BIT(5)
#define MAX96724_GPIO_C_GPIO_RECEIVED		BIT(6)

#define MAX96724_FSYNC_0			0x4a0
#define MAX96724_FSYNC_0_FSYNC_METH		GENMASK(1, 0)
#define MAX96724_FSYNC_0_FSYNC_METH_MANUAL	0b00
#define MAX96724_FSYNC_0_FSYNC_METH_SEMI_AUTO	0b01
#define MAX96724_FSYNC_0_FSYNC_METH_AUTO	0b10
#define MAX96724_FSYNC_0_FSYNC_MODE		GENMASK(3, 2)
/* Generation is on and no pin is involved: the tunnel is the only consumer. */
#define MAX96724_FSYNC_0_FSYNC_MODE_TUNNEL	0b00
#define MAX96724_FSYNC_0_FSYNC_MODE_GPIO_OUT	0b01
#define MAX96724_FSYNC_0_FSYNC_MODE_OFF		0b11
#define MAX96724_FSYNC_0_EN_VS_GEN		BIT(4)
/* Only MFP0 and MFP7 can carry the pulse out of the chip. */
#define MAX96724_FSYNC_0_FSYNC_OUT_PIN		BIT(5)
#define MAX96724_FSYNC_GEN_PIN_MFP0		0
#define MAX96724_FSYNC_GEN_PIN_MFP7		7

#define MAX96724_FSYNC_1			0x4a1
#define MAX96724_FSYNC_1_FSYNC_PER_DIV		GENMASK(3, 0)

/* 24-bit frame sync period, LSB first. */
#define MAX96724_FSYNC_5			0x4a5
#define MAX96724_FSYNC_6			0x4a6
#define MAX96724_FSYNC_7			0x4a7
#define MAX96724_FSYNC_PERIOD_MAX		GENMASK(23, 0)

#define MAX96724_FSYNC_15			0x4af
#define MAX96724_FSYNC_15_FS_LINKS		GENMASK(3, 0)
#define MAX96724_FSYNC_15_AUTO_FS_LINKS		BIT(4)
#define MAX96724_FSYNC_15_FS_USE_XTAL		BIT(6)
#define MAX96724_FSYNC_15_FS_GPIO_TYPE		BIT(7)

#define MAX96724_FSYNC_16			0x4b0
#define MAX96724_FSYNC_16_FSYNC_ERR_CNT		GENMASK(7, 0)

#define MAX96724_FSYNC_17			0x4b1
#define MAX96724_FSYNC_17_FSYNC_ERR_THR		GENMASK(2, 0)
#define MAX96724_FSYNC_17_FSYNC_TX_ID		GENMASK(7, 3)

#define MAX96724_FSYNC_22			0x4b6
#define MAX96724_FSYNC_22_FSYNC_LOCKED		BIT(6)
#define MAX96724_FSYNC_22_LOSS_OF_LOCK		BIT(7)

/* Frame sync generator time base when FS_USE_XTAL is set. */
#define MAX96724_FSYNC_XTAL_RATE		25000000UL

#define MAX96724_MIPI_PHY0			0x8a0
#define MAX96724_MIPI_PHY0_PHY_CONFIG		GENMASK(4, 0)
#define MAX96724_MIPI_PHY0_PHY_4X2		BIT(0)
#define MAX96724_MIPI_PHY0_PHY_2X4		BIT(2)
#define MAX96724_MIPI_PHY0_PHY_1X4A_2X2		BIT(3)
#define MAX96724_MIPI_PHY0_PHY_1X4B_2X2		BIT(4)
#define MAX96724_MIPI_PHY0_FORCE_CSI_OUT_EN	BIT(7)

#define MAX96724_MIPI_PHY2			0x8a2
#define MAX96724_MIPI_PHY2_PHY_STDB_N_4(x)	(GENMASK(5, 4) << ((x) / 2 * 2))
#define MAX96724_MIPI_PHY2_PHY_STDB_N_2(x)	(BIT(4 + (x)))

#define MAX96724_MIPI_PHY3(x)			(0x8a3 + (x) / 2)
#define MAX96724_MIPI_PHY3_PHY_LANE_MAP_4	GENMASK(7, 0)
#define MAX96724_MIPI_PHY3_PHY_LANE_MAP_2(x)	(GENMASK(3, 0) << (4 * ((x) % 2)))

#define MAX96724_MIPI_PHY5(x)			(0x8a5 + (x) / 2)
#define MAX96724_MIPI_PHY5_PHY_POL_MAP_4_0_1	GENMASK(1, 0)
#define MAX96724_MIPI_PHY5_PHY_POL_MAP_4_2_3	GENMASK(4, 3)
#define MAX96724_MIPI_PHY5_PHY_POL_MAP_4_CLK	BIT(5)
#define MAX96724_MIPI_PHY5_PHY_POL_MAP_2(x)	(GENMASK(1, 0) << (3 * ((x) % 2)))
#define MAX96724_MIPI_PHY5_PHY_POL_MAP_2_CLK(x)	BIT(2 + 3 * ((x) % 2))

#define MAX96724_MIPI_PHY13			0x8ad
#define MAX96724_MIPI_PHY13_T_T3_PREBEGIN	GENMASK(5, 0)
#define MAX96724_MIPI_PHY13_T_T3_PREBEGIN_64X7	FIELD_PREP(MAX96724_MIPI_PHY13_T_T3_PREBEGIN, 63)

#define MAX96724_MIPI_PHY14			0x8ae
#define MAX96724_MIPI_PHY14_T_T3_PREP		GENMASK(1, 0)
#define MAX96724_MIPI_PHY14_T_T3_PREP_55NS	FIELD_PREP(MAX96724_MIPI_PHY14_T_T3_PREP, 0b01)
#define MAX96724_MIPI_PHY14_T_T3_POST		GENMASK(6, 2)
#define MAX96724_MIPI_PHY14_T_T3_POST_32X7	FIELD_PREP(MAX96724_MIPI_PHY14_T_T3_POST, 31)

#define MAX96724_MIPI_CTRL_SEL			0x8ca
#define MAX96724_MIPI_CTRL_SEL_MASK(p)		(GENMASK(1, 0) << ((p) * 2))

#define MAX96724_MIPI_PHY25(x)			(0x8d0 + (x) / 2)
#define MAX96724_MIPI_PHY25_CSI2_TX_PKT_CNT(x)	(GENMASK(3, 0) << (4 * ((x) % 2)))

#define MAX96724_MIPI_PHY27(x)			(0x8d2 + (x) / 2)
#define MAX96724_MIPI_PHY27_PHY_PKT_CNT(x)	(GENMASK(3, 0) << (4 * ((x) % 2)))

#define MAX96724_MIPI_TX3(x)			(0x903 + (x) * 0x40)
#define MAX96724_MIPI_TX3_DESKEW_INIT_8X32K	FIELD_PREP(GENMASK(2, 0), 0b001)
#define MAX96724_MIPI_TX3_DESKEW_INIT_AUTO	BIT(7)

#define MAX96724_MIPI_TX4(x)			(0x904 + (x) * 0x40)
#define MAX96724_MIPI_TX4_DESKEW_PER_2K		FIELD_PREP(GENMASK(2, 0), 0b001)
#define MAX96724_MIPI_TX4_DESKEW_PER_AUTO	BIT(7)

#define MAX96724_MIPI_TX10(x)			(0x90a + (x) * 0x40)
#define MAX96724_MIPI_TX10_CSI2_CPHY_EN		BIT(5)
#define MAX96724_MIPI_TX10_CSI2_LANE_CNT	GENMASK(7, 6)

#define MAX96724_MIPI_TX11(p)			(0x90b + (p) * 0x40)
#define MAX96724_MIPI_TX12(p)			(0x90c + (p) * 0x40)

#define MAX96724_MIPI_TX13(p, x)		(0x90d + (p) * 0x40 + (x) * 0x2)
#define MAX96724_MIPI_TX13_MAP_SRC_DT		GENMASK(5, 0)
#define MAX96724_MIPI_TX13_MAP_SRC_VC		GENMASK(7, 6)

#define MAX96724_MIPI_TX14(p, x)		(0x90e + (p) * 0x40 + (x) * 0x2)
#define MAX96724_MIPI_TX14_MAP_DST_DT		GENMASK(5, 0)
#define MAX96724_MIPI_TX14_MAP_DST_VC		GENMASK(7, 6)

#define MAX96724_MIPI_TX45(p, x)		(0x92d + (p) * 0x40 + (x) / 4)
#define MAX96724_MIPI_TX45_MAP_DPHY_DEST(x)	(GENMASK(1, 0) << (2 * ((x) % 4)))

#define MAX96724_MIPI_TX51(x)			(0x933 + (x) * 0x40)
#define MAX96724_MIPI_TX51_ALT_MEM_MAP_12	BIT(0)
#define MAX96724_MIPI_TX51_ALT_MEM_MAP_8	BIT(1)
#define MAX96724_MIPI_TX51_ALT_MEM_MAP_10	BIT(2)
#define MAX96724_MIPI_TX51_ALT2_MEM_MAP_8	BIT(4)

#define MAX96724_MIPI_TX54(x)			(0x936 + (x) * 0x40)
#define MAX96724_MIPI_TX54_TUN_EN		BIT(0)

#define MAX96724_MIPI_TX57(x)			(0x939 + (x) * 0x40)
#define MAX96724_MIPI_TX57_TUN_DEST		GENMASK(5, 4)
#define MAX96724_MIPI_TX57_DIS_AUTO_TUN_DET	BIT(6)
#define MAX96724_DET(p)				BIT(p)

#define MAX96724_PATGEN_0			0x1050
#define MAX96724_PATGEN_0_VTG_MODE		GENMASK(1, 0)
#define MAX96724_PATGEN_0_VTG_MODE_FREE_RUNNING	0b11
#define MAX96724_PATGEN_0_DE_INV		BIT(2)
#define MAX96724_PATGEN_0_HS_INV		BIT(3)
#define MAX96724_PATGEN_0_VS_INV		BIT(4)
#define MAX96724_PATGEN_0_GEN_DE		BIT(5)
#define MAX96724_PATGEN_0_GEN_HS		BIT(6)
#define MAX96724_PATGEN_0_GEN_VS		BIT(7)

#define MAX96724_PATGEN_1			0x1051
#define MAX96724_PATGEN_1_PATGEN_MODE		GENMASK(5, 4)
#define MAX96724_PATGEN_1_PATGEN_MODE_DISABLED	0b00
#define MAX96724_PATGEN_1_PATGEN_MODE_CHECKER	0b01
#define MAX96724_PATGEN_1_PATGEN_MODE_GRADIENT	0b10

#define MAX96724_VS_DLY_2			0x1052
#define MAX96724_VS_HIGH_2			0x1055
#define MAX96724_VS_LOW_2			0x1058
#define MAX96724_V2H_2				0x105b
#define MAX96724_HS_HIGH_1			0x105e
#define MAX96724_HS_LOW_1			0x1060
#define MAX96724_HS_CNT_1			0x1062
#define MAX96724_V2D_2				0x1064
#define MAX96724_DE_HIGH_1			0x1067
#define MAX96724_DE_LOW_1			0x1069
#define MAX96724_DE_CNT_1			0x106b
#define MAX96724_GRAD_INCR			0x106d
#define MAX96724_CHKR_COLOR_A_L			0x106e
#define MAX96724_CHKR_COLOR_B_L			0x1071
#define MAX96724_CHKR_RPT_A			0x1074
#define MAX96724_CHKR_RPT_B			0x1075
#define MAX96724_CHKR_ALT			0x1076

#define MAX96724_DE_DET				0x11f0
#define MAX96724_HS_DET				0x11f1
#define MAX96724_VS_DET				0x11f2
#define MAX96724_HS_POL				0x11f3
#define MAX96724_VS_POL				0x11f4
#define MAX96724_DET(p)				BIT(p)

#define MAX96724_DPLL_0(x)			(0x1c00 + (x) * 0x100)
#define MAX96724_DPLL_0_CONFIG_SOFT_RST_N	BIT(0)

#define MAX96724_PHY1_ALT_CLOCK			5

static const struct regmap_config max96724_i2c_regmap = {
	.reg_bits = 16,
	.val_bits = 8,
	.max_register = 0x1f00,
};

struct max96724_priv {
	struct max_des des;
	const struct max96724_chip_info *info;

	struct device *dev;
	struct i2c_client *client;
	struct regmap *regmap;

	struct gpio_desc *gpiod_enable;
};

struct max96724_chip_info {
	unsigned int versions;
	unsigned int modes;
	bool supports_pipe_stream_autoselect;
	unsigned int num_pipes;

	int (*set_pipe_phy)(struct max_des *des, struct max_des_pipe *pipe,
			    struct max_des_phy *phy);
	int (*set_pipe_tunnel_phy)(struct max_des *des, struct max_des_pipe *pipe,
				   struct max_des_phy *phy);
	int (*set_pipe_tunnel_enable)(struct max_des *des, struct max_des_pipe *pipe,
				      bool enable);
};

#define des_to_priv(_des) \
	container_of(_des, struct max96724_priv, des)

static int max96724_wait_for_device(struct max96724_priv *priv)
{
	unsigned int i;
	int ret;

	for (i = 0; i < 10; i++) {
		unsigned int val;

		ret = regmap_read(priv->regmap, MAX96724_REG0, &val);
		if (!ret && val)
			return 0;

		msleep(100);

		dev_err(priv->dev, "Retry %u waiting for deserializer: %d\n", i, ret);
	}

	return ret;
}

static int max96724_reset(struct max96724_priv *priv)
{
	int ret;

	ret = max96724_wait_for_device(priv);
	if (ret)
		return ret;

	ret = regmap_update_bits(priv->regmap, MAX96724_PWR1,
				 MAX96724_PWR1_RESET_ALL,
				 FIELD_PREP(MAX96724_PWR1_RESET_ALL, 1));
	if (ret)
		return ret;

	/*
	 * Allow the deserializer to fully settle after RESET_ALL. The old
	 * max9x driver waited 100 ms here; the 10 ms used previously was too
	 * short and contributed to intermittent bring-up.
	 */
	fsleep(100000);

	return max96724_wait_for_device(priv);
}

static int __maybe_unused max96724_reg_read(struct max_des *des, unsigned int reg,
					    unsigned int *val)
{
	struct max96724_priv *priv = des_to_priv(des);

	return regmap_read(priv->regmap, reg, val);
}

static int __maybe_unused max96724_reg_write(struct max_des *des, unsigned int reg,
					     unsigned int val)
{
	struct max96724_priv *priv = des_to_priv(des);

	return regmap_write(priv->regmap, reg, val);
}

static unsigned int max96724_phy_id(struct max_des *des, struct max_des_phy *phy)
{
	unsigned int num_hw_data_lanes = max_des_phy_hw_data_lanes(des, phy);

	/* PHY 1 is the master PHY when combining PHY 0 and PHY 1. */
	if (phy->index == 0 && num_hw_data_lanes == 4)
		return 1;

	if (phy->index == 3 && num_hw_data_lanes == 4)
		return 2;

	return phy->index;
}

static int max96724_log_pipe_status(struct max_des *des,
				    struct max_des_pipe *pipe)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;
	unsigned int val, mask;
	int ret;

	ret = regmap_read(priv->regmap, MAX96724_VPRBS(index), &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tvideo_lock: %u\n",
		 !!(val & MAX96724_VPRBS_VIDEO_LOCK));

	mask = MAX96724_DET(index);

	ret = regmap_read(priv->regmap, MAX96724_DE_DET, &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tde_det: %u\n", !!(val & mask));

	ret = regmap_read(priv->regmap, MAX96724_HS_DET, &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\ths_det: %u\n", !!(val & mask));

	ret = regmap_read(priv->regmap, MAX96724_VS_DET, &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tvs_det: %u\n", !!(val & mask));

	ret = regmap_read(priv->regmap, MAX96724_HS_POL, &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\ths_pol: %u\n", !!(val & mask));

	ret = regmap_read(priv->regmap, MAX96724_VS_POL, &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tvs_pol: %u\n", !!(val & mask));

	return 0;
}

static int max96724_log_phy_status(struct max_des *des,
				   struct max_des_phy *phy)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = max96724_phy_id(des, phy);
	unsigned int val;
	int ret;

	ret = regmap_read(priv->regmap, MAX96724_MIPI_PHY25(index), &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tcsi2_pkt_cnt: %lu\n",
		 field_get(MAX96724_MIPI_PHY25_CSI2_TX_PKT_CNT(index), val));

	ret = regmap_read(priv->regmap, MAX96724_MIPI_PHY27(index), &val);
	if (ret)
		return ret;

	dev_info(priv->dev, "\tphy_pkt_cnt: %lu\n",
		 field_get(MAX96724_MIPI_PHY27_PHY_PKT_CNT(index), val));

	return 0;
}

static int max96724_set_enable(struct max_des *des, bool enable)
{
	struct max96724_priv *priv = des_to_priv(des);

	return regmap_assign_bits(priv->regmap, MAX96724_BACKTOP12,
				  MAX96724_BACKTOP12_CSI_OUT_EN, enable);
}

static const unsigned int max96724_phys_configs_reg_val[] = {
	MAX96724_MIPI_PHY0_PHY_1X4A_2X2,
	MAX96724_MIPI_PHY0_PHY_2X4,

	MAX96724_MIPI_PHY0_PHY_4X2,
	MAX96724_MIPI_PHY0_PHY_1X4A_2X2,
	MAX96724_MIPI_PHY0_PHY_1X4B_2X2,
	MAX96724_MIPI_PHY0_PHY_2X4,
};

static const struct max_serdes_phys_config max96724_phys_configs[] = {
	/*
	 * PHY 1 can be in 4-lane mode (combining lanes of PHY 0 and PHY 1)
	 * but only use the data lanes of PHY0, while continuing to use the
	 * clock lane of PHY 1.
	 * Specifying clock-lanes as 5 turns on alternate clocking mode.
	 */
	{ { 2, 0, 2, 2 }, { MAX96724_PHY1_ALT_CLOCK, 0, 0, 0 } },
	{ { 2, 0, 4, 0 }, { MAX96724_PHY1_ALT_CLOCK, 0, 0, 0 } },

	/*
	 * When combining PHY 0 and PHY 1 to make them function in 4-lane mode,
	 * PHY 1 is the master PHY, but we use PHY 0 here to maintain
	 * compatibility.
	 */
	{ { 2, 2, 2, 2 } },
	{ { 4, 0, 2, 2 } },
	{ { 2, 2, 4, 0 } },
	{ { 4, 0, 4, 0 } },
};

static int max96724_init_tpg(struct max_des *des)
{
	const struct reg_sequence regs[] = {
		{ MAX96724_GRAD_INCR, MAX_SERDES_GRAD_INCR },
		REG_SEQUENCE_3_LE(MAX96724_CHKR_COLOR_A_L,
				  MAX_SERDES_CHECKER_COLOR_A),
		REG_SEQUENCE_3_LE(MAX96724_CHKR_COLOR_B_L,
				  MAX_SERDES_CHECKER_COLOR_B),
		{ MAX96724_CHKR_RPT_A, MAX_SERDES_CHECKER_SIZE },
		{ MAX96724_CHKR_RPT_B, MAX_SERDES_CHECKER_SIZE },
		{ MAX96724_CHKR_ALT, MAX_SERDES_CHECKER_SIZE },
	};
	struct max96724_priv *priv = des_to_priv(des);

	return regmap_multi_reg_write(priv->regmap, regs, ARRAY_SIZE(regs));
}

/*
 * Errata #5 (MAX96724/F/R rev 1): the GMSL2 link requires these RLMS
 * (reverse-link) block register writes for robust 6 Gbps operation.
 * One register per PHY, stride 0x100 (PHY0..PHY3). Without them the
 * 6 Gbps link and its embedded reverse control channel are marginal,
 * causing intermittent link lock / -EREMOTEIO / -EIO across power cycles.
 * Ref: max96724-f-r-rev1-b-0a-errata.pdf.
 */
static const struct reg_sequence max96724_errata_rev1[] = {
	{ 0x1449, 0x75 },
	{ 0x1549, 0x75 },
	{ 0x1649, 0x75 },
	{ 0x1749, 0x75 },
};

static int max96724_init(struct max_des *des)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int i;
	int ret;

	/* Apply the rev1 6 Gbps robustness errata before bringing links up. */
	ret = regmap_multi_reg_write(priv->regmap, max96724_errata_rev1,
				     ARRAY_SIZE(max96724_errata_rev1));
	if (ret)
		return ret;

	if (priv->info->set_pipe_tunnel_enable) {
		for (i = 0; i < des->ops->num_pipes; i++) {
			ret = regmap_set_bits(priv->regmap, MAX96724_MIPI_TX57(i),
					      MAX96724_MIPI_TX57_DIS_AUTO_TUN_DET);
			if (ret)
				return ret;
		}
	}

	if (des->pipe_stream_autoselect) {
		/* Enable stream autoselect. */
		ret = regmap_set_bits(priv->regmap, MAX96724_VIDEO_PIPE_EN,
				      MAX96724_VIDEO_PIPE_EN_STREAM_SEL_ALL);
		if (ret)
			return ret;
	} else {
		/*
		 * Disable stream autoselect so each pipe only receives
		 * the stream matching its configured stream_id.
		 */
		ret = regmap_clear_bits(priv->regmap, MAX96724_VIDEO_PIPE_EN,
					MAX96724_VIDEO_PIPE_EN_STREAM_SEL_ALL);
		if (ret)
			return ret;
	}

	/* Set PHY mode. */
	ret = regmap_update_bits(priv->regmap, MAX96724_MIPI_PHY0,
				 MAX96724_MIPI_PHY0_PHY_CONFIG,
				 max96724_phys_configs_reg_val[des->phys_config]);
	if (ret)
		return ret;

	return max96724_init_tpg(des);
}

static int max96724_init_phy(struct max_des *des, struct max_des_phy *phy)
{
	struct max96724_priv *priv = des_to_priv(des);
	bool is_cphy = phy->bus_type == V4L2_MBUS_CSI2_CPHY;
	unsigned int num_data_lanes = phy->mipi.num_data_lanes;
	unsigned int dpll_freq = phy->link_frequency * 2;
	unsigned int num_hw_data_lanes;
	unsigned int index;
	unsigned int used_data_lanes = 0;
	unsigned int val, mask;
	unsigned int i;
	int ret;

	index = max96724_phy_id(des, phy);
	num_hw_data_lanes = max_des_phy_hw_data_lanes(des, phy);

	ret = regmap_update_bits(priv->regmap, MAX96724_MIPI_TX10(index),
				 MAX96724_MIPI_TX10_CSI2_LANE_CNT,
				 FIELD_PREP(MAX96724_MIPI_TX10_CSI2_LANE_CNT,
					    num_data_lanes - 1));
	if (ret)
		return ret;

	ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX10(index),
				 MAX96724_MIPI_TX10_CSI2_CPHY_EN, is_cphy);
	if (ret)
		return ret;

	/* Configure lane mapping. */
	val = 0;
	for (i = 0; i < num_hw_data_lanes ; i++) {
		unsigned int map;

		if (i < num_data_lanes)
			map = phy->mipi.data_lanes[i] - 1;
		else
			map = ffz(used_data_lanes);

		val |= map << (i * 2);
		used_data_lanes |= BIT(map);
	}

	if (num_hw_data_lanes == 4)
		mask = MAX96724_MIPI_PHY3_PHY_LANE_MAP_4;
	else
		mask = MAX96724_MIPI_PHY3_PHY_LANE_MAP_2(index);

	ret = regmap_update_bits(priv->regmap, MAX96724_MIPI_PHY3(index),
				 mask, field_prep(mask, val));
	if (ret)
		return ret;

	/* Configure lane polarity. */
	for (i = 0, val = 0; i < num_data_lanes; i++)
		if (phy->mipi.lane_polarities[i + 1])
			val |= BIT(i);

	if (num_hw_data_lanes == 4) {
		ret = regmap_update_bits(priv->regmap, MAX96724_MIPI_PHY5(index),
					 MAX96724_MIPI_PHY5_PHY_POL_MAP_4_0_1 |
					 MAX96724_MIPI_PHY5_PHY_POL_MAP_4_2_3,
					 FIELD_PREP(MAX96724_MIPI_PHY5_PHY_POL_MAP_4_0_1,
						    val) |
					 FIELD_PREP(MAX96724_MIPI_PHY5_PHY_POL_MAP_4_2_3,
						    val >> 2));
		if (ret)
			return ret;

		ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_PHY5(index),
					 MAX96724_MIPI_PHY5_PHY_POL_MAP_4_CLK,
					 phy->mipi.lane_polarities[0]);
		if (ret)
			return ret;
	} else {
		ret = regmap_update_bits(priv->regmap, MAX96724_MIPI_PHY5(index),
					 MAX96724_MIPI_PHY5_PHY_POL_MAP_2(index),
					 field_prep(MAX96724_MIPI_PHY5_PHY_POL_MAP_2(index), val));
		if (ret)
			return ret;

		ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_PHY5(index),
					 MAX96724_MIPI_PHY5_PHY_POL_MAP_2_CLK(index),
					 phy->mipi.lane_polarities[0]);
		if (ret)
			return ret;
	}

	if (!is_cphy && dpll_freq > 1500000000ull) {
		/* Enable initial deskew with 2 x 32k UI. */
		ret = regmap_write(priv->regmap, MAX96724_MIPI_TX3(index),
				   MAX96724_MIPI_TX3_DESKEW_INIT_AUTO |
				   MAX96724_MIPI_TX3_DESKEW_INIT_8X32K);
		if (ret)
			return ret;

		/* Enable periodic deskew with 2 x 1k UI.. */
		ret = regmap_write(priv->regmap, MAX96724_MIPI_TX4(index),
				   MAX96724_MIPI_TX4_DESKEW_PER_AUTO |
				   MAX96724_MIPI_TX4_DESKEW_PER_2K);
		if (ret)
			return ret;
	} else {
		/* Disable initial deskew. */
		ret = regmap_write(priv->regmap, MAX96724_MIPI_TX3(index), 0x0);
		if (ret)
			return ret;

		/* Disable periodic deskew. */
		ret = regmap_write(priv->regmap, MAX96724_MIPI_TX4(index), 0x0);
		if (ret)
			return ret;
	}

	if (is_cphy) {
		/* Configure C-PHY timings. */
		ret = regmap_write(priv->regmap, MAX96724_MIPI_PHY13,
				   MAX96724_MIPI_PHY13_T_T3_PREBEGIN_64X7);
		if (ret)
			return ret;

		ret = regmap_write(priv->regmap, MAX96724_MIPI_PHY14,
				   MAX96724_MIPI_PHY14_T_T3_PREP_55NS |
				   MAX96724_MIPI_PHY14_T_T3_POST_32X7);
		if (ret)
			return ret;
	}

	/* Put DPLL block into reset. */
	ret = regmap_clear_bits(priv->regmap, MAX96724_DPLL_0(index),
				MAX96724_DPLL_0_CONFIG_SOFT_RST_N);
	if (ret)
		return ret;

	/* Set DPLL frequency. */
	ret = regmap_update_bits(priv->regmap, MAX96724_BACKTOP22(index),
				 MAX96724_BACKTOP22_PHY_CSI_TX_DPLL,
				 FIELD_PREP(MAX96724_BACKTOP22_PHY_CSI_TX_DPLL,
					    div_u64(dpll_freq, 100000000)));
	if (ret)
		return ret;

	/* Enable DPLL frequency. */
	ret = regmap_set_bits(priv->regmap, MAX96724_BACKTOP22(index),
			      MAX96724_BACKTOP22_PHY_CSI_TX_DPLL_EN);
	if (ret)
		return ret;

	/* Pull DPLL block out of reset. */
	return regmap_set_bits(priv->regmap, MAX96724_DPLL_0(index),
			       MAX96724_DPLL_0_CONFIG_SOFT_RST_N);
}

static int max96724_set_phy_mode(struct max_des *des, struct max_des_phy *phy,
				 struct max_des_phy_mode *mode)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = max96724_phy_id(des, phy);
	int ret;

	/* Set alternate memory map modes. */
	ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX51(index),
				 MAX96724_MIPI_TX51_ALT_MEM_MAP_12,
				 mode->alt_mem_map12);
	if (ret)
		return ret;

	ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX51(index),
				 MAX96724_MIPI_TX51_ALT_MEM_MAP_8,
				 mode->alt_mem_map8);
	if (ret)
		return ret;

	ret = regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX51(index),
				 MAX96724_MIPI_TX51_ALT_MEM_MAP_10,
				 mode->alt_mem_map10);
	if (ret)
		return ret;

	return regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX51(index),
				  MAX96724_MIPI_TX51_ALT2_MEM_MAP_8,
				  mode->alt2_mem_map8);
}

static int max96724_set_phy_enable(struct max_des *des, struct max_des_phy *phy,
				   bool enable)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = max96724_phy_id(des, phy);
	unsigned int num_hw_data_lanes;
	unsigned int mask;

	num_hw_data_lanes = max_des_phy_hw_data_lanes(des, phy);

	if (num_hw_data_lanes == 4)
		/* PHY 1 -> bits [1:0] */
		/* PHY 2 -> bits [3:2] */
		mask = MAX96724_MIPI_PHY2_PHY_STDB_N_4(index);
	else
		mask = MAX96724_MIPI_PHY2_PHY_STDB_N_2(index);

	return regmap_assign_bits(priv->regmap, MAX96724_MIPI_PHY2, mask, enable);
}

static int max96724_set_pipe_remap(struct max_des *des,
				   struct max_des_pipe *pipe,
				   unsigned int i,
				   struct max_des_remap *remap)
{
	struct max96724_priv *priv = des_to_priv(des);
	struct max_des_phy *phy = &des->phys[remap->phy];
	unsigned int phy_id = max96724_phy_id(des, phy);
	unsigned int index = pipe->index;
	int ret;

	/* Set source Data Type and Virtual Channel. */
	/* TODO: implement extended Virtual Channel. */
	ret = regmap_write(priv->regmap, MAX96724_MIPI_TX13(index, i),
			   FIELD_PREP(MAX96724_MIPI_TX13_MAP_SRC_DT,
				      remap->from_dt) |
			   FIELD_PREP(MAX96724_MIPI_TX13_MAP_SRC_VC,
				      remap->from_vc));
	if (ret)
		return ret;

	/* Set destination Data Type and Virtual Channel. */
	/* TODO: implement extended Virtual Channel. */
	ret = regmap_write(priv->regmap, MAX96724_MIPI_TX14(index, i),
			   FIELD_PREP(MAX96724_MIPI_TX14_MAP_DST_DT,
				      remap->to_dt) |
			   FIELD_PREP(MAX96724_MIPI_TX14_MAP_DST_VC,
				      remap->to_vc));
	if (ret)
		return ret;

	/* Set destination PHY. */
	return regmap_update_bits(priv->regmap, MAX96724_MIPI_TX45(index, i),
				  MAX96724_MIPI_TX45_MAP_DPHY_DEST(i),
				  field_prep(MAX96724_MIPI_TX45_MAP_DPHY_DEST(i),
					     phy_id));
}

static int max96724_set_pipe_remaps_enable(struct max_des *des,
					   struct max_des_pipe *pipe,
					   unsigned int mask)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;
	int ret;

	ret = regmap_write(priv->regmap, MAX96724_MIPI_TX11(index), mask);
	if (ret)
		return ret;

	return regmap_write(priv->regmap, MAX96724_MIPI_TX12(index), mask >> 8);
}

static int max96724_set_pipe_tunnel_phy(struct max_des *des,
					struct max_des_pipe *pipe,
					struct max_des_phy *phy)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int phy_index = max96724_phy_id(des, phy);

	return regmap_update_bits(priv->regmap, MAX96724_MIPI_TX57(pipe->index),
				  MAX96724_MIPI_TX57_TUN_DEST,
				  FIELD_PREP(MAX96724_MIPI_TX57_TUN_DEST,
					     phy_index));
}

static int max96724_set_pipe_phy(struct max_des *des, struct max_des_pipe *pipe,
				 struct max_des_phy *phy)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int phy_index = max96724_phy_id(des, phy);

	return regmap_update_bits(priv->regmap, MAX96724_MIPI_CTRL_SEL,
				  MAX96724_MIPI_CTRL_SEL_MASK(pipe->index),
				  field_prep(MAX96724_MIPI_CTRL_SEL_MASK(pipe->index),
					     phy_index));
}

static int max96724_set_pipe_enable(struct max_des *des, struct max_des_pipe *pipe,
				    bool enable)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;

	return regmap_assign_bits(priv->regmap, MAX96724_VIDEO_PIPE_EN,
				  MAX96724_VIDEO_PIPE_EN_MASK(index), enable);
}

static int max96724_set_pipe_stream_id(struct max_des *des, struct max_des_pipe *pipe,
				       unsigned int stream_id)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;

	return regmap_update_bits(priv->regmap, MAX96724_VIDEO_PIPE_SEL(index),
				  MAX96724_VIDEO_PIPE_SEL_STREAM(index),
				  field_prep(MAX96724_VIDEO_PIPE_SEL_STREAM(index),
					     stream_id));
}

static int max96724_set_pipe_link(struct max_des *des, struct max_des_pipe *pipe,
				  struct max_des_link *link)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;

	return regmap_update_bits(priv->regmap, MAX96724_VIDEO_PIPE_SEL(index),
				  MAX96724_VIDEO_PIPE_SEL_LINK(index),
				  field_prep(MAX96724_VIDEO_PIPE_SEL_LINK(index),
					     link->index));
}

static int max96724_set_pipe_mode(struct max_des *des,
				  struct max_des_pipe *pipe,
				  struct max_des_pipe_mode *mode)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = pipe->index;
	unsigned int reg, mask, mode_mask;
	int ret;

	/* Set 8bit double mode. */
	ret = regmap_assign_bits(priv->regmap, MAX96724_BACKTOP21(index),
				 MAX96724_BACKTOP21_BPP8DBL(index), mode->dbl8);
	if (ret)
		return ret;

	ret = regmap_assign_bits(priv->regmap, MAX96724_BACKTOP24(index),
				 MAX96724_BACKTOP24_BPP8DBL_MODE(index),
				 mode->dbl8mode);
	if (ret)
		return ret;

	/* Set 10bit double mode. */
	if (index % 4 == 3) {
		reg = MAX96724_BACKTOP30(index);
		mask = MAX96724_BACKTOP30_BPP10DBL3;
		mode_mask = MAX96724_BACKTOP30_BPP10DBL3_MODE;
	} else if (index % 4 == 2) {
		reg = MAX96724_BACKTOP31(index);
		mask = MAX96724_BACKTOP31_BPP10DBL2;
		mode_mask = MAX96724_BACKTOP31_BPP10DBL2_MODE;
	} else if (index % 4 == 1) {
		reg = MAX96724_BACKTOP32(index);
		mask = MAX96724_BACKTOP32_BPP10DBL1;
		mode_mask = MAX96724_BACKTOP32_BPP10DBL1_MODE;
	} else {
		reg = MAX96724_BACKTOP32(index);
		mask = MAX96724_BACKTOP32_BPP10DBL0;
		mode_mask = MAX96724_BACKTOP32_BPP10DBL0_MODE;
	}

	ret = regmap_assign_bits(priv->regmap, reg, mask, mode->dbl10);
	if (ret)
		return ret;

	ret = regmap_assign_bits(priv->regmap, reg, mode_mask, mode->dbl10mode);
	if (ret)
		return ret;

	/* Set 12bit double mode. */
	return regmap_assign_bits(priv->regmap, MAX96724_BACKTOP32(index),
				  MAX96724_BACKTOP32_BPP12(index), mode->dbl12);
}

static int max96724_set_pipe_tunnel_enable(struct max_des *des,
					   struct max_des_pipe *pipe, bool enable)
{
	struct max96724_priv *priv = des_to_priv(des);

	return regmap_assign_bits(priv->regmap, MAX96724_MIPI_TX54(pipe->index),
				  MAX96724_MIPI_TX54_TUN_EN, enable);
}

static int max96724_select_links(struct max_des *des, unsigned int mask)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int link;
	int ret;

	ret = regmap_update_bits(priv->regmap, MAX96724_REG6, MAX96724_REG6_LINK_EN,
				 field_prep(MAX96724_REG6_LINK_EN, mask));
	if (ret)
		return ret;

	ret = regmap_set_bits(priv->regmap, MAX96724_CTRL1,
			      MAX96724_CTRL1_RESET_ONESHOT);
	if (ret)
		return ret;

	/*
	 * Wait for each selected link to report lock before returning, so the
	 * caller does not touch the GMSL reverse control channel (serializer /
	 * remote sensor) before it is up - doing so previously caused
	 * intermittent -EREMOTEIO / -EIO. This replaces the previous fixed
	 * 60 ms wait. Best-effort: a selected link with no device attached
	 * simply times out here without failing the call.
	 */
	for (link = 0; link < des->ops->num_links; link++) {
		unsigned int val;
		int i;

		if (!(mask & BIT(link)))
			continue;

		for (i = 0; i < MAX96724_LINK_LOCK_TIMEOUT_MS / 10; i++) {
			ret = regmap_read(priv->regmap,
					  MAX96724_LINK_LOCK(link), &val);
			if (!ret && (val & MAX96724_LINK_LOCK_LOCKED))
				break;

			msleep(10);
		}

		if (i == MAX96724_LINK_LOCK_TIMEOUT_MS / 10)
			dev_dbg(priv->dev,
				"link %u not locked after one-shot reset\n", link);
	}

	return 0;
}

static int max96724_set_link_version(struct max_des *des,
				     struct max_des_link *link,
				     enum max_serdes_gmsl_version version)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int index = link->index;
	unsigned int val;

	if (version == MAX_SERDES_GMSL_2_6GBPS)
		val = MAX96724_REG26_RX_RATE_6GBPS;
	else
		val = MAX96724_REG26_RX_RATE_3GBPS;

	return regmap_update_bits(priv->regmap, MAX96724_REG26(index),
				  MAX96724_REG26_RX_RATE_PHY(index),
				  field_prep(MAX96724_REG26_RX_RATE_PHY(index), val));
}

static int max96724_set_tpg_timings(struct max96724_priv *priv,
				    const struct max_serdes_tpg_timings *tm)
{
	const struct reg_sequence regs[] = {
		REG_SEQUENCE_3(MAX96724_VS_DLY_2, tm->vs_dly),
		REG_SEQUENCE_3(MAX96724_VS_HIGH_2, tm->vs_high),
		REG_SEQUENCE_3(MAX96724_VS_LOW_2, tm->vs_low),
		REG_SEQUENCE_3(MAX96724_V2H_2, tm->v2h),
		REG_SEQUENCE_2(MAX96724_HS_HIGH_1, tm->hs_high),
		REG_SEQUENCE_2(MAX96724_HS_LOW_1, tm->hs_low),
		REG_SEQUENCE_2(MAX96724_HS_CNT_1, tm->hs_cnt),
		REG_SEQUENCE_3(MAX96724_V2D_2, tm->v2d),
		REG_SEQUENCE_2(MAX96724_DE_HIGH_1, tm->de_high),
		REG_SEQUENCE_2(MAX96724_DE_LOW_1, tm->de_low),
		REG_SEQUENCE_2(MAX96724_DE_CNT_1, tm->de_cnt),
	};
	int ret;

	ret = regmap_multi_reg_write(priv->regmap, regs, ARRAY_SIZE(regs));
	if (ret)
		return ret;

	return regmap_write(priv->regmap, MAX96724_PATGEN_0,
			    FIELD_PREP(MAX96724_PATGEN_0_VTG_MODE,
				       MAX96724_PATGEN_0_VTG_MODE_FREE_RUNNING) |
			    FIELD_PREP(MAX96724_PATGEN_0_DE_INV, tm->de_inv) |
			    FIELD_PREP(MAX96724_PATGEN_0_HS_INV, tm->hs_inv) |
			    FIELD_PREP(MAX96724_PATGEN_0_VS_INV, tm->vs_inv) |
			    FIELD_PREP(MAX96724_PATGEN_0_GEN_DE, tm->gen_de) |
			    FIELD_PREP(MAX96724_PATGEN_0_GEN_HS, tm->gen_hs) |
			    FIELD_PREP(MAX96724_PATGEN_0_GEN_VS, tm->gen_vs));
}

static int max96724_set_tpg_clk(struct max96724_priv *priv, u32 clock)
{
	bool patgen_clk_src = 0;
	u8 pclk_src;
	int ret;

	switch (clock) {
	case 25000000:
		pclk_src = MAX96724_DEBUG_EXTRA_PCLK_SRC_25MHZ;
		break;
	case 75000000:
		pclk_src = MAX96724_DEBUG_EXTRA_PCLK_SRC_75MHZ;
		break;
	case 150000000:
		pclk_src = MAX96724_DEBUG_EXTRA_PCLK_SRC_USE_PIPE;
		patgen_clk_src = MAX96724_VPRBS_PATGEN_CLK_SRC_150MHZ;
		break;
	case 375000000:
		pclk_src = MAX96724_DEBUG_EXTRA_PCLK_SRC_USE_PIPE;
		patgen_clk_src = MAX96724_VPRBS_PATGEN_CLK_SRC_375MHZ;
		break;
	case 0:
		return 0;
	default:
		return -EINVAL;
	}

	/*
	 * TPG data is always injected on link 0, which is always routed to
	 * pipe 0.
	 */
	ret = regmap_update_bits(priv->regmap, MAX96724_VPRBS(0),
				 MAX96724_VPRBS_PATGEN_CLK_SRC,
				 FIELD_PREP(MAX96724_VPRBS_PATGEN_CLK_SRC,
					    patgen_clk_src));
	if (ret)
		return ret;

	return regmap_update_bits(priv->regmap, MAX96724_DEBUG_EXTRA,
				  MAX96724_DEBUG_EXTRA_PCLK_SRC,
				  FIELD_PREP(MAX96724_DEBUG_EXTRA_PCLK_SRC,
					     pclk_src));
}

static int max96724_set_tpg_mode(struct max96724_priv *priv, bool enable)
{
	unsigned int patgen_mode;

	switch (priv->des.tpg_pattern) {
	case MAX_SERDES_TPG_PATTERN_GRADIENT:
		patgen_mode = MAX96724_PATGEN_1_PATGEN_MODE_GRADIENT;
		break;
	case MAX_SERDES_TPG_PATTERN_CHECKERBOARD:
		patgen_mode = MAX96724_PATGEN_1_PATGEN_MODE_CHECKER;
		break;
	default:
		return -EINVAL;
	}

	return regmap_update_bits(priv->regmap, MAX96724_PATGEN_1,
				  MAX96724_PATGEN_1_PATGEN_MODE,
				  FIELD_PREP(MAX96724_PATGEN_1_PATGEN_MODE,
					     enable ? patgen_mode
						    : MAX96724_PATGEN_1_PATGEN_MODE_DISABLED));
}

static int max96724_set_tpg(struct max_des *des,
			    const struct max_serdes_tpg_entry *entry)
{
	struct max96724_priv *priv = des_to_priv(des);
	struct max_serdes_tpg_timings timings = { 0 };
	int ret;

	ret = max_serdes_get_tpg_timings(entry, &timings);
	if (ret)
		return ret;

	ret = max96724_set_tpg_timings(priv, &timings);
	if (ret)
		return ret;

	ret = max96724_set_tpg_clk(priv, timings.clock);
	if (ret)
		return ret;

	ret = max96724_set_tpg_mode(priv, entry);
	if (ret)
		return ret;

	return regmap_assign_bits(priv->regmap, MAX96724_MIPI_PHY0,
				  MAX96724_MIPI_PHY0_FORCE_CSI_OUT_EN, !!entry);
}

static int max96724_fsync_period(struct max96724_priv *priv,
				 const struct max_des_fsync *cfg,
				 unsigned int *period)
{
	unsigned long rate;
	u64 val;

	/*
	 * The generator either counts the 25MHz crystal, or the pixel clock
	 * of the master link's video pipe. Only the crystal has a rate the
	 * driver knows about, so a manual period can only be derived from it.
	 */
	if (!cfg->use_xtal) {
		dev_err(priv->dev,
			"fsync period requires the crystal time base\n");
		return -EINVAL;
	}

	if (!cfg->fps)
		return -EINVAL;

	rate = MAX96724_FSYNC_XTAL_RATE;
	val = DIV_ROUND_CLOSEST(rate, cfg->fps);
	if (!val || val > MAX96724_FSYNC_PERIOD_MAX) {
		dev_err(priv->dev, "unsupported fsync rate %ufps\n", cfg->fps);
		return -EINVAL;
	}

	*period = val;

	return 0;
}

/*
 * Route the generator through one of the deserializer's own pins.
 *
 * The pin is driven by the generator and, on every link of the frame sync
 * group, also announced as a transmitter on the tunnel channel, so the
 * serializers keep receiving the pulse. Boards that do not need the pulse
 * outside the chip leave this out and let the generator feed the tunnel
 * directly.
 */
static int max96724_set_fsync_gen_pin(struct max96724_priv *priv,
				      const struct max_des_fsync *cfg,
				      unsigned int link_mask)
{
	unsigned int pin = cfg->gen_pin;
	unsigned int link;
	int ret;

	/* Push-pull, so the pin can drive a sync input on the board. */
	ret = regmap_update_bits(priv->regmap, MAX96724_GPIO_B(0, pin),
				 MAX96724_GPIO_B_GPIO_TX_ID |
				 MAX96724_GPIO_B_OUT_TYPE,
				 MAX96724_GPIO_B_OUT_TYPE |
				 FIELD_PREP(MAX96724_GPIO_B_GPIO_TX_ID,
					    cfg->tx_id));
	if (ret)
		return ret;

	for (link = 1; link < MAX96724_NUM_LINKS; link++) {
		if (!(link_mask & BIT(link)))
			continue;

		ret = regmap_update_bits(priv->regmap,
					 MAX96724_GPIO_B(link, pin),
					 MAX96724_GPIO_B_GPIO_TX_ID |
					 MAX96724_GPIO_B_GPIO_TX_EN,
					 MAX96724_GPIO_B_GPIO_TX_EN |
					 FIELD_PREP(MAX96724_GPIO_B_GPIO_TX_ID,
						    cfg->tx_id));
		if (ret)
			return ret;
	}

	return regmap_update_bits(priv->regmap, MAX96724_GPIO_A(pin),
				  MAX96724_GPIO_A_GPIO_OUT_DIS |
				  MAX96724_GPIO_A_GPIO_TX_EN |
				  MAX96724_GPIO_A_GPIO_RX_EN,
				  MAX96724_GPIO_A_GPIO_TX_EN);
}

static int max96724_set_fsync(struct max_des *des,
			      const struct max_des_fsync *cfg, bool enable)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int period, val, mode, link_mask;
	int ret;

	if (cfg->tx_id > MAX96724_FSYNC_17_FSYNC_TX_ID >> 3 ||
	    cfg->link_mask & ~MAX96724_FSYNC_15_FS_LINKS)
		return -EINVAL;

	if (cfg->gen_pin != MAX_DES_FSYNC_NO_GEN_PIN &&
	    cfg->gen_pin != MAX96724_FSYNC_GEN_PIN_MFP0 &&
	    cfg->gen_pin != MAX96724_FSYNC_GEN_PIN_MFP7) {
		dev_err(priv->dev,
			"frame sync can only leave through MFP0 or MFP7\n");
		return -EINVAL;
	}

	if (!enable) {
		/*
		 * Stop the generator, so that no truncated pulse is forwarded
		 * to the serializers.
		 */
		return regmap_update_bits(priv->regmap, MAX96724_FSYNC_0,
					  MAX96724_FSYNC_0_EN_VS_GEN |
					  MAX96724_FSYNC_0_FSYNC_MODE,
					  FIELD_PREP(MAX96724_FSYNC_0_FSYNC_MODE,
						     MAX96724_FSYNC_0_FSYNC_MODE_OFF));
	}

	ret = max96724_fsync_period(priv, cfg, &period);
	if (ret)
		return ret;

	/*
	 * Tunnel channel ID, must match the serializers' GPIO_RX_ID. The
	 * generator is a tunnel source of its own, no local pin has to be
	 * enabled for transmission. Enabling one with the same ID would put a
	 * second source on the channel and corrupt the pulse train.
	 */
	ret = regmap_update_bits(priv->regmap, MAX96724_FSYNC_17,
				 MAX96724_FSYNC_17_FSYNC_TX_ID,
				 FIELD_PREP(MAX96724_FSYNC_17_FSYNC_TX_ID,
					    cfg->tx_id));
	if (ret)
		return ret;

	/*
	 * An empty link mask selects every enabled link, otherwise only the
	 * links belonging to the frame sync group are driven.
	 */
	link_mask = cfg->link_mask;
	val = MAX96724_FSYNC_15_FS_GPIO_TYPE;
	if (cfg->use_xtal)
		val |= MAX96724_FSYNC_15_FS_USE_XTAL;
	if (link_mask) {
		val |= FIELD_PREP(MAX96724_FSYNC_15_FS_LINKS, link_mask);
	} else {
		val |= MAX96724_FSYNC_15_AUTO_FS_LINKS;
		link_mask = MAX96724_FSYNC_15_FS_LINKS;
	}

	ret = regmap_update_bits(priv->regmap, MAX96724_FSYNC_15,
				 MAX96724_FSYNC_15_FS_GPIO_TYPE |
				 MAX96724_FSYNC_15_FS_USE_XTAL |
				 MAX96724_FSYNC_15_AUTO_FS_LINKS |
				 MAX96724_FSYNC_15_FS_LINKS, val);
	if (ret)
		return ret;

	/* One pulse per frame. */
	ret = regmap_update_bits(priv->regmap, MAX96724_FSYNC_1,
				 MAX96724_FSYNC_1_FSYNC_PER_DIV, 0);
	if (ret)
		return ret;

	ret = regmap_write(priv->regmap, MAX96724_FSYNC_5, period & 0xff);
	if (ret)
		return ret;

	ret = regmap_write(priv->regmap, MAX96724_FSYNC_6, (period >> 8) & 0xff);
	if (ret)
		return ret;

	ret = regmap_write(priv->regmap, MAX96724_FSYNC_7, (period >> 16) & 0xff);
	if (ret)
		return ret;

	val = MAX96724_FSYNC_0_EN_VS_GEN;
	mode = MAX96724_FSYNC_0_FSYNC_MODE_TUNNEL;

	if (cfg->gen_pin != MAX_DES_FSYNC_NO_GEN_PIN) {
		ret = max96724_set_fsync_gen_pin(priv, cfg, link_mask);
		if (ret)
			return ret;

		mode = MAX96724_FSYNC_0_FSYNC_MODE_GPIO_OUT;
		if (cfg->gen_pin == MAX96724_FSYNC_GEN_PIN_MFP7)
			val |= MAX96724_FSYNC_0_FSYNC_OUT_PIN;
	}

	/* Start the generator last, once its whole configuration is live. */
	return regmap_update_bits(priv->regmap, MAX96724_FSYNC_0,
				  MAX96724_FSYNC_0_EN_VS_GEN |
				  MAX96724_FSYNC_0_FSYNC_OUT_PIN |
				  MAX96724_FSYNC_0_FSYNC_MODE |
				  MAX96724_FSYNC_0_FSYNC_METH,
				  val |
				  FIELD_PREP(MAX96724_FSYNC_0_FSYNC_MODE, mode) |
				  FIELD_PREP(MAX96724_FSYNC_0_FSYNC_METH,
					     MAX96724_FSYNC_0_FSYNC_METH_MANUAL));
}

static int max96724_log_status(struct max_des *des)
{
	struct max96724_priv *priv = des_to_priv(des);
	unsigned int status, err_cnt, ctrl;
	int ret;

	if (!des->fsync.enabled)
		return 0;

	ret = regmap_read(priv->regmap, MAX96724_FSYNC_22, &status);
	if (ret)
		return ret;

	ret = regmap_read(priv->regmap, MAX96724_FSYNC_16, &err_cnt);
	if (ret)
		return ret;

	/* Read back the control register, the generator is silent without it. */
	ret = regmap_read(priv->regmap, MAX96724_FSYNC_0, &ctrl);
	if (ret)
		return ret;

	dev_info(priv->dev,
		 "fsync: active: %u, fps: %u, locked: %u, loss_of_lock: %u, err_cnt: %lu, ctrl: 0x%02x\n",
		 des->fsync_active, des->fsync.fps,
		 !!(status & MAX96724_FSYNC_22_FSYNC_LOCKED),
		 !!(status & MAX96724_FSYNC_22_LOSS_OF_LOCK),
		 FIELD_GET(MAX96724_FSYNC_16_FSYNC_ERR_CNT, err_cnt), ctrl);

	if (des->fsync.gen_pin != MAX_DES_FSYNC_NO_GEN_PIN) {
		unsigned int pin = des->fsync.gen_pin;

		ret = regmap_read(priv->regmap, MAX96724_GPIO_A(pin), &ctrl);
		if (ret)
			return ret;

		dev_info(priv->dev, "fsync: gen pin: MFP%u, level: %u\n", pin,
			 !!(ctrl & MAX96724_GPIO_A_GPIO_IN));
	}

	return 0;
}

static const struct max_serdes_tpg_entry max96724_tpg_entries[] = {
	MAX_TPG_ENTRY_640X480P60_RGB888,
	MAX_TPG_ENTRY_1920X1080P30_RGB888,
	MAX_TPG_ENTRY_1920X1080P60_RGB888,
};

static const struct max_des_ops max96724_ops = {
	.num_phys = 4,
	.num_links = 4,
	.num_remaps_per_pipe = 16,
	.phys_configs = {
		.num_configs = ARRAY_SIZE(max96724_phys_configs),
		.configs = max96724_phys_configs,
	},
	.tpg_entries = {
		.num_entries = ARRAY_SIZE(max96724_tpg_entries),
		.entries = max96724_tpg_entries,
	},
	.tpg_mode = MAX_SERDES_GMSL_PIXEL_MODE,
	.tpg_patterns = BIT(MAX_SERDES_TPG_PATTERN_CHECKERBOARD) |
			BIT(MAX_SERDES_TPG_PATTERN_GRADIENT),
	.use_atr = true,
#ifdef CONFIG_VIDEO_ADV_DEBUG
	.reg_read = max96724_reg_read,
	.reg_write = max96724_reg_write,
#endif
	.log_pipe_status = max96724_log_pipe_status,
	.log_phy_status = max96724_log_phy_status,
	.log_status = max96724_log_status,
	.set_enable = max96724_set_enable,
	.init = max96724_init,
	.init_phy = max96724_init_phy,
	.set_phy_mode = max96724_set_phy_mode,
	.set_phy_enable = max96724_set_phy_enable,
	.set_pipe_stream_id = max96724_set_pipe_stream_id,
	.set_pipe_link = max96724_set_pipe_link,
	.set_pipe_enable = max96724_set_pipe_enable,
	.set_pipe_remap = max96724_set_pipe_remap,
	.set_pipe_remaps_enable = max96724_set_pipe_remaps_enable,
	.set_pipe_mode = max96724_set_pipe_mode,
	.set_tpg = max96724_set_tpg,
	.select_links = max96724_select_links,
	.set_link_version = max96724_set_link_version,
	.set_fsync = max96724_set_fsync,
};

static const struct max96724_chip_info max96724_info = {
	.versions = BIT(MAX_SERDES_GMSL_2_3GBPS) |
		    BIT(MAX_SERDES_GMSL_2_6GBPS),
	.modes = BIT(MAX_SERDES_GMSL_PIXEL_MODE) |
		 BIT(MAX_SERDES_GMSL_TUNNEL_MODE),
	.set_pipe_tunnel_enable = max96724_set_pipe_tunnel_enable,
	.set_pipe_phy = max96724_set_pipe_phy,
	.set_pipe_tunnel_phy = max96724_set_pipe_tunnel_phy,
	.supports_pipe_stream_autoselect = true,
	.num_pipes = 4,
};

static const struct max96724_chip_info max96724f_info = {
	.versions = BIT(MAX_SERDES_GMSL_2_3GBPS),
	.modes = BIT(MAX_SERDES_GMSL_PIXEL_MODE) |
		 BIT(MAX_SERDES_GMSL_TUNNEL_MODE),
	.set_pipe_tunnel_enable = max96724_set_pipe_tunnel_enable,
	.set_pipe_phy = max96724_set_pipe_phy,
	.set_pipe_tunnel_phy = max96724_set_pipe_tunnel_phy,
	.supports_pipe_stream_autoselect = true,
	.num_pipes = 4,
};

static const struct max96724_chip_info max96712_info = {
	.versions = BIT(MAX_SERDES_GMSL_2_3GBPS) |
		    BIT(MAX_SERDES_GMSL_2_6GBPS),
	.modes = BIT(MAX_SERDES_GMSL_PIXEL_MODE),
	.num_pipes = 8,
};

static int max96724_probe(struct i2c_client *client)
{
	struct device *dev = &client->dev;
	struct max96724_priv *priv;
	struct max_des_ops *ops;
	int ret;

	priv = devm_kzalloc(dev, sizeof(*priv), GFP_KERNEL);
	if (!priv)
		return -ENOMEM;

	ops = devm_kzalloc(dev, sizeof(*ops), GFP_KERNEL);
	if (!ops)
		return -ENOMEM;

	priv->info = device_get_match_data(dev);
	if (!priv->info) {
		dev_err(dev, "Failed to get match data\n");
		return -ENODEV;
	}

	priv->dev = dev;
	priv->client = client;
	i2c_set_clientdata(client, priv);

	priv->regmap = devm_regmap_init_i2c(client, &max96724_i2c_regmap);
	if (IS_ERR(priv->regmap))
		return PTR_ERR(priv->regmap);

	priv->gpiod_enable = devm_gpiod_get_optional(&client->dev, "enable",
						     GPIOD_OUT_LOW);
	if (IS_ERR(priv->gpiod_enable))
		return PTR_ERR(priv->gpiod_enable);

	if (priv->gpiod_enable) {
		/* PWDN must be held for 1us for reset */
		udelay(1);

		gpiod_set_value_cansleep(priv->gpiod_enable, 1);

		/* Maximum power-up time (tLOCK) 4ms */
		usleep_range(4000, 5000);
	}

	*ops = max96724_ops;
	ops->versions = priv->info->versions;
	ops->modes = priv->info->modes;
	ops->num_pipes = priv->info->num_pipes;
	ops->set_pipe_tunnel_enable = priv->info->set_pipe_tunnel_enable;
	ops->set_pipe_phy = priv->info->set_pipe_phy;
	ops->set_pipe_tunnel_phy = priv->info->set_pipe_tunnel_phy;
	priv->des.ops = ops;

	priv->des.pipe_stream_autoselect = priv->info->supports_pipe_stream_autoselect;

	ret = max96724_reset(priv);
	if (ret)
		return ret;

	return max_des_probe(client, &priv->des);
}

static void max96724_remove(struct i2c_client *client)
{
	struct max96724_priv *priv = i2c_get_clientdata(client);

	max_des_remove(&priv->des);

	gpiod_set_value_cansleep(priv->gpiod_enable, 0);
}

static void max96724_shutdown(struct i2c_client *client)
{
	struct max96724_priv *priv = i2c_get_clientdata(client);

	/*
	 * Reset the remote serializers while the GMSL link is still up so a
	 * warm reboot leaves them in a clean power-up state (see
	 * max_des_shutdown). Without this the next probe fails with -121.
	 */
	max_des_shutdown(&priv->des);
}

static const struct acpi_device_id max96724_acpi_ids[] = {
	{ "INTC1139", (kernel_ulong_t) &max96724_info },
	{}
};
MODULE_DEVICE_TABLE(acpi, max96724_acpi_ids);

static const struct of_device_id max96724_of_table[] = {
	{ .compatible = "maxim,max96712", .data = &max96712_info },
	{ .compatible = "maxim,max96724", .data = &max96724_info },
	{ .compatible = "maxim,max96724f", .data = &max96724f_info },
	{ .compatible = "maxim,max96724r", .data = &max96724f_info },
	{ },
};
MODULE_DEVICE_TABLE(of, max96724_of_table);

static struct i2c_driver max96724_i2c_driver = {
	.driver	= {
		.name = "max96724",
		.of_match_table	= max96724_of_table,
		.acpi_match_table = max96724_acpi_ids,
	},
	.probe = max96724_probe,
	.remove = max96724_remove,
	.shutdown = max96724_shutdown,
};

module_i2c_driver(max96724_i2c_driver);

MODULE_IMPORT_NS("MAX_SERDES");
MODULE_DESCRIPTION("Maxim MAX96724 Quad GMSL2 Deserializer Driver");
MODULE_AUTHOR("Cosmin Tanislav <cosmin.tanislav@analog.com>");
MODULE_LICENSE("GPL");
