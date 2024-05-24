FROM debian:stable-slim

ARG JAVA_RUNTIME
ARG JAVA_VERSION=latest
ENV DEBIAN_FRONTEND=noninteractive

# Install scripting dependencies
RUN apt-get update && \
    apt-get install -y curl git gpg jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Eclipse Adoptium DEB installer package
RUN set -eux && \
  # Download the Eclipse Adoptium GPG key
  curl -s https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | gpg --dearmor | tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null && \
  # Configure the Eclipse Adoptium APT repository
  VERSION_CODENAME="$(awk -F= '/^VERSION_CODENAME/{print $2}' /etc/os-release)" && \
  echo "deb https://packages.adoptium.net/artifactory/deb $VERSION_CODENAME main" \
    | tee /etc/apt/sources.list.d/adoptium.list

# Install Adoptium Temurin (OpenJDK/OpenJRE)
RUN set -eux && \
  # Grab latest LTS version if not specified
  if [ "$JAVA_VERSION" = "latest" ]; then \
    JAVA_VERSION="$( \
      curl -s https://api.adoptium.net/v3/info/available_releases \
        | jq '.most_recent_lts' \
    )"; \
  fi && \
  # Install OpenJDK if JAVA_RUNTIME is false
  case "$JAVA_RUNTIME" in \
    true) \
      JAVA_TYPE='jre' ;; \
    false) \
      JAVA_TYPE='jdk' ;; \
    *) \
      echo "ERROR: Invalid value for JAVA_RUNTIME. Set to 'true' or 'false'"; \
      exit 1 ;; \
  esac && \
  # Install the Temurin version
  apt-get update && \
  apt-get install -y "temurin-$JAVA_VERSION-$JAVA_TYPE" && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

# Create minecraft user for runtime
RUN if [ "$JAVA_RUNTIME" = "true" ]; then \
      groupadd -g 1000 minecraft && \
      useradd -m -u 1000 -g 1000 -d /app minecraft; \
    fi

# Install additional runtime dependencies
RUN if [ "$JAVA_RUNTIME" = "true" ]; then \
      apt-get update && \
      apt-get install -y procps screen strace && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/*; \
    fi
