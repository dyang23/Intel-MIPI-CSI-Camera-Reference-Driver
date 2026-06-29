## Description

This document details the configuration settings for the S56 GMSL sensor, providing essential information for system integration. The table below presents the key parameters and their respective values used during system setup and validation.

## BIOS Configuration Table


### MIPI Camera Configuration for IPU75XA

Config path: `Intel Advanced Menu`->`System Agent (SA) Configuration`->`MIPI Camera Configuration`
Select "Disable" for Camera1 Link options and Camera2 Link Options

#### Connected to C-PHY of MAX96724 AIC

![AIC jumper connections](../isx031/max96724-fabb-cphy.png)

## Sensor Verification

Upon setup completion, verify sensor with:

    media-ctl -p

For AIC MAX96724

![link-port](../isx031/max96724-link-port.png)

![link-port](../isx031/max96724-link-port2.png)

#### Number of Stream (Single Stream / Multi Stream) Selection

| Number of Stream | Command Pipeline |
|---|---|
| x2 | v4l2-ctl -d /dev/video0 --stream-mmap --stream-count=10 --stream-to=./stream0.out \& v4l2-ctl -d /dev/video1 --stream-mmap --stream-count=10 --stream-to=./stream1.out \& |