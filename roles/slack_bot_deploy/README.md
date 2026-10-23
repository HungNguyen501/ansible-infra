# slack_bot_deploy

Deploys the Agentic Slack Bot (redis, receiver, worker, scheduler, ngrok) to a host with docker compose. The compose file and the worker skills are copied from a local checkout of `agentic-slack-bot`, the receiver, worker and scheduler run a pre-built image from Docker Hub, and nothing is built on the host.

The host needs Docker with the compose plugin (2.18 or newer) and Python 3.

## Variables

| Variable | Default | Description |
|---|---|---|
| `slack_bot_deploy_dir` | `/var/workspace/agentic-slack-bot` | Directory on the host that holds the compose files and the worker skills. |
| `slack_bot_deploy_src_dir` | `$SLACK_BOT_SRC_DIR`, else `{{ playbook_dir }}/../../agentic-slack-bot` | Local checkout of the `agentic-slack-bot` repository. The deploy workflows set the environment variable. |
| `slack_bot_deploy_image_repo` | required | Docker Hub repository of the image. |
| `slack_bot_deploy_image_tag` | required | Image tag to deploy. Pin a version. |
| `slack_bot_deploy_services` | `[redis, receiver, worker, scheduler, ngrok]` | Compose services started and restarted. |
| `slack_bot_deploy_worker_count` | `2` | Number of worker containers. |
| `slack_bot_deploy_env` | `{}` | Non-secret `NAME: value` environment of the compose project. |
| `slack_bot_deploy_secret_env` | required | Secret `NAME: value` environment. Alias `vault_*` variables here. |
| `slack_bot_deploy_log_service` | `""` | Service for the `logs` entry point. Empty means all. |
| `slack_bot_deploy_log_tail` | `50` | Log lines per container for the `logs` entry point. |

The environment fills the `${NAME}` references of `docker-compose.yml` through a `.env` file in the deploy directory (owner root, mode `0600`). The role writes it just before each compose call and deletes it right after, even when the call fails, so secrets are on disk only while compose runs. A file upload is used, because passing the values as process environment makes the SSM session stall. If a run is killed mid-way the file can stay behind: `make deploy` with `PLAYBOOK=playbooks/slack_bot_stop.yml` or the next deploy replaces and removes it. Secret values must not contain a placeholder: a deploy stops while any value is `replace-me`.

## Entry points and tags

| What | How |
|---|---|
| Full deploy | `playbooks/slack_bot.yml` (part of `site.yml`) |
| Copy the worker skills only | `TAGS=skills`. Services read the skills volume on the next request, no restart needed. The skills are those of the checkout, which the workflows pin to the image tag. |
| Restart without pulling | `TAGS=restart` (tagged `never`, so a full deploy does not run it) |
| Stop and remove orphans | `playbooks/slack_bot_stop.yml` (`tasks_from: stop.yml`) |
| Recent logs | `playbooks/slack_bot_logs.yml` (`tasks_from: logs.yml`) |

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
make test   # Molecule: stages the files and syncs the skills, checks idempotence. Needs Docker.
```

The Molecule scenario does not start the compose project, because that needs a Docker daemon inside the instance.
