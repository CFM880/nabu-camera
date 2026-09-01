# Nabu autofocus prototype

`nabu-autofocus` is a userspace autofocus prototype for the Xiaomi Pad 5 rear
OV13B10 camera and CN3927 lens. It measures the central part of the libcamera
preview with a Tenengrad sharpness metric and drives the lens through
`V4L2_CID_FOCUS_ABSOLUTE`.

Build it with:

```sh
make -C camera-app
```

Close other camera preview applications before starting continuous autofocus:

```sh
camera-app/nabu-autofocus
```

The default mode opens its own preview window, performs a coarse and fine
focus scan, and refocuses when the locked image sharpness drops substantially.
Click or tap the preview to refocus a 30% region around that point. Press
`Ctrl+C` to stop it. A successful tap focus is held for five seconds before
continuous autofocus is allowed to scan again; another tap restarts the hold.

To focus once without opening a preview window:

```sh
camera-app/nabu-autofocus --once
```

An image-space focus point can also be supplied explicitly. For the 640x480
analysis stream, this example focuses a region near the upper-left quarter:

```sh
camera-app/nabu-autofocus --once --point 160,120
```

Expected libcamera sensor crop warnings can be hidden while testing with:

```sh
LIBCAMERA_LOG_LEVELS='*:FATAL' camera-app/nabu-autofocus
```
