#!/bin/bash
set -eu

# Set eula value in eula.txt
set_eula() {
  local EULA
  EULA="${1:-false}"
  EULAFILE="${EULAFILE:-/app/eula.txt}"
  sed -i.bak "s/^eula=.*\$/eula=${EULA:-false}/" "$EULAFILE"
  diff --unified=1 "${EULAFILE}.bak" "$EULAFILE" || true
  rm "${EULAFILE}.bak"
}

# Update server.properties using env
set_properties() {
  # Basic settings
  DEBUG="${DEBUG:-false}"
  PREFIX="${PREFIX:-SETTINGS_}"
  FILE="${FILE:-/app/server.properties}"

  # Update server.properties
  while IFS='=' read -r ENVVAR VALUE ; do
    if echo "$ENVVAR" | grep -q "^${PREFIX}.*$"; then
      KEY="${ENVVAR#"$PREFIX"}"
      if ! grep -q "^${KEY}=" "$FILE"; then
        echo "[WARN]: \"$KEY\" does not exist in $FILE and was not updated"
      else
        [ "$DEBUG" = "true" ] && echo "[DEBUG] Updating \"$KEY\" to \"$VALUE\""
        sed -i.bak "s/^${KEY}=.*/${KEY}=${VALUE}/" "$FILE"
        diff --unified=1 "${FILE}.bak" "$FILE"
        rm "${FILE}.bak"
      fi
    else
      if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG] \"$ENVVAR\" doesn't have the prefix \"$PREFIX\""
      fi
    fi
  done < <(env)

  # Show server.properties in DEBUG mode
  if [ "$DEBUG" = "true" ]; then
    echo "[DEBUG] Showing ${FILE}:"
    cat "$FILE"
  fi
}

# Check if the minecraft screen is still running
# shellcheck disable=SC2317
check_screen() {
  local SCREEN_NAME
  SCREEN_NAME="$1"
  if [ "$(screen -ls | grep -cE "[0-9]+\.$SCREEN_NAME")" -eq 1 ]; then
    return 0
  else
    return 1
  fi
}

# Find screen PID, strace it, and wait for it to exit
wait_on_screen() {
  local SCREEN_PID
  local SCREEN_NAME
  local STRACE_PID
  local TAIL_PID

  SCREEN_NAME="$1"

  # Get screen PID
  [ "$DEBUG" = "true" ] && screen -ls
  SCREEN_PID="$(
    screen -ls | grep -oE "[0-9]+\.$SCREEN_NAME" | cut -d. -f1
  )"

  # Check screen PID
  if ! kill -0 "$SCREEN_PID" 2>/dev/null; then
    echo "[ERROR] Cannot find \"$SCREEN_NAME\" screen (PID: \"$SCREEN_PID\")"
    exit 1
  fi

  # Output logs to stdout (touch in case slow to create)
  touch screenlog.0
  tail -f screenlog.0 &
  TAIL_PID="$!"

  # Wait for screen to exit
  strace -e exit -e signal=none -p "$SCREEN_PID" 2>/dev/null &
  STRACE_PID="$!"
  [ "$DEBUG" = "true" ] && ps aux
  wait "$STRACE_PID"
}

# Function to stop the server gracefully
# shellcheck disable=SC2317
stop_server() {
  local SCREEN_NAME
  SCREEN_NAME="$1"
  if check_screen "$SCREEN_NAME"; then
    # Run 'stop' inside screen and wait for the screen to exit
    /usr/bin/screen -p 0 -S "$SCREEN_NAME" -X eval 'stuff "stop"\015'
    wait "$STRACE_PID"

    # Stop tail -f to stdout
    if kill -0 "$TAIL_PID" 2>/dev/null; then
      kill "$TAIL_PID"
    fi

    # Check only this script is running (PID 1) and pgrep (2 PIDs total)
    PGREP_OUTPUT="$(pgrep .)"
    if ! [ "$(echo "$PGREP_OUTPUT" | wc -l)" -eq 2 ]; then
      echo "[WARN] Some processes might not have exited:"
      echo "$PGREP_OUTPUT"
      exit 1
    fi

    # Exit cleanly
    echo "[INFO] Server stopped gracefully"
    exit 0
  else
    echo "[ERROR]: Can't find which screen to use"
    screen -ls
    exit 1
  fi
}

# Start the Minecraft server
minecraft_server() {
  # Settings
  JVM_OPTS="${JVM_OPTS:--Xms1G -Xmx2G}"

  # Set EULA
  set_eula "${EULA:-false}"

  # Update server.properties using env
  set_properties

  # Set up a SIGTERM signal trap to stop the server
  trap 'stop_server minecraft' SIGTERM

  # Run server in screen (without attaching)
  echo "[INFO] Starting Minecraft server"
  /usr/bin/screen -dmS minecraft -L \
    bash -c "/usr/bin/java $JVM_OPTS -jar server.jar --nogui"

  # Wait for 'minecraft' screen PID to exit
  wait_on_screen minecraft
  exit 0
}

# Start the Velocity proxy Minecraft server
velocity_server() {
  # Settings
  JVM_OPTS="${JVM_OPTS:--Xms1G -Xmx2G}"

  # Set up a SIGTERM signal trap to stop the server
  trap 'stop_server velocity' SIGTERM

  # Start server
  echo "[INFO] Starting Velocity server"
  /usr/bin/screen -dmS velocity -L \
    bash -c "
      /usr/bin/java $JVM_OPTS -XX:+UseG1GC -XX:G1HeapRegionSize=4M \
        -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled \
        -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15 -jar velocity.jar
    "

  # Wait for 'velocity' screen PID to exit
  wait_on_screen velocity
}

# Enable debug mode
DEBUG="${DEBUG:-false}"
if [ "$DEBUG" = "true" ]; then
  echo "[DEBUG] Running entrypoint script at $(which entrypoint.sh)"
  sleep 0.2
  set -ux
fi

# Start Velocity proxy if VELOCITY='true' otherwise start a Minecraft server
VELOCITY="${VELOCITY:-false}"
if [ "$VELOCITY" = "true" ]; then
  # Start Velocity proxy
  velocity_server
else
  # Start Minecraft
  minecraft_server
fi

# Exit gracefully
exit 0
