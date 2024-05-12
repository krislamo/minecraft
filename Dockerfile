FROM debian:stable-slim

ARG VERSION=latest
ARG JAVA_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive

# Create minecraft user
RUN groupadd -g 1000 minecraft && \
    useradd -m -u 1000 -g 1000 -d /app minecraft

# Install scripting dependencies
RUN apt-get update && \
    apt-get install -y curl gpg jq screen && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Eclipse Adoptium DEB installer package
RUN set -ux && \
  # Download the Eclipse Adoptium GPG key
  curl -s https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null && \
  # Configure the Eclipse Adoptium apt repository
  VERSION_CODENAME="$(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release)" && \
  echo "deb https://packages.adoptium.net/artifactory/deb $VERSION_CODENAME main" \
    | tee /etc/apt/sources.list.d/adoptium.list

# Install Adoptium Temurin (OpenJDK Distribution)
RUN set -ux && \
  # Grab latest LTS version if not specified
  if [ "$JAVA_VERSION" = "latest" ]; then \
    JAVA_VERSION="$( \
      curl -s https://api.adoptium.net/v3/info/available_releases \
        | jq '.most_recent_lts' \
    )"; \
  fi && \
  # Install the Temurin version
  apt-get update && \
  apt-get install -y "temurin-${JAVA_VERSION}-jre" && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Download files and run as user
USER minecraft
WORKDIR /app

# Download and verify sha1sum for server.jar
RUN set -ux && \
  # Grab latest version if not specified
  if [ "$VERSION" = "latest" ]; then \
    VERSION="$( \
      curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json \
        | jq -r '.latest.release' \
    )"; \
  fi && \
  # Get server.jar based on $VERSION
  curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json \
    | jq -r --arg id "$VERSION" '.versions[] | select(.id == $id) | .url' \
    | xargs curl -s | jq -r '.downloads.server' | tee "/tmp/dl.json" \
    | jq -r '.url' | xargs curl -s -o server.jar && \
  # Get SHA1 hash of server.jar and compare
  SHA1="$(sha1sum server.jar | awk '{print $1}')" && \
  EXPECTED="$(jq -r .sha1 /tmp/dl.json)"; rm /tmp/dl.json && \
  if [ ! "$SHA1" = "$EXPECTED" ]; then \
    echo "[ERROR] SHA1=\"$SHA1\" expected \"$EXPECTED\""; \
    exit 1; \
  fi

# Generate initial settings
RUN java -jar server.jar --initSettings --nogui

# Back to root to copy the entrypoint in
USER root
WORKDIR /app

# Copy in entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Run app as minecraft user
USER minecraft
WORKDIR /app

# Expose port and run entrypoint script
EXPOSE 25565
ENTRYPOINT ["entrypoint.sh"]
