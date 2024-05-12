#!/bin/bash

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
    [ "$DEBUG" = "true" ] && \
      echo "[DEBUG] \"$ENVVAR\" doesn't have the prefix \"$PREFIX\""
  fi
done < <(env)

# Show server.properties in DEBUG mode
if [ "$DEBUG" = "true" ]; then
  echo "[DEBUG] Showing ${FILE}:"
  cat "$FILE"
fi

# Pre-create the screen log
touch screenlog.0

# Run server in screen (without attaching)
/usr/bin/screen -dmS minecraft -L \
  bash -c "
    sleep 0.5
    [ $DEBUG = true ] && echo '[DEBUG] Starting server'
    /usr/bin/java $JVM_OPTS -jar server.jar --nogui
  "

# Tail screen log to container stdout
[ "$DEBUG" = "true" ] && echo "[DEBUG] Tailing screenlog.0"
tail -f screenlog.0
