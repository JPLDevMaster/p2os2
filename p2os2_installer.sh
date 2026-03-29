#!/usr/bin/env bash

# ! set -e causes the script to abort on any non-zero exit. Keep this in mind
# ! when adding new commands, wrap anything expected to fail with "|| true".
set -e

# Suppress the interactive needrestart ncurses dialog that pops up mid-install
# asking which services to restart. DEBIAN_FRONTEND=noninteractive handles dpkg
# prompts, NEEDRESTART_MODE=a tells needrestart to auto-restart everything.
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Helper variables for terminal formatting.
BOLD="\e[1m"
RESET="\e[0m"
GREEN="\e[32m"
BLUE="\e[34m"
RED="\e[31m"
YELLOW="\e[33m"

echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}[P2OS]: Starting ROS 2 Humble Driver Installer (Real Robot)${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo ""

# Silence needrestart at the config level as well, so it stays quiet even for
# packages installed later via rosdep or other tools.
if [ -f /etc/needrestart/needrestart.conf ]; then
    sudo sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/g" \
        /etc/needrestart/needrestart.conf 2>/dev/null || true
fi

# ----------------------------------------------------------------------
# [0] User Configuration
# ----------------------------------------------------------------------
DEFAULT_WS=~/pioneer_ws
read -p "[P2OS]: Enter the path for your workspace (Default: $DEFAULT_WS): " USER_WS_INPUT
WORKSPACE_DIR=${USER_WS_INPUT:-$DEFAULT_WS}

# SWAP configuration.
DEFAULT_SWAP="2GB"
read -p "[P2OS]: Enter SWAP size (e.g., 500MB, 1GB, 4GB) or '0' to skip (Default: $DEFAULT_SWAP): " USER_SWAP_INPUT
SWAP_SIZE=${USER_SWAP_INPUT:-$DEFAULT_SWAP}

# Network configuration.
echo ""
echo -e "${YELLOW}We will configure a PRIMARY connection (Lab) and a BACKUP Hotspot.${RESET}"

TARGET_SSID=""
while [[ -z "$TARGET_SSID" ]]; do
    read -p "Enter the Lab Wi-Fi Name (SSID): " TARGET_SSID
    if [[ -z "$TARGET_SSID" ]]; then
        echo -e "${RED}[ERROR] SSID cannot be empty.${RESET}"
    fi
done

TARGET_PASS=""
while [[ ${#TARGET_PASS} -lt 8 ]]; do
    read -s -p "Enter the Lab Wi-Fi Password (min 8 chars): " TARGET_PASS
    echo ""
    if [[ ${#TARGET_PASS} -lt 8 ]]; then
        echo -e "${RED}[ERROR] Wi-Fi password must be at least 8 characters long (WPA2 standard).${RESET}"
        TARGET_PASS=""
    fi
done

# * Validate IP format with a basic regex before accepting it, so we don't hand
# * a garbage string to nmcli later and get a cryptic failure mid-install.
STATIC_IP=""
while true; do
    echo -e "${BOLD}[P2OS]: A UNIQUE static IP is REQUIRED for this robot.${RESET}"
    read -p "[P2OS]: Enter the Static IP (e.g., 192.168.1.100): " STATIC_IP
    if [[ "$STATIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        break
    fi
    echo -e "${RED}[ERROR] Invalid IP format. Please use format: 192.168.X.Y${RESET}"
    echo ""
done

DEFAULT_GW=$(echo "$STATIC_IP" | cut -d'.' -f1-3).1
read -p "Enter the Lab Gateway IP (Default: $DEFAULT_GW): " USER_GW_INPUT
TARGET_GATEWAY=${USER_GW_INPUT:-$DEFAULT_GW}

DOMAIN_ID=""
while [[ ! "$DOMAIN_ID" =~ ^[0-9]+$ ]] || [ "$DOMAIN_ID" -lt 0 ] || [ "$DOMAIN_ID" -gt 101 ]; do
    read -p "[P2OS]: Enter the ROS_DOMAIN_ID (0-101) for this robot (Default: 0): " INPUT_ID
    DOMAIN_ID=${INPUT_ID:-0}

    if [[ ! "$DOMAIN_ID" =~ ^[0-9]+$ ]] || [ "$DOMAIN_ID" -lt 0 ] || [ "$DOMAIN_ID" -gt 101 ]; then
        echo -e "${RED}[ERROR] ROS_DOMAIN_ID must be a number between 0 and 101.${RESET}"
    fi
done

echo ""
echo -e "[Config] Workspace:     ${BOLD}$WORKSPACE_DIR${RESET}"
echo -e "[Config] Swap Size:     ${BOLD}$SWAP_SIZE${RESET}"
echo -e "[Config] Wi-Fi SSID:    ${BOLD}$TARGET_SSID${RESET}"
echo -e "[Config] Static IP:     ${BOLD}$STATIC_IP${RESET}"
echo -e "[Config] Gateway:       ${BOLD}$TARGET_GATEWAY${RESET}"
echo -e "[Config] ROS_DOMAIN_ID: ${BOLD}$DOMAIN_ID${RESET}"
echo ""

echo -e "[P2OS]: Workspace will be created at: ${BOLD}$WORKSPACE_DIR${RESET}"
echo ""

# ----------------------------------------------------------------------
# [1] System Setup: Locale & Repositories
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 1] Configuring Locale and System Sources...${RESET}"

# Make sure the system locale is UTF-8, ROS tooling can misbehave without it.
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# Enable the Universe repository, needed for several ROS dependencies.
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y

# Install the ros2-apt-source package which sets up the ROS 2 apt repository
# automatically, replacing the old key-based method.
sudo apt update && sudo apt install curl -y
export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}')
curl -L -o /tmp/ros2-apt-source.deb "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb"
sudo dpkg -i /tmp/ros2-apt-source.deb

echo ""

# ----------------------------------------------------------------------
# [2] Install ROS 2 Humble Base
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 2] Installing ROS 2 Humble Base...${RESET}"
sudo apt update

# ros-base is the barebones install, no GUI tools, which is exactly what we
# want on the robot. Saves a lot of disk space and install time.
sudo apt install -y ros-humble-ros-base

echo ""

# ----------------------------------------------------------------------
# [3] Install Build Tools
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 3] Installing Build Tools...${RESET}"

sudo apt install -y build-essential python3-colcon-common-extensions python3-rosdep python3-vcstool

# Only initialise rosdep if it hasn't been done already.
if [ ! -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    sudo rosdep init
fi
rosdep update

echo ""

# ----------------------------------------------------------------------
# [4] Workspace Setup & Cloning Repos
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 4] Setting up Workspace and Cloning P2OS...${RESET}"

mkdir -p "$WORKSPACE_DIR/src"
cd "$WORKSPACE_DIR/src"

# Clone (or update) the main P2OS driver repository.
if [ ! -d "p2os2" ]; then
    echo -e "${BLUE}[INFO] Cloning p2os2 repository...${RESET}"
    git clone -b p3dx-enabled https://github.com/JPLDevMaster/p2os2.git
else
    echo -e "${BLUE}[INFO] p2os2 repo already exists. Pulling latest...${RESET}"
    cd p2os2
    git checkout p3dx-enabled
    git pull
    cd ..
fi

# Clone (or update) the Hokuyo URG node for the LiDAR.
if [ ! -d "urg_node2" ]; then
    echo -e "${BLUE}[INFO] Cloning urg_node2 repository...${RESET}"
    git clone --recursive https://github.com/Hokuyo-aut/urg_node2.git
    rosdep update
    # * The -y flag is required here, without it rosdep will pause and wait
    # * for manual confirmation, which breaks the unattended install.
    rosdep install -i --from-paths urg_node2 -y
else
    echo -e "${BLUE}[INFO] urg_node2 repo already exists. Pulling latest...${RESET}"
    cd urg_node2
    git pull
    cd ..
fi

# Patch urg_node2 to use the serial config instead of ethernet, since the
# Hokuyo on this robot is connected via USB-Serial.
echo -e "${BLUE}[INFO] Patching urg_node2.launch.py to use Serial config...${RESET}"
sed -i "s/'params_ether.yaml'/'params_serial.yaml'/g" urg_node2/launch/urg_node2.launch.py

echo ""

# ----------------------------------------------------------------------
# [5] Build Workspace
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 5] Building Workspace...${RESET}"

cd "$WORKSPACE_DIR"

# Source ROS 2 so colcon can find everything it needs.
source /opt/ros/humble/setup.bash

# Install dependencies, explicitly skipping Gazebo and simulation packages.
# We do not want those heavy tools on the physical robot.
echo -e "${BLUE}[INFO] Installing dependencies (skipping simulation tools)...${RESET}"
rosdep install --from-paths src --ignore-src -r -y \
  --skip-keys "gazebo_ros gz_plugin_vendor gz_sim_vendor ros_gz_bridge ros_gz_sim ros_gz_interfaces"

# Handle swap creation before the build starts, the RPi3 only has 1GB of RAM
# and colcon with multiple workers will OOM without extra swap.
if [[ "$SWAP_SIZE" == "0" ]]; then
    echo -e "${BLUE}[INFO] User selected 0. Removing any existing swap...${RESET}"
    if [ -f /swapfile ]; then
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
        # Remove the old fstab entry if it exists.
        sudo sed -i '/\/swapfile/d' /etc/fstab
    fi
else
    # Remove the existing swapfile so we can safely resize it.
    if [ -f /swapfile ]; then
        echo -e "${BLUE}[INFO] Existing swap found. Removing to apply new size ($SWAP_SIZE)...${RESET}"
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
        sudo sed -i '/\/swapfile/d' /etc/fstab
    fi

    echo -e "${BLUE}[INFO] Creating $SWAP_SIZE swap file...${RESET}"

    # * fallocate is fast but fails on some ext4 configs on SD cards. Fall
    # * back to dd if it doesn't work, which is slower but always reliable.
    if ! sudo fallocate -l $SWAP_SIZE /swapfile 2>/dev/null; then
        echo -e "${YELLOW}[WARN] fallocate failed, falling back to dd (this will take a moment)...${RESET}"
        # Convert SWAP_SIZE to MB for dd. We handle GB and MB units.
        if [[ "$SWAP_SIZE" =~ ([0-9]+)GB ]]; then
            SWAP_MB=$(( ${BASH_REMATCH[1]} * 1024 ))
        elif [[ "$SWAP_SIZE" =~ ([0-9]+)MB ]]; then
            SWAP_MB=${BASH_REMATCH[1]}
        else
            SWAP_MB=2048
            echo -e "${YELLOW}[WARN] Could not parse swap size '$SWAP_SIZE', defaulting to 2GB.${RESET}"
        fi
        sudo dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_MB status=progress
    fi

    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
    echo -e "${BLUE}[INFO] Swap created and enabled.${RESET}"

    # * Persist the swap in fstab so it survives the mandatory reboot at the
    # * end of this script. Without this line, the swap is gone after the first
    # * reboot and the robot will OOM on the next heavy operation.
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
    fi
fi

# Verify swap is visible.
free -h

# Build with a single parallel worker and Release mode. Without --parallel-workers 1
# colcon spawns multiple compiler processes simultaneously and the RPi3 will almost
# certainly OOM-kill the build. Release mode also reduces binary size noticeably.
colcon build \
    --parallel-workers 1 \
    --cmake-args -DCMAKE_BUILD_TYPE=Release

echo ""

# ----------------------------------------------------------------------
# [6] Bashrc Setup
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 6] Updating ~/.bashrc...${RESET}"

MARKER_START="# P2OS_SETUP_START"
MARKER_END="# P2OS_SETUP_END"

# Remove any old block from a previous run before writing the fresh one.
if grep -qF "$MARKER_START" ~/.bashrc; then
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" ~/.bashrc
fi

# Write the sourcing block. Using markers makes this idempotent and easy to
# remove manually if needed (the reset_network alias handles NetworkManager cleanup).
echo "" >> ~/.bashrc
echo "$MARKER_START" >> ~/.bashrc
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
echo "source $WORKSPACE_DIR/install/local_setup.bash" >> ~/.bashrc
echo "export ROS_DOMAIN_ID=$DOMAIN_ID" >> ~/.bashrc
echo "alias reset_network='sudo nmcli con delete \"Lab-Connection\" && sudo nmcli con delete \"Hotspot-Fallback\" && echo \"Profiles deleted. Reverting to defaults.\"' " >> ~/.bashrc
echo "$MARKER_END" >> ~/.bashrc

echo -e "${BLUE}[INFO] Added workspace sourcing to ~/.bashrc.${RESET}"
echo ""

# ----------------------------------------------------------------------
# [7] Permissions
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 7] Setting Serial Port Permissions...${RESET}"

# The user needs to be in the dialout group to access /dev/ttyUSB0 without sudo.
# This only takes effect after a reboot (which we require at the end anyway).
sudo usermod -aG dialout $USER
echo -e "${BLUE}[INFO] User added to 'dialout' group.${RESET}"

echo ""

# ----------------------------------------------------------------------
# [8] Configure Failover Network (NetworkManager)
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 8] Configuring Network Manager (Failover Mode)...${RESET}"

sudo apt install -y network-manager

# Remove any conflicting Netplan files that would fight with NetworkManager.
echo -e "${BLUE}[INFO] Checking for conflicting Netplan files...${RESET}"

if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    echo -e "${BLUE}[INFO] Removing conflicting file: 50-cloud-init.yaml${RESET}"
    sudo rm -f /etc/netplan/50-cloud-init.yaml
fi

if [ -f /etc/netplan/99-static-ip.yaml ]; then
    echo -e "${BLUE}[INFO] Removing conflicting file: 99-static-ip.yaml${RESET}"
    sudo rm -f /etc/netplan/99-static-ip.yaml
fi

# Hand off full network control to NetworkManager via Netplan.
NETPLAN_FILE="/etc/netplan/01-network-manager-all.yaml"
sudo bash -c "cat > $NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
sudo netplan apply
echo -e "${BLUE}[INFO] Switched network backend to NetworkManager.${RESET}"

# Give NetworkManager a moment to wake up after netplan apply.
sleep 5

# Clean up any old profiles that might conflict with ours.
echo -e "${BLUE}[INFO] Cleaning old connections...${RESET}"
sudo nmcli con delete "Lab-Connection" 2>/dev/null || true
sudo nmcli con delete "Hotspot-Fallback" 2>/dev/null || true
sudo nmcli con delete "preconfigured" 2>/dev/null || true

# Primary (Lab) connection with static IP and high autoconnect priority.
echo -e "${BLUE}[INFO] Creating Primary Connection: $TARGET_SSID ...${RESET}"
sudo nmcli con add type wifi ifname wlan0 con-name "Lab-Connection" ssid "$TARGET_SSID"
sudo nmcli con modify "Lab-Connection" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$TARGET_PASS"
sudo nmcli con modify "Lab-Connection" ipv4.method manual ipv4.addresses "$STATIC_IP/24" ipv4.gateway "$TARGET_GATEWAY" ipv4.dns "8.8.8.8,8.8.4.4"
# * Priority 100 means this will always be preferred over the hotspot.
sudo nmcli con modify "Lab-Connection" connection.autoconnect-priority 100

# Fallback hotspot, activates automatically when the lab Wi-Fi is unreachable.
HOTSPOT_SSID="Pioneer-Hotspot"
HOTSPOT_IP="10.42.0.1"
echo -e "${BLUE}[INFO] Creating Fallback Hotspot: $HOTSPOT_SSID ...${RESET}"
sudo nmcli con add type wifi ifname wlan0 con-name "Hotspot-Fallback" ssid "$HOTSPOT_SSID" mode ap
sudo nmcli con modify "Hotspot-Fallback" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "pioneer-robot"
sudo nmcli con modify "Hotspot-Fallback" ipv4.addresses "$HOTSPOT_IP/24" ipv4.method shared
# * Priority 10 keeps this firmly below the lab connection.
sudo nmcli con modify "Hotspot-Fallback" connection.autoconnect-priority 10

# Disable the "Wait for Network" service so the robot doesn't stall at boot
# if the lab Wi-Fi happens to be unavailable.
echo -e "${BLUE}[INFO] Disabling systemd-networkd-wait-online to speed up boot...${RESET}"
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

echo ""

# ----------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}[P2OS]: Installation Complete!${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo ""
echo -e "1. ${BOLD}Pioneer 3-DX only!${RESET}"
echo -e "   This installation does not include Gazebo simulation tools."
echo -e "   It is optimised for controlling the physical robot."
echo ""
echo -e "2. ${BOLD}USB Connection:${RESET}"
echo -e "   Ensure the robot is connected via a USB-Serial adapter."
echo -e "   Default port: /dev/ttyUSB0"
echo ""
echo -e "3. ${BOLD}Network Configuration:${RESET}"
echo -e "   - Priority Network: $TARGET_SSID (Static IP: $STATIC_IP)"
echo -e "   - Fallback Network: $HOTSPOT_SSID (Password: 'pioneer-robot')"
echo -e "   - Note: The static IP applies only to Wi-Fi. Ethernet still uses DHCP."
echo -e "   - ROS_DOMAIN_ID: $DOMAIN_ID"
echo ""
echo -e "4. ${BOLD}Reboot Required:${RESET}"
echo -e "   Please reboot to apply user permission and network changes."
echo ""