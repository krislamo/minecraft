DOCKER_BUILDKIT ?= 1
BUILDKIT_PROGRESS ?= auto
BUILD ?= basic

DOCKER_COMPOSE_OPTS = BUILDX_GIT_LABELS=full \
	DOCKER_BUILDKIT=$(DOCKER_BUILDKIT) \
	BUILDKIT_PROGRESS=$(BUILDKIT_PROGRESS)
DOCKER_COMPOSE_BUILD = $(DOCKER_COMPOSE_OPTS) docker compose -f docker-compose.build.yml build
DOCKER_COMPOSE_UP = docker compose up -d

PRUNE_IMAGES = \
	localhost/minecraft:latest \
	localhost/minecraft:latest-paper \
	localhost/minecraft:latest-spigot \
	localhost/minecraft:latest-craftbukkit \
	localhost/minecraft-jre:latest \
	localhost/minecraft-jdk:latest

.PHONY: all clean configure craftbukkit default install jdk jre spigot vanilla
default: vanilla
all: vanilla paper spigot craftbukkit

jre:
	$(DOCKER_COMPOSE_BUILD) minecraft-jre

jdk:
	$(DOCKER_COMPOSE_BUILD) minecraft-jdk

vanilla: jre
	$(DOCKER_COMPOSE_BUILD) minecraft-vanilla

paper: jre
	$(DOCKER_COMPOSE_BUILD) minecraft-paper

spigot: jre jdk
	$(DOCKER_COMPOSE_BUILD) minecraft-spigot

craftbukkit: jre jdk
	$(DOCKER_COMPOSE_BUILD) minecraft-craftbukkit

install:
	$(DOCKER_COMPOSE_UP)

# Macro to copy files if they don't already exist or are the same
define copy_build_files
	set -eu; \
	BUILD=$(1) && \
	FILE=$(2) && \
	DIRECTORY=$(if $(3),$(3),builds) && \
	SRC_FILE="./$${DIRECTORY}/$${BUILD}/$${FILE}" && \
	DEST_FILE="./$${FILE}" && \
	TEMP_DEST_FILE="$$(mktemp)" && \
	if [ -f "$${SRC_FILE}" ]; then \
		if [ -f "$${DEST_FILE}" ]; then \
			cp "$${DEST_FILE}" "$${TEMP_DEST_FILE}"; \
			if [ "$${FILE}" = ".env" ] && grep -q 'EULA=false' "$${SRC_FILE}"; then \
				sed -i 's/EULA=true/EULA=false/' "$${TEMP_DEST_FILE}"; \
			fi; \
			if cmp -s "$${SRC_FILE}" "$${TEMP_DEST_FILE}"; then \
				echo "INFO: \"$${DEST_FILE}\" is up to date."; \
				rm "$${TEMP_DEST_FILE}"; \
			else \
				echo "ERROR: \"$${DEST_FILE}\" is different from \"$${SRC_FILE}\""; \
				diff -u "$${DEST_FILE}" "$${SRC_FILE}"; \
				rm "$${TEMP_DEST_FILE}"; \
				exit 1; \
			fi; \
		else \
			cp "$${SRC_FILE}" "$${DEST_FILE}"; \
			echo "INFO: \"$${SRC_FILE}\" copied to \"$${DEST_FILE}\""; \
		fi; \
	else \
		echo "ERROR: Source file \"$${SRC_FILE}\" does not exist."; \
		exit 1; \
	fi
endef

configure:
	@if [ -d "./builds/$(BUILD)" ]; then \
		echo "INFO: Configuring build $(BUILD) (./builds/$(BUILD))" && \
		$(call copy_build_files,$(BUILD),.env); \
		$(call copy_build_files,$(BUILD),plugins.json); \
	elif [ -d "./scratch/$(BUILD)" ]; then \
		echo "INFO: Configuring build $(BUILD) (./scratch/$(BUILD))" && \
		$(call copy_build_files,$(BUILD),.env,scratch); \
		$(call copy_build_files,$(BUILD),plugins.json,scratch); \
	else \
		echo "ERROR: Build directory for \"$(BUILD)\" not found"; \
		exit 1; \
	fi

clean:
	docker image rm $(PRUNE_IMAGES) || true
	docker builder prune -f
