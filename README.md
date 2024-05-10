# Minecraft Docker Image

This Dockerfile sets up a Minecraft server based on Debian stable. WIP.

To test image creation, run:
```
docker build --build-arg EULA=true -t minecraft . && \
docker run -d --name minecraft --rm minecraft && \
docker logs -f minecraft
```

## Copyright and License
Copyright (C) 2024  Kris Lamoureux

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 3 of the License.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.
