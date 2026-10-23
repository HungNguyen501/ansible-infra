# slack_bot_deploy

Deploys the Agentic Slack Bot (redis, receiver, worker, scheduler, ngrok) to a host with docker compose. The compose file is copied from a local checkout of `agentic-slack-bot`, the receiver, worker and scheduler run a pre-built image from Docker Hub, and nothing is built on the host. The worker skills are part of that image: the prod override drops the bind mount of `docker-compose.yml` that would hide them.

The host needs Docker with the compose plugin (2.24 or newer, for `!reset` in the override) and Python 3.

## Variables

| Variable | Default | Description |
|---|---|---|
| `slack_bot_deploy_dir` | `/var/workspace/agentic-slack-bot` | Directory on the host that holds the compose files. |
| `slack_bot_deploy_src_dir` | `$SLACK_BOT_SRC_DIR`, else `{{ playbook_dir }}/../../agentic-slack-bot` | Local checkout of the `agentic-slack-bot` repository. The deploy workflows set the environment variable. |
| `slack_bot_deploy_image_repo` | required | Docker Hub repository of the image. |
| `slack_bot_deploy_image_tag` | required | Image tag to deploy. Pin a version. |
| `slack_bot_deploy_services` | `[redis, receiver, worker, scheduler, ngrok]` | Compose services started and restarted. |
| `slack_bot_deploy_worker_count` | `2` | Number of worker containers. |
| `slack_bot_deploy_env` | `{}` | Non-secret `NAME: value` environment of the compose project. |
| `slack_bot_deploy_secret_env` | required | Secret `NAME: value` environment. Alias `vault_*` variables here. |

The environment fills the `${NAME}` references of `docker-compose.yml` through a file under `/run/slack-bot-deploy/` (owner root, mode `0600`). `/run` is tmpfs, so the secrets never reach the disk. The role writes the file just before it starts the services and deletes it right after, even when that fails. Stop and restart need no values and write nothing. A failed start shows the output of Compose: it holds no secret values. A file upload is used, because passing the values as process environment makes the SSM session stall. Each call uses a directory of its own, `/run/slack-bot-deploy-<random>`, and the file is uploaded through a tmpfs temporary directory (`/dev/shm`), so it never touches the disk on the way. A call removes only its own directory. If a run is killed mid-way its directory stays until the next call finds it older than 6 hours or the host reboots. Values must not contain a single quote, a trailing backslash or a carriage return: the deploy stops and names the variable. Secret values must not contain a placeholder: a deploy stops while any value is `replace-me`.

## Entry points and tags

| What | How |
|---|---|
| Full deploy | `playbooks/slack_bot.yml` (part of `site.yml`) |
| Restart without pulling | `TAGS=restart` (tagged `never`, so a full deploy does not run it) |
| Stop and remove orphans | `playbooks/slack_bot_stop.yml` (`tasks_from: stop.yml`) |

Under `--check` the files are staged with a diff, and the compose tasks are skipped because compose cannot be dry run.

## Example

```yaml
- name: Deploy the Agentic Slack Bot
  hosts: slack_bot
  roles:
    - role: slack_bot_deploy
      vars:
        slack_bot_deploy_image_repo: hungwnguyen/agentic-slack-bot
        slack_bot_deploy_image_tag: v2026.10.09.9ea548
        slack_bot_deploy_env: {}
        slack_bot_deploy_secret_env:
          OPENAI_API_KEY: "{{ vault_slack_bot_openai_api_key }}"
```

## Test

```bash
make test   # Molecule: stages the files, checks idempotence and the env file handling. Needs Docker with Compose v2.
```

The Molecule scenario does not start the compose project, because that needs a Docker daemon inside the instance.
