# p2os2 - Pioneer Robot Drivers for ROS2

[![Ubuntu 22.04](https://img.shields.io/badge/Ubuntu-22.04%20LTS-orange)](https://releases.ubuntu.com/22.04/)
[![ROS 2 Humble](https://img.shields.io/badge/ROS%202-Humble%20Hawksbill-blue)](https://docs.ros.org/en/humble/index.html)
[![Gazebo Harmonic](https://img.shields.io/badge/Gazebo-Harmonic-blueviolet)](https://gazebosim.org/docs/harmonic)

**🚧 Under Active Development & Migration 🚧**

**Please Note:** This repository contains the core drivers for the Pioneer robot family, refactored for ROS2 Humble. This is a migration of the original P2OS driver (originally written for Player/Stage). While the core chassis movement and sonar subsystems have been migrated, several subsystems (Laser, PTZ Camera, Arm/Gripper, Joystick) have **not been tested** as I do not have access to the specific hardware.

We are actively working on verifying these systems. Validated configurations currently exist for the **Pioneer 3-AT** (Physical) and **Pioneer 3-DX** (Simulation).

## Overview

P2OS is the essential driver interface for Pioneer robots utilizing the ARCOS controller. This update brings P2OS into the ROS2 ecosystem. My primary goal was to get the chassis moving and the sonars working. All SIP packets and related ROS2 messages pertaining to currently untested systems (Arm, Gripper, PTZ) were preserved in the migration logic, but remain unverified.

### ⚠️ Note on Sonar Readings (NaN)
Using an adaptation of standard ROS 2 sensor conventions (REP-0117), this driver outputs `NaN` (Not a Number) for invalid sonar readings. You will see `NaN` populated in the `/sonar` topic array under two conditions:
1. **Out of Range:** The object is further than the 5.0-meter maximum hardware range.
2. **Blind Spot:** The object is too close (under ~10cm) for the transducer to physically process the returning echo.

This intentional `NaN` handling ensures that downstream navigation stacks (like Nav2 or SLAM) gracefully ignore these readings rather than mapping them as false obstacles or clearing existing walls from the costmap.

## Packages

This repository currently includes the following core packages:

* **`p2os_driver`**: The core node. It controls the interface for the P2OS ARCOS controller via serial connection.
* **`p2os_bringup`**: Contains launch configurations migrated to ROS2 Python launch files for functionality that has been tested.
* **`p2os_urdf`**: Contains the robot description files to visualize the robot in RViz and spawn it in Gazebo.
* **`p2os_teleop`**: nodes to control the robot via joystick or keyboard.
* **`p2os_launch`**: **[Legacy]** ROS 1 launch files. Not usable in ROS2; kept purely as a reference for prior usage.

## Prerequisites

To use these packages, your system should meet the following requirements:

* **Operating System:** Ubuntu 22.04 LTS (Jammy Jellyfish)
* **ROS2 Version:** Humble Hawksbill (Desktop Install)
* **Gazebo Version:** Gazebo Harmonic (Tested and working)
* **Essential Tools:** `colcon`, `socat` (for firmware emulation)

## ⚡ Quick Installation (Automated)

We provide two automated scripts to simplify installation. Choose the one that fits your use case.

### Option A: Developer & Simulation Setup (Recommended for Development PC)
Use this script on your **personal computer**. It installs the full suite: ROS 2 Humble, Gazebo Harmonic, MobileSim (Legacy Emulator), and the p2os2 drivers.

```bash
# Clone the repository
git clone -b p3dx-enabled https://github.com/JPLDevMaster/p2os2.git
cd p2os2

# Run the full installer
chmod +x full_dev_installer.sh
./full_dev_installer.sh
```

### Option B: Robot Driver Setup (Physical Pioneer Only)
Use this script only on the Pioneer's onboard computer. It installs a lightweight version of the drivers without heavy simulation tools (Gazebo/MobileSim) to save resources.

```bash
# Clone the repository
git clone -b p3dx-enabled https://github.com/JPLDevMaster/p2os2.git
cd p2os2

# Run the robot-only installer
chmod +x p2os2_installer.sh
./p2os2_installer.sh
```

### What the Robot Installer Configures

When you run the `p2os2_installer.sh` script, it will prompt you for several configuration parameters to fully set up the onboard computer. Here is what you will be asked to provide:

| Parameter | Default | Description |
| :--- | :--- | :--- |
| **Workspace Path** | `~/pioneer_ws` | The directory where the ROS 2 workspace will be cloned and built. |
| **SWAP Size** | `2GB` | Creates a swap file to prevent out-of-memory errors during C++ compilation. Enter `0` to skip. |
| **Lab/Main Wi-Fi (SSID)** | *None (Required)* | The name of your primary local Wi-Fi network. |
| **Wi-Fi Password** | *None (Required)* | The WPA2 password for your primary network (minimum 8 characters). |
| **Static IP** | *None (Required)* | A unique static IP address for the robot on the primary network (e.g., `192.168.1.50`). |
| **Gateway IP** | *Auto-calculated* | The network router's IP address (usually ends in `.1`). |
| **ROS_DOMAIN_ID** | `0` | The ROS 2 domain ID (0-101) used to isolate this robot's ROS traffic from other devices. |

**📡 Automatic Failover Hotspot** To prevent the robot from becoming inaccessible if the primary Wi-Fi drops, the installer automatically configures a fallback network. If the robot cannot connect to the preset Wi-Fi on boot, it will broadcast its own hotspot so you can still SSH into it:
* **Network Name:** `Pioneer-Hotspot`
* **Password:** `pioneer-robot`
* **Robot IP Address:** `10.42.0.1`

## 🔧 Manual Installation (Reference)

If you prefer to install manually or customize your setup, follow these steps.

1. **Create a Colcon Workspace:**
```bash
mkdir -p ~/pioneer_ws/src
cd ~/pioneer_ws/src
```

2. **Clone the Repository:**
```bash
git clone https://github.com/JPLDevMaster/p2os2.git
cd p2os2
git checkout p3dx-enabled
```

3. **Build the Workspace:**
```bash
cd ~/pioneer_ws
colcon build --symlink-install
source install/setup.bash
```

---

## 🧪 Running the Simulation (Gazebo Harmonic)

A fully migrated simulation environment is available for the **Pioneer 3-DX**. The URDF has been updated to use modern `diff_drive` plugins compatible with Gazebo Harmonic, and legacy `p3d` plugins have been removed.

To launch the simulation:

```bash
ros2 launch p2os_urdf pioneer3dx_gz_launch.py
```

This will spawn the Pioneer 3-DX in Gazebo Harmonic with the necessary transforms and controller interfaces active.

---

## 🤖 Firmware Emulation Workflow (No Robot Required)

Since `p2os` acts as a low-level driver bridging ROS2 and the robot's microcontroller via a serial port, validation in pure simulation (Gazebo) is limited (as Gazebo simulates physics, not the specific ARCOS firmware protocol).

To validate the driver logic and ROS2 communication without physical access to a robot, we have established a firmware emulation workflow using **MobileSim**.

### 1. Install Prerequisites

You will need `socat` to create a virtual serial tunnel and **MobileSim** to emulate the hardware.

* **Install socat:**
```bash
sudo apt install socat
```


* **Install MobileSim:** Follow the installation guide [here](https://github.com/rnitin/pioneer-ros).

### 2. Launch MobileSim

Run MobileSim in "no map" mode to expose the TCP interface:

```bash
MobileSim -nomap
```

### 3. Create a Virtual Serial Tunnel

Because `p2os_driver` expects a serial port but MobileSim uses TCP, we use `socat` to bridge them. Run this in a new terminal:

```bash
socat -d -d pty,link=$HOME/ttyPioneer,raw,echo=0 tcp:localhost:8101
```

### 4. Launch the Driver

The launcher has been updated to accept a `port` argument. Launch the driver pointing to your virtual serial port (Note: launch this immediately after the bridge to avoid timeouts):

```bash
ros2 launch p2os_bringup p2os_driver_launch.py port:=$HOME/ttyPioneer
```

### 5. Verification

You can now verify that the driver is publishing standard topics (Battery, Sonar, Odometry, etc.) via `ros2 topic list`.

To test bidirectional communication, you can manually enable the motors and send a velocity command:

```bash
# Enable Motors.
ros2 topic pub --once /cmd_motor_state p2os_msgs/msg/MotorState "{state: 1}"

# Send Velocity Command (Move forward).
ros2 topic pub --rate 10 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.5}, angular: {z: 0.0}}"
```

---

## 🛠️ Real Robot Launch

Similarly to the emulation section, you may launch the driver using the following command:

```bash
ros2 launch p2os_bringup p2os_driver_launch.py
```

where the arguments and their default values are explained in the next table.

### Verification

You can now verify that the driver is publishing standard topics (Battery, Sonar, Odometry, etc.) via `ros2 topic list`.

To test bidirectional communication, you can manually enable the motors and send a velocity command:

```bash
# Enable Motors.
ros2 topic pub --once /cmd_motor_state p2os_msgs/msg/MotorState "{state: 1}"

# Send Velocity Command (Move forward).
ros2 topic pub --rate 10 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.5}, angular: {z: 0.0}}"
```

To start the Hokuyo driver (urg_node2) you just need to run the following command:

```bash
ros2 launch urg_node2 urg_node2.launch.py
```

and you may validate that the topic is being correctly published by running the command:

```bash
ros2 topic echo /scan
```

To visualize the sonar messages, follow the following steps:

1. Run the ```rviz2``` command.
2. In the Displays panel on the left, change the Fixed Frame to base_link (or another, given you understand the workings of TFs).
3. Click the Add button at the bottom left.
4. Select the "By topic" tab.
5. Scroll down to the ```/sonar_pointcloud``` topic and select the appropriate display type (PointCloud2).

If you eventually save a pre-configured `.rviz` file locally that already has these topics and frames set up, you can just boot rviz up with that file directly:

```bash
rviz2 -d {your_file_path}
```

---

## 🛠️ Launch Configuration Parameters

The `p2os_bringup` and `p2os_urdf` launch files are being refactored to support several arguments to configure the serial connection and simulation settings. 
The arguments will be added to the following table as soon as the workflow is tested with them.

| Parameter Name | Default Value | Description |
| --- | --- | --- |
| `port` | `/dev/ttyUSB0` | The serial port device to connect to (e.g., `/dev/ttyUSB0` for the real robot, `$HOME/ttyPioneer` for emulation). |
| `use_sonar` | `True` | Set to "true" for sonar usage and "false" for null messages. |
| `log_level` | `INFO` | Log level parameter. Set to "DEBUG" for more detailed logging. |

---

## Reporting Issues

Please report any bugs using the [GitHub Issues tab](https://github.com/pondersome/p2os2/issues).

If you successfully test this driver on a **Pioneer 3-DX** or verify the **ROS2 Player/Stage** migrations, please submit a Pull Request!
