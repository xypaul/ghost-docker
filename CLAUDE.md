# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker Compose setup for Ghost, a modern publishing platform. The repository currently contains a minimal structure with a `compose.yml` file for containerized deployment.

## Common Commands

Since this is a Docker Compose project, the primary commands will be:

- `docker compose up -d` - Start Ghost services in detached mode
- `docker compose down` - Stop and remove Ghost services
- `docker compose logs` - View service logs
- `docker compose ps` - View running services
- `docker compose pull` - Pull latest images

## Architecture

The project uses Docker Compose to orchestrate Ghost and its dependencies (typically MySQL/MariaDB database). The main configuration is defined in `compose.yml`.
