FROM debian:stable

ENV DEBIAN_FRONTEND=noninteractive
ENV VERSION=1.20.1
ENV JVM_OPTS="-Xmx2G -Xms1G"
ENV EULA=false

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
RUN curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json \
  | jq -r --arg id "$VERSION" '.versions[] | select(.id == $id) | .url' | xargs curl -s \
  | jq -r '.downloads.server' | tee "/tmp/dl.json" | jq -r '.url' | xargs curl -s -o server.jar \
  && sha1sum server.jar | awk '{print $1}' | xargs -I{} sh -c '[ "{}" = "$(jq -r .sha1 /tmp/dl.json)" ] && \
  (echo "Checksum matches" && rm /tmp/dl.json) || (echo "Checksum failed" && exit 1)' \
  && chown minecraft:minecraft server.jar

USER minecraft
EXPOSE 25565

# temp
RUN echo 'eula=true' > eula.txt

CMD ["java", "-jar", "server.jar", "nogui"]
