import launch
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, GroupAction, OpaqueFunction
from launch.conditions import IfCondition
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare

def generate_launch_description():
    # Declare launch arguments. All default to off except P2OS_Driver and
    # enableMotor, which we always want running on the real robot.
    launch_arguments = [
        DeclareLaunchArgument('HokuyoLaser',    default_value='0'),
        DeclareLaunchArgument('SICKLMSLaser',   default_value='0'),
        DeclareLaunchArgument('P2OS_Driver',    default_value='1'),
        DeclareLaunchArgument('KeyboardTeleop', default_value='0'),
        DeclareLaunchArgument('JoystickTeleop', default_value='0'),
        DeclareLaunchArgument('Transform',      default_value='0'),
        DeclareLaunchArgument('enableMotor',    default_value='1'),
    ]

    included_launches = [
        # P2OS driver node — the main robot controller.
        GroupAction(
            actions=[
                Node(
                    package='p2os_driver',
                    executable='p2os_driver',
                    name='p2os_driver',
                    parameters=[
                        {'use_sonar': True},
                        {'port': '/dev/ttyUSB0'}  # Verify this is the right port.
                    ]
                )
            ],
            condition=IfCondition(LaunchConfiguration('P2OS_Driver'))
        ),

        # Keyboard teleoperation.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        FindPackageShare('p2os_bringup'), '/launch/', 'teleop_keyboard_launch.py'
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('KeyboardTeleop'))
        ),

        # Joystick teleoperation.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        FindPackageShare('p2os_bringup'), '/launch/', 'teleop_joy_launch.py'
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('JoystickTeleop'))
        ),

        # Static TF from base_link to laser frame.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        FindPackageShare('p2os_bringup'), '/launch/', 'tf_base_link_to_laser_launch.py'
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('Transform'))
        ),

        # Hokuyo URG LiDAR node. Note: this uses urg_node2, not the old urg_node
        # package. The installer patches the launch file to use serial params.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        PathJoinSubstitution([
                            FindPackageShare('urg_node2'), 'launch', 'urg_node2.launch.py'
                        ])
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('HokuyoLaser'))
        ),

        # SICK LMS laser — not typically used on the P3-DX but kept for compatibility.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        FindPackageShare('p2os_bringup'), '/launch/', 'sicklms_launch.py'
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('SICKLMSLaser'))
        ),

        # Enable motors on startup.
        GroupAction(
            actions=[
                IncludeLaunchDescription(
                    PythonLaunchDescriptionSource([
                        PathJoinSubstitution([
                            FindPackageShare('p2os_bringup'), 'launch', 'enable_motors_launch.py'
                        ])
                    ])
                )
            ],
            condition=IfCondition(LaunchConfiguration('enableMotor'))
        ),

        # * The P3-DX is a 2-wheeled differential
        # * drive robot with completely different geometry than the 3-AT, using the wrong URDF
        # * breaks all TF transforms and the RViz2 model.
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource([
                PathJoinSubstitution([
                    FindPackageShare('p2os_urdf'), 'launch', 'pioneer3dx_urdf_launch.py'
                ])
            ])
        )
    ]

    return LaunchDescription(launch_arguments + included_launches)

if __name__ == '__main__':
    generate_launch_description()