#!/bin/bash
# Makes the test fonts from a free Hebrew font and installs them the way a user installs fonts (into ~/Library/Fonts).
set -eu
python3 -m pip install --quiet fonttools
mkdir -p base out made
curl -fsSL -o base/Heebo.ttf 'https://github.com/google/fonts/raw/main/ofl/heebo/Heebo%5Bwght%5D.ttf'
curl -fsSL -o out/OFL-Heebo.txt 'https://github.com/google/fonts/raw/main/ofl/heebo/OFL.txt'
python3 font-names/make_fonts.py base/Heebo.ttf made font-names
mkdir -p ~/Library/Fonts
cp made/* ~/Library/Fonts/
echo "font files in the user's own folder: $(ls ~/Library/Fonts | wc -l)"
# the system takes a moment to notice new fonts
sleep 8
