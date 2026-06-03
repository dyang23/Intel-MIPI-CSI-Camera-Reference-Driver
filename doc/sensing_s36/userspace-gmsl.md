## Description

This document details the configuration settings for the ISX031 GMSL sensor, providing essential information for system integration. The table below presents the key parameters and their respective values used during system setup and validation.

## BIOS Configuration Table


### MIPI Camera Configuration for IPU75XA

Config path: `Intel Advanced Menu`->`System Agent (SA) Configuration`->`MIPI Camera Configuration`
Select "Disable" for Camera1 Link options and Camera2 Link Options

#### Connected to C-PHY of MAX96724 AIC

![AIC jumper connections](../isx031/max96724-fabb-cphy.png)

## Sensor Verification

Upon setup completion, verify sensor with:

    media-ctl -p

## Sample Userspace Command

> **Note**: Refer to icamerasrc device-name property for more sensor details.

##### How to relate Sensor Number with AIC Link Port

| AIC Link Port | Sensor Number |
|---            |---            |
| A             | 1             |
| B             | 2             |

For AIC MAX96724

![link-port](../isx031/max96724-link-port.png)

![link-port](../isx031/max96724-link-port2.png)

#### Number of Stream (Single Stream / Multi Stream) Selection

| Number of Stream | Command Pipeline |
|---|---|
| x1 | gst-launch-1.0 v4l2src device=/dev/video0 ! 'video/x-raw,format=UYVY,width=1920,height=1536,framerate=30/1,pixel-aspect-ratio=1/1' ! glimagesink sync=false |
| x2 | gst-launch-1.0 v4l2src device=/dev/video0 ! 'video/x-raw,format=UYVY,width=1920,height=1536,framerate=30/1,pixel-aspect-ratio=1/1' ! glimagesink sync=false ; gst-launch-1.0 v4l2src device=/dev/video0 ! 'video/x-raw,format=UYVY,width=1920,height=1536,framerate=30/1,pixel-aspect-ratio=1/1' ! glimagesink sync=false |