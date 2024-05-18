DOCKER_COMPOSE_BUILD = docker compose -f docker-compose.build.yml build
DOCKER_COMPOSE_UP = docker compose up -d

PRUNE_IMAGES = \
	localhost/minecraft:latest \
	localhost/minecraft:latest-spigot \
	localhost/minecraft:latest-craftbukkit \
	localhost/minecraft-jre:latest \
	localhost/minecraft-jdk:latest

.PHONY: all clean craftbukkit default install jdk jre spigot vanilla
default: vanilla
all: vanilla spigot craftbukkit

jre:
	$(DOCKER_COMPOSE_BUILD) minecraft-jre

jdk:
	$(DOCKER_COMPOSE_BUILD) minecraft-jdk

vanilla: jre
	$(DOCKER_COMPOSE_BUILD) minecraft-vanilla

spigot: jre jdk
	$(DOCKER_COMPOSE_BUILD) minecraft-spigot

craftbukkit: jre jdk
	$(DOCKER_COMPOSE_BUILD) minecraft-craftbukkit

install:
	$(DOCKER_COMPOSE_UP)

clean:
	docker image rm $(PRUNE_IMAGES) || true
	docker builder prune -f
