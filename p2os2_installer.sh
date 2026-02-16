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
echo -e "3. ${BOLD}Reboot Required:${RESET}"
echo -e "   Please reboot to apply the user permission changes (dialout group)."
echo ""
