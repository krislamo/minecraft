CONTAINER = minecraft-minecraft-1

.PHONY: default build clean install
default: build

build:
	docker compose build

clean:
	rm -f screenlog.0
	docker compose down --rmi all
	docker builder prune -f

install: build
	touch screenlog.0
	docker compose up -d && \
	docker logs -f $(CONTAINER)
