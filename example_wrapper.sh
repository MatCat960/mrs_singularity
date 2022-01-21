#!/bin/bash

set -e

trap 'last_command=$current_command; current_command=$BASH_COMMAND' DEBUG
trap 'echo "$0: \"${last_command}\" command failed with exit code $?"' ERR

## | ------------------- configure the paths ------------------ |

# Change these when moving the script and the folders around

# get the path to the repository
REPO_PATH=`dirname "$0"`
REPO_PATH=`( cd "$REPO_PATH" && pwd )`

IMAGES_PATH="$REPO_PATH/images"
OVERLAYS_PATH="$REPO_PATH/overlays"
MOUNT_PATH="$REPO_PATH/mount"

## | ----------------------- user config ---------------------- |

# use <file>.sif for normal container
# use <folder>/ for sandbox container
CONTAINER_NAME="mrs_uav_system.sif"
OVERLAY_NAME="mrs_uav_system.img"

CONTAINED=true # do NOT mount host's $HOME
CLEAN_ENV=true # clean environment before runnning container

# mutually exclusive
OVERLAY=false  # load persistant overlay (initialize it with ./create_fs_overlay.sh)
WRITABLE=false # run as --writable (works with --sandbox containers)

# definy what should be mounted from the host to the container
# [TYPE], [SOURCE (host)], [DESTINATION (container)]
MOUNTS=(
  # mount the custom user workspace into the container
  "type=bind" "$REPO_PATH/user_ros_workspace" "$HOME/user_ros_workspace"

  # mount the MRS shell additions into the container, DO NOT MODIFY
  "type=bind" "$MOUNT_PATH" "/opt/mrs/host"
)

# not supposed to be changed by a normal user
DEBUG=false           # print stuff
KEEP_ROOT_PRIVS=false # let root keep privileges in the container
FAKEROOT=false        # run as superuser
DETACH_TMP=true       # do NOT mount host's /tmp

## | --------------------- user config end -------------------- |

if [ -z "$1" ]; then
  ACTION="run"
else
  ACTION=${1}
fi

CONTAINER_PATH=$IMAGES_PATH/$CONTAINER_NAME

if $OVERLAY; then

  if [ ! -e $OVERLAYS_PATH/$OVERLAY_NAME ]; then
    echo "Overlay file does not exist, initialize it with the 'create_fs_overlay.sh' script"
    exit 1
  fi

  OVERLAY_ARG="-o $OVERLAYS_PATH/$OVERLAY_NAME"
  $DEBUG && echo "Debug: using overlay"
else
  OVERLAY_ARG=""
fi

if $CONTAINED; then
  CONTAINED_ARG="-c"
  $DEBUG && echo "Debug: running as contained"
else
  CONTAINED_ARG=""
fi

if $WRITABLE; then
  WRITABLE_ARG="--writable"
  $DEBUG && echo "Debug: running as writable"
else
  WRITABLE_ARG=""
fi

if $KEEP_ROOT_PRIVS; then
  KEEP_ROOT_PRIVS_ARG="--keep-privs"
  $DEBUG && echo "Debug: keep root privs"
else
  KEEP_ROOT_PRIVS_ARG=""
fi

if $FAKEROOT; then
  FAKE_ROOT_ARG="--fakeroot"
  $DEBUG && echo "Debug: fake root"
else
  FAKE_ROOT_ARG=""
fi

if $CLEAN_ENV; then
  CLEAN_ENV_ARG="-e"
  $DEBUG && echo "Debug: clean env"
else
  CLEAN_ENV_ARG=""
fi

NVIDIA_COUNT=$( lspci | grep -i -e "vga.*nvidia" | wc -l )

if [ "$NVIDIA_COUNT" -ge "1" ]; then
  NVIDIA_ARG="--nv"
  $DEBUG && echo "Debug: using nvidia"
else
  NVIDIA_ARG=""
fi

if $DETACH_TMP; then
  TMP_PATH="/tmp/singularity_tmp"
  DETACH_TMP_ARG="--bind $TMP_PATH:/tmp"
  $DEBUG && echo "Debug: detaching tmp from the host"
else
  DETACH_TMP_ARG=""
fi

if $DEBUG; then
  EXEC_CMD="echo"
else
  EXEC_CMD="eval"
fi

MOUNT_ARG=""
if ! $WRITABLE; then

  # prepare the mounting points, resolve the full paths
  for ((i=0; i < ${#MOUNTS[*]}; i++));
  do
    ((i%3==0)) && TYPE[$i/3]="${MOUNTS[$i]}"
    ((i%3==1)) && SOURCE[$i/3]=$( realpath -e "${MOUNTS[$i]}" )
    ((i%3==2)) && DESTINATION[$i/3]=$( realpath -m "${MOUNTS[$i]}" )
  done

  for ((i=0; i < ${#TYPE[*]}; i++)); do
    MOUNT_ARG="$MOUNT_ARG --mount ${TYPE[$i]},source=${SOURCE[$i]},destination=${DESTINATION[$i]}"
  done
fi

if [[ "$ACTION" == "run" ]]; then
  [ ! -z "$@" ] && shift
  CMD="$@"
elif [[ $ACTION == "exec" ]]; then
  shift
  CMD="'/bin/bash -c \"${@}\"'"
elif [[ $ACTION == "shell" ]]; then
  CMD=""
else
  echo "Action is missing"
  exit 1
fi

# create tmp folder for singularity in host's tmp
[ ! -e /tmp/singularity_tmp ] && mkdir -p /tmp/singularity_tmp

# this will make the singularity to "export DISPLAY=:0"
export SINGULARITYENV_DISPLAY=:0

$EXEC_CMD singularity $ACTION \
  $NVIDIA_ARG \
  $OVERLAY_ARG \
  $DETACH_TMP_ARG \
  $CONTAINED_ARG \
  $WRITABLE_ARG \
  $CLEAN_ENV_ARG \
  $FAKE_ROOT_ARG \
  $KEEP_ROOT_PRIVS_ARG \
  $MOUNT_ARG \
  $CONTAINER_PATH \
  $CMD