from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

def generate_launch_description():
    # Create the LaunchConfiguration variable to capture the value.
    port_config = LaunchConfiguration('port')

    return LaunchDescription([
        # Declare the argument so we can use 'port:=...' in the terminal.
        DeclareLaunchArgument(
            'port',
            default_value='/dev/ttyUSB0',
            description='Serial port for the p2os_driver'
        ),

        Node(
            package='p2os_driver',
            executable='p2os_driver',
            name='p2os_driver',
            remappings=[
                ('pose', 'odom')
            ],
            parameters=[
                {'use_sonar': False},
                {'port': port_config}  # Use the captured value.
            ],
            arguments=['--ros-args', '--log-level', 'INFO']
        ),            
    ])