#!/bin/sh
# Force the primary connected output to 1920x1080 at GNOME session start.
#
# Both TX68 and KM7 have a Mali-G31 GPU too weak to compose a 4K desktop
# smoothly, but a lot of the panels these boxes get plugged into report 4K
# as their native/preferred EDID mode, so left alone the driver picks 4K.
#
# This intentionally only ever selects a mode `xrandr` already lists for the
# output (i.e. one the monitor's own EDID advertises), never a synthesized
# timing. TX68 used to force 1080p at the kernel cmdline layer via
# `video=HDMI-A-1:1920x1080@60`, but Linux's video= parser generates that as
# a CVT reduced-blanking timing rather than the standard CEA-861 timing
# monitors actually list -- confirmed live that some panels reject the RB
# timing outright, which hung the boot at a black screen because the kernel
# modeset never completed. Doing it here, against a mode xrandr already
# knows the connector supports, avoids that failure mode entirely.
# xrandr itself refuses a --mode argument that isn't in the output's own
# mode list, so no separate "is this mode supported" check is needed here --
# if the EDID doesn't list 1920x1080, this simply fails harmlessly and the
# session keeps whatever mode the kernel already negotiated.
output=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1; exit}')
[ -n "$output" ] || exit 0

xrandr --output "$output" --mode 1920x1080 2>/dev/null
exit 0
