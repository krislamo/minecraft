# Minecraft Container Image

## Quick Start
Assume a clean repository (i.e., without .env and plugins.json in the top
directory), and Docker cache. You can use `make clean` to clear specific
default images and prune the unused build cache. However, you'll still need to
inspect all containers and images to ensure you've removed them all.

- `make clean` only removes certain images and prunes the builder cache.

### Steps

1. **Configure your build:**
    ```
    make configure
    ```
    This defaults to `make configure BUILD=basic`, but if you have directories
    in `./scratch`, you can specify those build names here. Repository-included
    builds are in`./builds`, but it's advised to copy `./builds/basic` or
    whichever build configuration you are basing off and copy it into
    `./scratch/X` to control your settings apart from the repository. This
    separation allows you to manage your configurations independently and avoid
    overwriting repository defaults.

2.  **Build the PaperMC server:**

    ```
    make paper
    ```
    This builds the PaperMC server, which is likely what you want unless you
    prefer a 100% vanilla server experience. PaperMC is recommended for its
    performance benefits and support for Bukkit API server mods. Both
    EssentialsX and WorldGuard suggest using Paper for better performance and
    stability.

3.  **(Optional) Install for testing:**

    ```
    make install
    ```
    This runs `docker compose up -d` and brings up a `minecraft-minecraft-1`
    network/container compose stack using the `.env` and `plugins.json` in the
    root of the repository. It includes settings for image overrides, the
    `EULA` agreement, and a `DEBUG` option for the custom `entrypoint.sh`
    script, Java options (defaulting to `-Xms1G -Xmx2G`), and the ability to
    set any `server.properties` file entry using the `SETTINGS_` prefix in the
    compose file. The purpose of `make install` is for testing only, and it is
    advised not to rely on it for managing an actual server deployment. You
    will likely want to add other settings not specified in the
    `docker-compose.yml` and manage your own compose files.

## Additional Notes

### Image Management
All images are tagged with `localhost/minecraft`, etc. It's acceptable not to
override these default image names and just tag your own versions after
building the `localhost` images. The images will include git hash information
for extra traceability.

After using the quick start, you'll get something like this:
```
$ docker image ls
REPOSITORY                TAG            IMAGE ID       CREATED          SIZE
localhost/minecraft       1.20.1-paper   814edda474c4   9 seconds ago    568MB
localhost/minecraft-jre   latest         50350d8d3947   30 seconds ago   379MB
```

It is advisable to tag your own images and push them to a private container
repository, as you'll want to avoid pushing these images to a public DockerHub
repository due to the Minecraft EULA with typical proprietary software
non-redistribution rules.

```
docker tag localhost/minecraft:1.20.1-paper example.org/minecraft:1.20.1-paper
docker push example.org/minecraft:1.20.1-paper
```

## License
This project is licensed under the GPLv3 License. See the LICENSE file for details.
