#!/bin/bash

# Check if the minecraft screen is still running
check_screen() {
  if [ "$(screen -ls | grep -cE '[0-9]+\.minecraft')" -eq 1 ]; then
    return 0
  else
    return 1
  fi
}

# Function to stop the server gracefully
stop_server() {
  if check_screen; then
    # Run 'stop' inside screen and wait for the screen to exit
    /usr/bin/screen -p 0 -S minecraft -X eval 'stuff "stop"\015'
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

# Enable debug mode
DEBUG="${DEBUG:-false}"
if [ "$DEBUG" = "true" ]; then
  echo "[DEBUG] Running entrypoint script at $(which entrypoint.sh)"
  sleep 0.2
  set -ux
fi

# Settings
FILE="${FILE:-/app/server.properties}"
EULAFILE="${EULAFILE:-/app/eula.txt}"
PREFIX="${PREFIX:-SETTINGS_}"
JVM_OPTS="${JVM_OPTS:--Xms1G -Xmx2G}"

# Set EULA
sed -i.bak "s/^eula=.*\$/eula=${EULA:-false}/" "$EULAFILE"
diff --unified=1 "${EULAFILE}.bak" "$EULAFILE"
rm "${EULAFILE}.bak"

# Update server.properties using env
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

# Set up a SIGTERM signal trap to stop the server
trap 'stop_server' SIGTERM

# Run server in screen (without attaching)
echo "[INFO] Starting Minecraft server"
/usr/bin/screen -dmS minecraft -L \
  bash -c "/usr/bin/java $JVM_OPTS -jar server.jar --nogui"

# Get screen PID
[ "$DEBUG" = "true" ] && screen -ls
SCREEN_PID="$(
  screen -ls | grep -oE '[0-9]+\.minecraft' | cut -d. -f1
)"

# Check screen PID
if ! kill -0 "$SCREEN_PID" 2>/dev/null; then
  echo "[ERROR] Cannot find Minecraft screen (PID: \"$SCREEN_PID\")"
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
