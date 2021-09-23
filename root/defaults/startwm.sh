#!/bin/bash
PULSE_SCRIPT="/etc/xrdp/pulse/default.pa" 
HOME="/config" 
pulseaudio --start
/usr/bin/openbox-session > /dev/null 2>&1
