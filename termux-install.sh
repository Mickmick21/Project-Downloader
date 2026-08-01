#!/bin/bash
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

write_green()  { echo -e "${GREEN}$1${NC}"; }
write_blue()   { echo -e "${CYAN}$1${NC}"; }
write_red()    { echo -e "${RED}$1${NC}"; }
write_yellow() { echo -e "${YELLOW}$1${NC}"; }

echo
echo "Installing dependencies, please wait..."
echo
pkg update -y
pkg upgrade -y
pkg install -y nodejs python3 git curl zip jq
if [ $? -ne 0 ]; then
    write_red "\n\n✗ Failed to install dependencies."
    exit
fi
write_green "\n\n✓ Successfully installed dependencies."
echo "Downloading Project Downloader to "~"..."
git clone https://github.com/Mickmick21/Project-Downloader.git
if [ $? -ne 0 ]; then
    write_red "\n\n✗ Failed to download Project Downloader."
    exit
fi
write_green "\n\n✓ Successfully downloaded Project Downloader."
write_green "\n✓ Done ! Run '~/Project-Downloader/project-downloader.sh' to use Project Downloader."
