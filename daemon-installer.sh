#!/bin/bash

function main {

  # set default values and configuration
  SELF_PATH="$(readlink -f "$0")"
  SELF_NAME="$(basename "$SELF_PATH")"
  SHOW_HELP=false

  # parse arguments
  OPTIONS_PARSED=$(getopt \
    --options 'hu:n:c:d:l:p:' \
    --longoptions 'help,username:,daemon-name:,command:,working-dir:,log-file:,pid-file:' \
    --name "$SELF_NAME" \
    -- "$@"
  )

  # replace arguments
  eval set -- "$OPTIONS_PARSED"

  # apply arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        SHOW_HELP=true
        shift 1
        ;;
      -u|--username)
        USERNAME2="$2"
        shift 2
        ;;
      -n|--daemon-name)
        DAEMON_NAME="$2"
        shift 2
        ;;
      -c|--command)
        COMMAND="$2"
        shift 2
        ;;
      -d|--working-dir)
        WORKING_DIR="$2"
        shift 2
        ;;
      -l|--log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      -p|--pid-file)
        PID_FILE="$2"
        shift 2
        ;;
      --)
        shift 1
        break
        ;;
      *)
        break
        ;;
    esac
  done

  # either print the help text or process task
  if "$SHOW_HELP"; then

    # show help text
    show_help

  else

    # check if there is a unassigned argument to interpret it as task
    if [[ $# -eq 0 ]]; then

      echo "$SELF_NAME: require a task to continue" >&2
      exit 1

    fi

    # assign the task
    TASK="$1"
    shift 1

    # check if there is no unassigned argument left
    if [[ $# -ne 0 ]]; then

      echo "$SELF_NAME: cannot handle unassigned arguments: $*" >&2
      exit 1

    fi

    # select task
    case "$TASK" in
      install)
        task_install_daemon
        ;;
      uninstall)
        task_uninstall_daemon
        ;;
      *)
        echo "$SELF_NAME: require a valid task" >&2
        exit 1
        ;;
    esac

  fi
}

function check_root_privileges {

  if [[ $EUID -ne 0 ]]; then

    echo "$SELF_NAME: require root privileges" >&2
    exit 1

  fi
}

function validate_username {

  if [[ -z "$USERNAME2" ]]; then

    USERNAME2="$(logname)"

  else

    if ! getent passwd "$USERNAME2" > /dev/null; then

      echo "$SELF_NAME: the user does not exist" >&2
      exit 1

    fi

  fi
}

function validate_daemon_name {

  if [[ -z "$DAEMON_NAME" ]] || $1 && ! echo "$DAEMON_NAME" | grep -qE '^[a-z][_a-z0-9]*$'; then

    echo "$SELF_NAME: require valid daemon name" >&2
    exit 1

  fi

  DAEMON_FILE="/etc/init.d/$DAEMON_NAME"
}

function validate_working_dir {

  if [[ ! -d "$WORKING_DIR" ]]; then

    echo "$SELF_NAME: path to working directory does not exist" >&2
    exit 1

  fi

  WORKING_DIR="$(realpath "$WORKING_DIR")"
}

function validate_log_file {

  if [[ -z "$LOG_FILE" ]]; then

    LOG_FILE="/dev/null"

  else

    if [[ ! -d "$(dirname "$(realpath "$LOG_FILE")")" ]]; then

      echo "$SELF_NAME: path to directory of log file does not exist" >&2
      exit 1

    fi

  fi

  LOG_FILE="$(realpath "$LOG_FILE")"
}

function validate_pid_file {

  if [[ -z "$PID_FILE" ]]; then

    PID_FILE="$WORKING_DIR/application.pid"

  else

    if [[ ! -d "$(dirname "$(realpath "$PID_FILE")")" ]]; then

      echo "$SELF_NAME: path to directory of PID file does not exist" >&2
      exit 1

    fi

  fi

  PID_FILE="$(realpath "$PID_FILE")"
}

function task_install_daemon {

  check_root_privileges
  validate_username
  validate_daemon_name true
  validate_working_dir
  validate_log_file
  validate_pid_file

  echo '#!/bin/bash' > "$DAEMON_FILE"
  echo '### BEGIN INIT INFO' >> "$DAEMON_FILE"
  echo "# Provides:          $DAEMON_NAME" >> "$DAEMON_FILE"
  echo '# Required-Start:    $network $named $remote_fs $time $syslog' >> "$DAEMON_FILE"
  echo '# Required-Stop:     $network $named $remote_fs $time $syslog' >> "$DAEMON_FILE"
  echo '# Default-Start:     2 3 4 5' >> "$DAEMON_FILE"
  echo '# Default-Stop:      0 1 6' >> "$DAEMON_FILE"
  echo '### END INIT INFO' >> "$DAEMON_FILE"
  echo '' >> "$DAEMON_FILE"
  echo "USERNAME2=\"$USERNAME2\"" >> "$DAEMON_FILE"
  echo "DAEMON_NAME=\"$DAEMON_NAME\"" >> "$DAEMON_FILE"
  echo "COMMAND=\"$COMMAND\"" >> "$DAEMON_FILE"
  echo "WORKING_DIR=\"$WORKING_DIR\"" >> "$DAEMON_FILE"
  echo "PID_FILE=\"$PID_FILE\"" >> "$DAEMON_FILE"
  echo "LOG_FILE=\"$LOG_FILE\"" >> "$DAEMON_FILE"

  cat >> "$DAEMON_FILE" << 'EOF'

function start {

  start-stop-daemon \
    --start \
    --background \
    --chdir "$WORKING_DIR" \
    --chuid "$USERNAME2" \
    --pidfile "$PID_FILE" \
    --exec "/bin/bash" \
    -- -c "$COMMAND &> \"$LOG_FILE\""
}

function stop {

  start-stop-daemon \
    --stop \
    --pidfile "$PID_FILE"
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    stop
    start
    ;;
  *)
    echo "Usage: $0 {start|stop|restart}"
esac

EOF

  chmod +x "$DAEMON_FILE"
  update-rc.d "$DAEMON_NAME" defaults
}

function task_uninstall_daemon {

  check_root_privileges
  validate_daemon_name false

  service "$DAEMON_NAME" stop

  update-rc.d -f "$DAEMON_NAME" remove
  rm -f "$DAEMON_FILE"
}

function show_help {

  echo "1) Usage: $SELF_NAME install"
  echo "   ( -u | --username    ) <username>"
  echo "   ( -n | --daemon-name ) <daemon to be installed>"
  echo "   ( -c | --command     ) <command to be executed>"
  echo "   ( -d | --working-dir ) <working directory>"
  echo "   ( -l | --log-file    ) <destination for stdout and stderr>"
  echo "   ( -p | --pid-file    ) <PID file to be created by daemon>"
  echo ""
  echo "2) Usage: $SELF_NAME uninstall"
  echo "   ( -n | --daemon-name ) <daemon to be uninstalled>"
  echo ""
  echo "3) Show this text: $SELF_NAME ( -h | --help )"
  echo ""
}

main "$@"
exit 0
