#!/usr/bin/env bash
set -e

PLASMOID_ID="com.github.tesla.plasmadocker"

if kpackagetool6 -t Plasma/Applet --list 2>/dev/null | grep -q "$PLASMOID_ID"; then
    kpackagetool6 -t Plasma/Applet --remove "$PLASMOID_ID"
    echo "✅ Widget removed"
else
    echo "ℹ️  Widget was not installed"
fi
