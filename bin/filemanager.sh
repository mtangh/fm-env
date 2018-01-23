#!/bin/bash
# filemanager  This is the init script for starting up the filemanager
#
# chkconfig: - 88 38
# description: Starts and stops the filemanager daemon.
# processname: filemanager
# pidfile: /var/run/filemanager.pid

NAME="${0##*/}"

# Find the name of the script
NAME="${NAME:-filemanager.sh}"
BASE="${NAME%.*}"

# Script dir.
CDIR=$([ -n "${0%/*}" ] && cd "${0%/*}" 2>/dev/null; pwd)

# Real path and name
REALPATH="$(readlink ${0} 2>/dev/null || echo ${CDIR}/${NAME})"

# Real name and basename
REALNAME="${REALPATH##*/}"
REALBASE="${REALNAME%.*}"

# Script real dir.
REAL_DIR=$([ -n "${REALPATH}" ] && cd "${REALPATH}" 2>/dev/null; pwd)

# ISBOOT ?
unset ISBOOT
if [ "${NAME:0:1}" = "S" -o "${NAME:0:1}" = "K" ]
then
  NAME="${NAME:3}"
  ISBOOT=1
fi

# Source file.
for src_file in /etc/rc.d/init.d/functions /etc/sysconfig/filemanager
do
  [ -r "$src_file" ] && {
    . "$src_file"
  } || :
done 1>/dev/null 2>&1

# Get function listing for cross-distribution logic.
TYPESET=$(typeset -f |grep "declare")

# For SELinux we need to use 'runuser' not 'su'
if [ -x "/sbin/runuser" ]
then SU=runuser
else SU=su
fi

# filemanager command
FMAN_CMD="${FMAN_CMD:-}"

# Process user
FMAN_USR="${FMAN_USR:-nobody}"
FMAN_GRP="${FMAN_GRP:-nobody}"

# Default port
FMANPORT=8888

# Directories
FMANROOT="${FMANROOT:-}"
FMANBASE="${FMANBASE:-}"
FMETCDIR="${FMETCDIR:-}"
FMLOGDIR="${FMLOGDIR:-}"

# filemanager command
[ -n "$FMAN_CMD" -a -x "$FMAN_CMD" ] || {
  # Finding under the script dir.
  for dir_path in "${RDIR}" "${CDIR}"
  do
    [ -x "${dir_path}/${BASE}" ] ||
      continue
    FMAN_CMD="${dir_path}/${BASE}" &&
    break
  done
  # Validate the found command
  [ -n "$FMAN_CMD" -a -x "$FMAN_CMD" ] ||
  FMAN_CMD=$(type -P ${BASE} 2>/dev/null)
} 1>/dev/null 2>&1
[ -n "$FMAN_CMD" -a -x "$FMAN_CMD" ] || {
  echo "$NAME: '${BASE}' command not found." 1>&2
  exit 128
}

# filemanager root dir.
[ -n "${FMANROOT}" -a -d "${FMANROOT}" ] || {
  FMANROOT=$([ -n "${FMAN_CMD%/bin*}" ] && cd "${FMAN_CMD%/bin*}"; pwd)
  FMANROOT=$([ -n "${FMANROOT%/*}" ] && cd "${FMANROOT%/bin*}"; pwd)
  [ -n "${FMANROOT}" -a -d "${FMANROOT}" ] ||
    FMANROOT="/var/${BASE}"
  echo "$FMANROOT" |egrep '^/(usr$|$)' &&
    FMANROOT=""
} 1>/dev/null 2>&1

# filemanager dirs.
[ -n "${FMANBASE}" -a -d "${FMANBASE}" ] || {
  if [ -n "${FMANROOT}" ]
  then FMANBASE="${FMANROOT}/data"
  else FMANBASE="/var/filemanager/data"
  fi
} 1>/dev/null 2>&1
[ -n "${FMETCDIR}" -a -d "${FMETCDIR}" ] || {
  if [ -n "${FMANROOT}" ]
  then FMETCDIR="${FMANROOT}/etc"
  else FMETCDIR="/etc/filemanager"
  fi
} 1>/dev/null 2>&1
[ -n "${FMLOGDIR}" -a -d "${FMLOGDIR}" ] || {
  if [ -n "${FMANROOT}" ]
  then FMLOGDIR="${FMANROOT}/log"
  else FMLOGDIR="/var/log/filemanager"
  fi
} 1>/dev/null 2>&1

# initialize result
script_result=0

##
# functions
##

start() {

  # Init directories
  for fman_dir in "$FMETCDIR" "$FMETCDIR/db" "$FMLOGDIR"
  do
    [ -n "${fman_dir}" ] || {
      continue
    }
    [ -d "${fman_dir}" ] || {
      mkdir -p "${fman_dir}" &&
      chown "${FMAN_USR}:${FMAN_GRP}" "${fman_dir}" &&
      chmod 3775 "${fman_dir}"
    } 1>/dev/null 2>&1
  done || :

  # Log files
  [ -d "${FMLOGDIR}" ] && {
    chown -R "${FMAN_USR}:${FMAN_GRP}" "${FMLOGDIR}"/* &&
    chmod 0644 "${FMLOGDIR}"/*
  } 1>/dev/null 2>&1 || :

  # Instances
  if [ $# -le 0 ]
  then
    fm_files=$(ls -1 "${FMETCDIR}"/*.yml)
    fm_files="${fm_files:-*}"
  else
    fm_files="$@"
  fi 1>/dev/null

  # Lookup config files
  for fmconfig in ${fm_files}
  do
    filename=""
    instance=""
    fm_fbase=""
    if [ "$fmconfig" = "*" ]
    then
      filename="*"
      instance="*"
      fm_fbase="${BASE}"
    elif [ -r "${fmconfig}" ]
    then
      filename="${fmconfig##*/}"
      instance="${filename%.*}"
      fm_fbase="${BASE}-${instance}"
    fi
    [ -n "${filename}" ] || continue
    [ -n "${instance}" ] || continue
    fmanopts=""
    [ "$fmconfig" = "*" ] &&
    fmanopts="${fmanopts}${fmanopts:+ }-b ${FMANBASE}"
    [ "$fmconfig" = "*" ] ||
    fmanopts="${fmanopts}${fmanopts:+ }-c ${fmconfig}"
    fmanopts="${fmanopts}${fmanopts:+ }-d ${FMETCDIR}/${fm_fbase}.db"
    fmanopts="${fmanopts}${fmanopts:+ }-l ${FMLOGDIR}/${fm_fbase}.log"
    echo -n "Starting ${fm_fbase}: "
    [ -e "${FMAN_CMD}" ] && {
      $SU -m "$FMAN_USR" -c "cd ${FMANROOT:-/}; $FMAN_CMD $fmanopts &" </dev/null
    } 1>>${FMLOGDIR}/${BASE}.log 2>&1
    if [ $? -eq 0 ]
    then echo_success
    else echo_failure
    fi
    echo
  done

  # Number of config files
  fmconfig_count=$(ls -1 "${FMETCDIR}"/*.yml 2>/dev/null |wc -l)
  # Number of filemanager instances
  instance_count=$(pgrep "${FMAN_CMD##*/}" 2>/dev/null |wc -l)

  # Check
  if [ $fmconfig_count -gt 0 ] 2>/dev/null &&
     [ $fmconfig_count -eq $instance_count ] 2>/dev/null
  then script_result=0
  else script_result=1
  fi

  # End
  return $script_result
}

stop() {

  # Stopping filemanager instances
  if [ $# -le 0 ]
  then
    echo -n "Stopping ${BASE}: "
    pgrep "${FMAN_CMD##*/}" 1>/dev/null 2>&1 && {
      killall "${FMAN_CMD##*/}"
    } 1>/dev/null 2>&1
    script_result=$?
    if [ $script_result -eq 0 ]
    then echo_success
    else echo_failure
    fi
    echo
  else
    for instance in "$@"
    do
      echo -n "Stopping ${BASE}/${instance}: "
      : && {
        fman_pid=$(_fman_instance_pid "${instance}")
        [ -n "$fman_pid" ] && {
          kill "${fman_pid}"
        }
      } 1>/dev/null 2>&1
      script_result=$?
      if [ $script_result -eq 0 ]
      then echo_success
      else echo_failure
      fi
      echo
    done
  fi

  # End
  return  $script_result
}

restart() {
  stop "$@"
  start "$@"
}

status() {

  if [ $# -le 0 ]
  then
    if [ -n "$(pgrep ${FMAN_CMD##*/} |head -n 1)" ]
    then
      echo "${BASE} is running ..."
      script_result=0
    else
      echo "${BASE} is stopped."
      script_result=3
    fi
  else
    script_result=0
    for instance in "$@"
    do
      fman_pid=$(_fman_instance_pid "${instance}")
      if [ -n "$fman_pid" ]
      then
        echo "${BASE}-${instance} is running (pid=$fman_pid)"
      else
        echo "${BASE}-${instance} is stopped."
        script_result=3
      fi
    done
  fi

  # End
  return $script_result
}

condstart() {
  status "$@" 1>/dev/null 2>&1 || {
    start "$@"
  }
  return $script_result
}

condstop() {
  status "$@" 1>/dev/null 2>&1 && {
    stop "$@"
  } || :
  return $script_result
}

condrestart() {
  if status "$@" 1>/dev/null 2>&1
  then restart "$@"
  else start "$@"
  fi
  return $script_result
}

config() {
  cat <<_EOF_
NAME=$NAME
BASE=$BASE
CDIR=$CDIR

REALPATH=$REALPATH
REALNAME=$REALNAME
REALBASE=$REALBASE
REAL_DIR=$REAL_DIR

FMAN_CMD=$FMAN_CMD

FMAN_USR=$FMAN_USR
FMAN_GRP=$FMAN_GRP

FMANPORT=$FMANPORT

FMANROOT=$FMANROOT
FMANBASE=$FMANBASE
FMETCDIR=$FMETCDIR
FMLOGDIR=$FMLOGDIR

_EOF_

  ls -1 ${FMETCDIR}/*.yml 2>/dev/null

  return $script_result
}

_fman_instance_pid() {
  [ -r "${FMETCDIR}/${$1}.yml" ] && {
    pgrep -afl "${FMAN_CMD}" |
    egrep "${FMETCDIR}/${1}.yml" |
    awk '{print($1);}'
  }
  return $?
}

[ -z "$(declare -F 'echo_success' 'echo_failure' 2>/dev/null)" ] || {
  echo_success() {
    printf " OK."
  }
  echo_failure() {
    printf " NG."
  }
}

# Axction
_ACTION_="$1"; shift

# See how we were called.
case "${_ACTION_}" in
start|stop|restart|status|reload)
  ${_ACTION_} "$@"
  ;;
condrestart|condstart|condstop)
  ${_ACTION_} "$@"
  ;;
config)
  ${_ACTION_}
  ;;
*)
  echo "Usage: $BASE {start|stop|restart|status|condstart|condstop|condrestart} [instance...]"
  script_result=1
  ;;
esac

# End
exit $script_result
