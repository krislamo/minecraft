FROM debian:stable

ENV VERSION=1.20.1
ENV JVM_OPTS="-Xmx2G -Xms1G"
ENV DEBIAN_FRONTEND=noninteractive
ARG EULA=false

# Install dependencies
RUN apt-get update && \
    apt-get install -y curl default-jre jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Create minecraft user
RUN groupadd -g 1000 minecraft && \
    useradd -m -u 1000 -g 1000 -d /home/minecraft minecraft

# Create directory
RUN mkdir /app && \
    chown minecraft:minecraft /app

# Download and verify sha1sum for server.jar
WORKDIR /app
USER minecraft
RUN set -ux; \
  # Get server.jar based on $VERSION
  curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json \
  | jq -r --arg id "$VERSION" '.versions[] | select(.id == $id) | .url' | xargs curl -s \
  | jq -r '.downloads.server' | tee "/tmp/dl.json" | jq -r '.url' | xargs curl -s -o server.jar && \
  java -jar server.jar --initSettings --nogui && \
  sed -i "s/^eula=.*\$/eula=$EULA/" eula.txt && \
  # Get SHA1 hash of server.jar and compare
  SHA1="$(sha1sum server.jar | awk '{print $1}')" && \
  EXPECTED="$(jq -r .sha1 /tmp/dl.json)"; rm /tmp/dl.json && \
  if [ ! "$SHA1" = "$EXPECTED" ]; then \
    echo "[ERROR] SHA1=\"$SHA1\" expected \"$EXPECTED\""; \
    exit 1; \
  fi

EXPOSE 25565
CMD ["java", "-jar", "server.jar", "$JVM_OPTS", "--nogui"]
