from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node

def generate_launch_description():
    # Create the LaunchConfiguration variables to capture the values.
    port_config = LaunchConfiguration('port')
    use_sonar_config = LaunchConfiguration('use_sonar')
    log_level_config = LaunchConfiguration('log_level')

    return LaunchDescription([
        # Declare the argument so we can use 'port:=...' in the terminal.
        DeclareLaunchArgument(
            'port',
            default_value='/dev/ttyUSB0',
            description='Serial port for the p2os_driver'
        ),
        # Declare the argument to make use_sonar configurable (it was harcoded before).
        DeclareLaunchArgument(
            'use_sonar',
            default_value='True',
            description='Set to "true" for sonar usage and "false" for null messages.'
        ),
        # Declare the argument define the log level.
        DeclareLaunchArgument(
            'log_level',
            default_value='INFO',
            description='Log level parameter. Set to "DEBUG" for more detailed logging.'
        ),

        Node(
            package='p2os_driver',
            executable='p2os_driver',
            name='p2os_driver',
            remappings=[
                ('pose', 'odom')
            ],
            parameters=[
                {'use_sonar': use_sonar_config}, # Use the captured value.
                {'port': port_config}  # Use the captured value.
            ],
            arguments=['--ros-args', '--log-level', log_level_config] 
        ),            
    ])