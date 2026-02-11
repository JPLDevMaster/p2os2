import os
from launch import LaunchDescription
from launch.actions import IncludeLaunchDescription, SetEnvironmentVariable, DeclareLaunchArgument, OpaqueFunction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch_ros.actions import Node
from launch.substitutions import Command, FindExecutable, PathJoinSubstitution, LaunchConfiguration, PythonExpression
from launch_ros.substitutions import FindPackageShare
from launch_ros.parameter_descriptions import ParameterValue

def _log_gz_path(context, *args, **kwargs):

    # Read the launch configuration for the declared arg.
    gz_cfg = context.launch_configurations.get('GZ_SIM_RESOURCE_PATH', '')
    print(f'GZ_SIM_RESOURCE_PATH (launch config): {gz_cfg}')

    # Also print effective env var if set in the process environment.
    print(f'GZ_SIM_RESOURCE_PATH (env): {os.environ.get("GZ_SIM_RESOURCE_PATH", "")}')

def generate_launch_description():
    package_name = 'p2os_urdf'
    pkg_share = FindPackageShare(package=package_name)

    # Remove the final directory from the package_share path.
    gz_resource_path = PythonExpression(["'", pkg_share, "'", ".rstrip('/').rsplit('/', 1)[0]"])

    # Declare the launch argument for GZ_SIM_RESOURCE_PATH.
    declare_gz_sim_resource_path_arg = DeclareLaunchArgument(
        'GZ_SIM_RESOURCE_PATH',
        default_value=''
    )

    # Set the environment variable by concatenating the provided launch arg and the package share.
    set_gz_sim_resource_path = SetEnvironmentVariable(
        name='GZ_SIM_RESOURCE_PATH',
        value=[LaunchConfiguration('GZ_SIM_RESOURCE_PATH'), os.pathsep, gz_resource_path]
    )

    # Generate robot description using xacro (Command substitution).
    xacro_exe = FindExecutable(name='xacro')
    xacro_file = PathJoinSubstitution([pkg_share, 'defs', 'pioneer3dx.xacro'])
    robot_description_cmd = Command([xacro_exe, ' ', xacro_file])

    # Wrap the substitution in ParameterValue with value_type=str.
    robot_description_param = ParameterValue(robot_description_cmd, value_type=str)

    # Gazebo launch file (ros_gz_sim).
    gazebo_launch_file = PathJoinSubstitution([FindPackageShare('ros_gz_sim'), 'launch', 'gz_sim.launch.py'])

    # Node declarations.
    rsp_node = Node(
        package='robot_state_publisher',
        executable='robot_state_publisher',
        name='robot_state_publisher',
        output='screen',
        parameters=[{
            'robot_description': robot_description_param,
            'use_sim_time': True,
            'publish_frequency': 30.0,
            'tf_prefix': ''
        }]
    )

    publisher_node = Node(
        package='p2os_urdf',
        executable='p2os_publisher_3dx',
        name='p2os_publisher_3dx',
        output='screen',
        parameters=[{'use_sim_time': True}]
    )

    spawn_node = Node(
        package='ros_gz_sim',
        executable='create',
        name='spawn_pioneer',
        arguments=['-name', 'pioneer3dx', '-topic', 'robot_description', '-z', '0.051'],
        output='screen'
    )

    return LaunchDescription([
        declare_gz_sim_resource_path_arg,
        set_gz_sim_resource_path,
        OpaqueFunction(function=_log_gz_path),

        rsp_node,
        publisher_node,

        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(gazebo_launch_file),
            launch_arguments={'gz_args': ''}.items()
        ),

        spawn_node
    ])