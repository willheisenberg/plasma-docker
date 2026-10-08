#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLASMOID_ID="com.github.tesla.plasmadocker"

if kpackagetool6 -t Plasma/Applet --list | grep -q "$PLASMOID_ID"; then
    echo "🔄 Upgrading Docker Containers widget..."
    kpackagetool6 -t Plasma/Applet --upgrade "$DIR/package"
else
    echo "📥 Installing Docker Containers widget..."
    kpackagetool6 -t Plasma/Applet --install "$DIR/package"
fi

echo
echo "✅ Done. Right click the panel → 'Add Widgets…' → search for 'Docker Containers'."
echo "   If it does not show up yet: systemctl --user restart plasma-plasmashell.service"
