#!/usr/bin/env bash

set -e

# ----------------------------------------------------------------------
# Helper Variables for Formatting
# ----------------------------------------------------------------------
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

# ----------------------------------------------------------------------
# [0] User Configuration
# ----------------------------------------------------------------------
DEFAULT_WS=~/pioneer_ws
read -p "[P2OS]: Enter the path for your workspace (Default: $DEFAULT_WS): " USER_WS_INPUT
WORKSPACE_DIR=${USER_WS_INPUT:-$DEFAULT_WS}

# SWAP Configuration.
DEFAULT_SWAP="2GB"
read -p "[P2OS]: Enter SWAP size (e.g., 500MB, 1GB, 4GB) or '0' to skip (Default: $DEFAULT_SWAP): " USER_SWAP_INPUT
SWAP_SIZE=${USER_SWAP_INPUT:-$DEFAULT_SWAP}

# Network Configuration.
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
    echo "" # Newline for hidden input.
    
    if [[ ${#TARGET_PASS} -lt 8 ]]; then
        echo -e "${RED}[ERROR] Wi-Fi password must be at least 8 characters long (WPA2 standard).${RESET}"
        # We clear the variable so the loop repeats.
        TARGET_PASS="" 
    fi
done

STATIC_IP=""
while [[ -z "$STATIC_IP" ]]; do
    echo -e "${BOLD}[P2OS]: UNIQUE Static IP is REQUIRED for this robot.${RESET}"
    read -p "[P2OS]: Enter the Static IP (e.g., 192.168.X.Y): " STATIC_IP
    
    if [[ -z "$STATIC_IP" ]]; then
        echo -e "${RED}[ERROR] Input cannot be empty. Please enter a valid IP address.${RESET}"
        echo ""
    fi
done

DEFAULT_GW=$(echo "$STATIC_IP" | cut -d'.' -f1-3).1
read -p "Enter the Lab Gateway IP (Default: $DEFAULT_GW): " USER_GW_INPUT
TARGET_GATEWAY=${USER_GW_INPUT:-$DEFAULT_GW}

echo ""
echo -e "[Config] Workspace:  ${BOLD}$WORKSPACE_DIR${RESET}"
echo -e "[Config] Swap Size:  ${BOLD}$SWAP_SIZE${RESET}"
echo -e "[Config] Wi-Fi SSID: ${BOLD}$TARGET_SSID${RESET}"
echo -e "[Config] Static IP:  ${BOLD}$STATIC_IP${RESET}"
echo -e "[Config] Gateway:    ${BOLD}$TARGET_GATEWAY${RESET}"
echo ""

echo -e "[P2OS]: Workspace will be created at: ${BOLD}$WORKSPACE_DIR${RESET}"
echo ""

# ----------------------------------------------------------------------
# [1] System Setup: Locale & Repositories
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 1] Configuring Locale and System Sources...${RESET}"

# Ensure Locale is UTF-8.
sudo apt update && sudo apt install -y locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8

# Enable Universe.
sudo apt install -y software-properties-common
sudo add-apt-repository universe -y

# Install the ros2-apt-source package that will configure ROS 2 repositories for the system.
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

# Install ROS 2 Base (Barebones, no GUI tools).
sudo apt install -y ros-humble-ros-base

echo ""

# ----------------------------------------------------------------------
# [3] Install Build Tools
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 3] Installing Build Tools...${RESET}"

# Install 'build-essential' to ensure C++ compilers are present
sudo apt install -y build-essential python3-colcon-common-extensions python3-rosdep python3-vcstool

# Initialize rosdep.
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

# Clone the repository.
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

echo ""

# ----------------------------------------------------------------------
# [5] Build Workspace
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 5] Building Workspace...${RESET}"

cd "$WORKSPACE_DIR"

# Source ROS 2 to get build tools.
source /opt/ros/humble/setup.bash

# Install dependencies, SKIPPING Gazebo/Simulation packages.
# This prevents installing heavy simulation tools on the physical robot.
echo -e "${BLUE}[INFO] Installing dependencies (Skipping Simulation tools)...${RESET}"
rosdep install --from-paths src --ignore-src -r -y \
  --skip-keys "gazebo_ros gz_plugin_vendor gz_sim_vendor ros_gz_bridge ros_gz_sim ros_gz_interfaces"

# --- NEW: Dynamic SWAP creation before build ---
if [[ "$SWAP_SIZE" == "0" ]]; then
    echo -e "${BLUE}[INFO] User selected 0. Removing any existing swap...${RESET}"
    if [ -f /swapfile ]; then
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi
else
    # If a swap file already exists, remove it so we can resize (in case the user chose a different size).
    if [ -f /swapfile ]; then
        echo -e "${BLUE}[INFO] Existing swap found. Removing it to apply new size ($SWAP_SIZE)...${RESET}"
        # Try to turn it off first (ignore errors if it was already off).
        sudo swapoff /swapfile 2>/dev/null || true
        sudo rm -f /swapfile
    fi

    # Create the fresh file with the requested size.
    echo -e "${BLUE}[INFO] Creating $SWAP_SIZE swap file...${RESET}"
    if sudo fallocate -l $SWAP_SIZE /swapfile; then
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo -e "${BLUE}[INFO] Swap created and enabled.${RESET}"
    else
        echo -e "${RED}[ERROR] Failed to create swap file (Disk full?).${RESET}"
    fi
fi

# Verify Swap status.
free -h
# -----------------------------------------------

# Build with symlinks.
colcon build

echo ""

# ----------------------------------------------------------------------
# [6] Bashrc Setup
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 6] Updating ~/.bashrc...${RESET}"

MARKER_START="# P2OS_SETUP_START"
MARKER_END="# P2OS_SETUP_END"

# Clean old block.
if grep -qF "$MARKER_START" ~/.bashrc; then
    sed -i.bak "/$MARKER_START/,/$MARKER_END/d" ~/.bashrc
fi

# Add new block.
echo "" >> ~/.bashrc
echo "$MARKER_START" >> ~/.bashrc
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
echo "source $WORKSPACE_DIR/install/local_setup.bash" >> ~/.bashrc
# --- NEW: Network reset alias ---
echo "alias reset_network='sudo nmcli con delete \"Lab-Connection\" && sudo nmcli con delete \"Hotspot-Fallback\" && echo \"Profiles deleted. Reverting to defaults.\"' " >> ~/.bashrc
# --------------------------------
echo "$MARKER_END" >> ~/.bashrc

echo -e "${BLUE}[INFO] Added workspace sourcing to ~/.bashrc${RESET}"
echo ""

# ----------------------------------------------------------------------
# [7] Permissions
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 7] Setting Serial Port Permissions...${RESET}"

# Ensure the user can access the serial port (ttyUSB0).
sudo usermod -aG dialout $USER
echo -e "${BLUE}[INFO] User added to 'dialout' group.${RESET}"

echo ""

# ----------------------------------------------------------------------
# [8] Configure Failover Network (NetworkManager)
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 8] Configuring Network Manager (Failover Mode)...${RESET}"

# Install NetworkManager.
sudo apt install -y network-manager

# Clean old conflicting configurations.
echo -e "${BLUE}[INFO] Checking for conflicting Netplan files...${RESET}"

if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    echo -e "${BLUE}[INFO] Removing conflicting file: 50-cloud-init.yaml${RESET}"
    sudo rm -f /etc/netplan/50-cloud-init.yaml
fi

if [ -f /etc/netplan/99-static-ip.yaml ]; then
    echo -e "${BLUE}[INFO] Removing conflicting file: 99-static-ip.yaml${RESET}"
    sudo rm -f /etc/netplan/99-static-ip.yaml
fi

# Tell Netplan to surrender control to NetworkManager.
NETPLAN_FILE="/etc/netplan/01-network-manager-all.yaml"
sudo bash -c "cat > $NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: NetworkManager
EOF
sudo netplan apply
echo -e "${BLUE}[INFO] Switched network backend to NetworkManager.${RESET}"

# Create Profiles using nmcli.
# Wait a moment for NM service to wake up.
sleep 5

# Clean up old connections that might conflict.
echo -e "${BLUE}[INFO] cleaning old connections...${RESET}"
sudo nmcli con delete "Lab-Connection" 2>/dev/null || true
sudo nmcli con delete "Hotspot-Fallback" 2>/dev/null || true
sudo nmcli con delete "preconfigured" 2>/dev/null || true

# Create PRIMARY (Lab) Connection.
echo -e "${BLUE}[INFO] Creating Primary Connection: $TARGET_SSID ...${RESET}"
sudo nmcli con add type wifi ifname wlan0 con-name "Lab-Connection" ssid "$TARGET_SSID"
sudo nmcli con modify "Lab-Connection" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$TARGET_PASS"
sudo nmcli con modify "Lab-Connection" ipv4.method manual ipv4.addresses "$STATIC_IP/24" ipv4.gateway "$TARGET_GATEWAY" ipv4.dns "8.8.8.8,8.8.4.4"
# Set High Priority (100).
sudo nmcli con modify "Lab-Connection" connection.autoconnect-priority 100

# Create FALLBACK (Hotspot) Connection.
HOTSPOT_SSID="Pioneer-Hotspot"
HOTSPOT_IP="10.42.0.1"
echo -e "${BLUE}[INFO] Creating Fallback Hotspot: $HOTSPOT_SSID ...${RESET}"
sudo nmcli con add type wifi ifname wlan0 con-name "Hotspot-Fallback" ssid "$HOTSPOT_SSID" mode ap
sudo nmcli con modify "Hotspot-Fallback" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "pioneer"
sudo nmcli con modify "Hotspot-Fallback" ipv4.addresses "$HOTSPOT_IP/24" ipv4.method shared
# Set Low Priority (10).
sudo nmcli con modify "Hotspot-Fallback" connection.autoconnect-priority 10

# Disable the "Wait for Network" service so the robot boots fast even without Wi-Fi.
echo -e "${BLUE}[INFO] Disabling systemd-networkd-wait-online to speed up boot...${RESET}"
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service

echo ""
# ----------------------------------------------------------------------

# ----------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}[P2OS]: Installation Complete!${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo ""
echo -e "1. ${BOLD}!PIONEER-USE ONLY!${RESET}"
echo -e "   This installation does not include Gazebo simulation tools."
echo -e "   It is optimized for controlling the physical robot."
echo ""
echo -e "2. ${BOLD}USB Connection:${RESET}"
echo -e "   Ensure your robot is connected via USB-Serial adapter."
echo -e "   Common port: /dev/ttyUSB0"
echo ""
echo -e "3. ${BOLD}Network Configuration:${RESET}"
echo -e "   - Priority Network: $TARGET_SSID (Static IP: $STATIC_IP)"
echo -e "   - Fallback Network: $HOTSPOT_SSID (Password: 'pioneer')"
echo -e "   - Note: The static IP is only for Wi-Fi. Ethernet will still use DHCP."
echo ""
echo -e "4. ${BOLD}Reboot Required:${RESET}"
echo -e "   Please reboot to apply user permission and network changes."
echo ""