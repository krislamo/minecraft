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
        [ "$DEBUG" = "true" ] && echo "[DEBUG]: Updating \"$KEY\" to \"$VALUE\""
        sed -i.bak "s/^${KEY}=.*/${KEY}=${VALUE}/" "$FILE"
        diff --unified=1 "${FILE}.bak" "$FILE" || true
        rm "${FILE}.bak"
      fi
    else
      if [ "$DEBUG" = "true" ]; then
        echo "[DEBUG]: \"$ENVVAR\" doesn't have the prefix \"$PREFIX\""
      fi
    fi
  done < <(env)

  # Show server.properties in DEBUG mode
  if [ "$DEBUG" = "true" ]; then
    echo "[DEBUG]: Showing ${FILE}:"
    cat "$FILE"
  fi
}

# Set Velocity's forwarding.secret
set_forwarding_secret() {
  local WRITE_FILE
  local FILE_CONTENT
  WRITE_FILE=false

  # Check file is not empty
  if [ -s /app/forwarding.secret ]; then
    FILE_CONTENT="$(head -c 1025 /app/forwarding.secret)"
    # Check that FORWARDING_SECRET is blank
    if [ ! "${#FORWARDING_SECRET}" -gt 0 ]; then
      # Only the file was set, so FORWARDING_SECRET becomes the file
      FORWARDING_SECRET="$(head -c 1025 /app/forwarding.secret)"
    else
      if [ ! "$FORWARDING_SECRET" = "$FILE_CONTENT" ]; then
        # You should either bind mount a file in OR set a value
        echo "[ERROR]: FORWARDING_SECRET is set with an existing file"
        exit 1
      fi
    fi
  # If the file is zero, we make sure the variable isn't also zero
  elif [ "${#FORWARDING_SECRET}" -eq 0 ]; then
    echo "[ERROR]: You must set FORWARDING_SECRET or set a value in the file"
    exit 1
  else
    # File is zero, so we must write the variable out to the file
    WRITE_FILE=true
  fi

  # Check length
  if [ "${#FORWARDING_SECRET}" -lt 32 ]; then
    echo "[ERROR]: FORWARDING_SECRET needs to be at least 32 characters long"
    exit 1
  elif [ "${#FORWARDING_SECRET}" -gt 1024 ]; then
    echo "[ERROR]: FORWARDING_SECRET is >1024 bytes"
    exit 1
  fi

  # Add secret to file
  if [ "$WRITE_FILE" = "true" ]; then
    echo "$FORWARDING_SECRET" > /app/forwarding.secret
  fi

  # Unset sensitive value
  unset FORWARDING_SECRET
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

# Find Java PID, strace it, and wait for it to exit
wait_on_java() {
  local JAVA_PID
  local JAVA_EXIT

  # Debug mode
  [ "$DEBUG" = "true" ] && ps aux

  # Capture PID and test
  JAVA_PID="$(pgrep java)"
  if ! kill -0 "$SCREEN_PID" 2>/dev/null; then
    echo "[ERROR]: Cannot find running Java process (PID: \"$JAVA_PID\")"
    exit 1
  fi

  # strace Java PID and get return code
  JAVA_EXIT="$(strace -e trace=exit -p "$JAVA_PID" 2>&1 \
    | grep -oP '^\+\+\+ exited with \K[0-9]+')"

  # Delay if Java exits non-zero
  if [ ! "$JAVA_EXIT" = "0" ]; then
    echo "[ERROR]: Java exited with non-zero status"
    sleep "${EXIT_DELAY:-5}"
    exit "$JAVA_EXIT"
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

  # Debug mode
  [ "$DEBUG" = "true" ] && ps aux

  # Wait for screen to exit
  strace -e exit -e signal=none -p "$SCREEN_PID" 2>/dev/null &
  STRACE_PID="$!"

  # Wait on Java PID first
  wait_on_java

  # Wait if screen is somehow still running
  wait "$STRACE_PID"

  # Kill tail PID
  if kill -0 "$TAIL_PID" 2>/dev/null; then
    kill "$TAIL_PID"
  fi
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
      echo "[WARN]: Some processes might not have exited:"
      echo "$PGREP_OUTPUT"
      exit 1
    fi

    # Exit cleanly
    echo "[INFO]: Server stopped gracefully"
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

  # temp
  ls -al /app
  ls -al /app/config

  # Run server in screen (without attaching)
  echo "[INFO]: Starting Minecraft server"
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

  # Ensure there is a forwarding.secret
  set_forwarding_secret

  # Set up a SIGTERM signal trap to stop the server
  trap 'stop_server velocity' SIGTERM

  # Start server
  echo "[INFO]: Starting Velocity server"
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
  echo "[DEBUG]: Running entrypoint script at $(which entrypoint.sh)"
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
