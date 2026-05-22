# GitHub Actions runner container

This runs the official GitHub Actions runner image as a long-lived Docker Compose service.

## Register and start

1. In GitHub, open the repository or organization:
   - Repository: `Settings` -> `Actions` -> `Runners` -> `New self-hosted runner`
   - Organization: `Settings` -> `Actions` -> `Runners` -> `New runner`

2. Copy the registration token from GitHub's generated `./config.sh --url ... --token ...` command.

3. Create the local environment file:

   ```bash
   cd container-runner
   cp .env.example .env
   ```

4. Edit `.env`:

   ```dotenv
   GITHUB_URL=https://github.com/OWNER/REPO
   RUNNER_TOKEN=YOUR_FRESH_REGISTRATION_TOKEN
   RUNNER_NAME=container-runner-1
   RUNNER_LABELS=docker,self-hosted
   ```

5. Start the long-lived container:

   ```bash
   docker compose up -d --build
   docker compose logs -f github-runner
   ```

After the first successful registration, the runner state is saved in the `runner-state`
Docker volume.
Normal container restarts do not need a new token.

## Use it in a workflow

```yaml
jobs:
  build:
    runs-on: [self-hosted, docker]
    steps:
      - uses: actions/checkout@v6
      - run: docker version
```

## Remove the runner registration

Get a fresh runner token from the same GitHub runner page, put it in `.env`, then run:

```bash
docker compose run --rm github-runner /usr/local/bin/remove-runner.sh
docker compose down
```

## Notes

- The official `ghcr.io/actions/actions-runner` image is intentionally minimal, not the same as GitHub-hosted `ubuntu-latest`.
- The Docker socket mount lets jobs run Docker commands on the host Docker daemon. Treat this as root-equivalent access to the host.
- On startup, the container adds the `runner` user to the group that owns `/var/run/docker.sock`, then runs the GitHub runner as `runner`.
- Do not attach this runner to public repositories unless you fully trust every workflow that can target it.
