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
echo -e "${BOLD}[P2OS Dev]: Starting Full ROS 2 Humble & Simulation Installer${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo ""

# ----------------------------------------------------------------------
# [0] User Configuration
# ----------------------------------------------------------------------
DEFAULT_WS=~/pioneer_ws
read -p "[P2OS Dev]: Enter the path for your workspace (Default: $DEFAULT_WS): " USER_WS_INPUT
WORKSPACE_DIR=${USER_WS_INPUT:-$DEFAULT_WS}

echo -e "[P2OS Dev]: Workspace will be created at: ${BOLD}$WORKSPACE_DIR${RESET}"
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

# Add necessary tools for Gazebo installation.
sudo apt-get update
sudo apt-get install curl lsb-release gnupg

echo ""

# ----------------------------------------------------------------------
# [2] Install ROS 2 Humble & Gazebo Harmonic
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 2] Installing ROS 2 Humble and Gazebo Harmonic...${RESET}"
sudo apt update

# Install ROS 2 Desktop (Includes RViz, demos, tutorials).
sudo apt install -y ros-humble-desktop

# Add Gazebo repository and install Gazebo Harmonic.
sudo curl https://packages.osrfoundation.org/gazebo.gpg --output /usr/share/keyrings/pkgs-osrf-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/pkgs-osrf-archive-keyring.gpg] https://packages.osrfoundation.org/gazebo/ubuntu-stable $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/gazebo-stable.list > /dev/null
sudo apt-get update
sudo apt-get install gz-harmonic

echo ""

# ----------------------------------------------------------------------
# [3] Install Build Tools & Emulation Dependencies
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 3] Installing Build Tools and 'socat'...${RESET}"

sudo apt install -y build-essential python3-colcon-common-extensions python3-rosdep2 python3-vcstool

# Install socat for the firmware emulation workflow.
sudo apt install -y socat

# Clean up legacy rosdep2 sources to prevent conflicts.
if [ -f /etc/ros/rosdep/sources.list.d/20-default.list ]; then
    echo -e "${BLUE}[INFO] Cleaning up legacy rosdep sources to prevent conflicts...${RESET}"
    sudo rm /etc/ros/rosdep/sources.list.d/20-default.list
fi

# Initialize rosdep.
sudo rosdep init
rosdep update

echo ""

# ----------------------------------------------------------------------
# [4] Install MobileSim (Legacy Emulator)
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 4] Installing MobileSim...${RESET}"

MOBILESIM_DEB="mobilesim_0.9.8+ubuntu16_amd64.deb"
DOWNLOAD_URL="https://web.archive.org/web/20181006012429/http://robots.mobilerobots.com/MobileSim/download/current/$MOBILESIM_DEB"

# Check if already installed.
if dpkg -l | grep -q mobilesim; then
    echo -e "${BLUE}[INFO] MobileSim is already installed. Skipping.${RESET}"
else
    echo -e "${BLUE}[INFO] Downloading MobileSim from archive...${RESET}"
    if [ ! -f "$MOBILESIM_DEB" ]; then
        wget -O "$MOBILESIM_DEB" "$DOWNLOAD_URL"
    fi

    echo -e "${BLUE}[INFO] Installing MobileSim package...${RESET}"
    # dpkg might fail due to dependencies, so we force install dependencies after.
    sudo dpkg -i "$MOBILESIM_DEB" || true
    echo -e "${BLUE}[INFO] Fixing any missing dependencies...${RESET}"
    sudo apt-get install -f -y
    
    # Cleanup.
    rm "$MOBILESIM_DEB"
    echo -e "${BLUE}[INFO] MobileSim installed successfully.${RESET}"
fi

echo ""

# ----------------------------------------------------------------------
# [5] Workspace Setup & Cloning Repos
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 5] Setting up Workspace and Cloning P2OS...${RESET}"

mkdir -p "$WORKSPACE_DIR/src"
cd "$WORKSPACE_DIR/src"

# Clone the repository.
if [ ! -d "p2os2" ]; then
    echo -e "${BLUE}[INFO] Cloning p2os2 repository...${RESET}"
    git clone -b p3dx-enabled https://github.com/JPLDevMaster/p2os2.git
else
    echo -e "${BLUE}[INFO] p2os2 repo already exists. Checking branch...${RESET}"
    cd p2os2
    git checkout p3dx-enabled
    git pull
    cd ..
fi

echo ""

# ----------------------------------------------------------------------
# [6] Build Workspace
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 6] Building Workspace...${RESET}"

cd "$WORKSPACE_DIR"

# Source ROS 2.
source /opt/ros/humble/setup.bash

# Install dependencies for the cloned repo.
echo -e "${BLUE}[INFO] Installing all dependencies (including simulation)...${RESET}"
rosdep install --from-paths src --ignore-src -r -y

# Build with symlinks.
colcon build --symlink-install

echo ""

# ----------------------------------------------------------------------
# [7] Bashrc Setup
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 7] Updating ~/.bashrc...${RESET}"

MARKER_START="# P2OS_DEV_SETUP_START"
MARKER_END="# P2OS_DEV_SETUP_END"

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
# [8] Permissions
# ----------------------------------------------------------------------
echo -e "${GREEN}[Step 8] Setting Permissions...${RESET}"

# Useful for creating virtual ports or accessing real USB devices.
sudo usermod -aG dialout $USER
echo -e "${BLUE}[INFO] User added to 'dialout' group.${RESET}"
echo ""

# ----------------------------------------------------------------------
# Final Summary
# ----------------------------------------------------------------------
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo -e "${BOLD}[P2OS Dev]: Installation Complete!${RESET}"
echo -e "${BLUE}----------------------------------------------------------------------${RESET}"
echo ""
echo -e "1. ${BOLD}Apply Changes:${RESET}"
echo -e "   Please ${GREEN}source ~/.bashrc${RESET} or open a new terminal."
echo ""
echo -e "2. ${BOLD}To run the Simulation (Gazebo Harmonic):${RESET}"
echo -e "   ${GREEN}ros2 launch p2os_urdf pioneer3dx_gz_launch.py${RESET}"
echo ""
echo -e "3. ${BOLD}To run Firmware Emulation (MobileSim):${RESET}"
echo -e "   Open 3 terminals:"
echo -e "   [T1] ${YELLOW}MobileSim -nomap${RESET}"
echo -e "   [T2] ${YELLOW}socat -d -d pty,link=\$HOME/ttyPioneer,raw,echo=0 tcp:localhost:8101${RESET}"
echo -e "   [T3] ${YELLOW}ros2 launch p2os_bringup p2os_driver_launch.py port:=\$HOME/ttyPioneer${RESET}"
echo ""
