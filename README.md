# ansible-infra

Ansible automation for ansible-infra

## Prerequisites

- [uv](https://docs.astral.sh/uv/) and Python 3.12 or newer
- Docker with the Compose v2 plugin (`docker compose version`), for `make test` (Molecule)
- SSH access to the hosts as the user in `group_vars/all/connection.yml`; the `slack_bot` hosts use AWS SSM instead (see below)

## Setup

```bash
git init            # if this is not a repository yet
make install        # tools, collections, pre-commit hooks
make help           # every command
```

## Structure

```text
ansible-infra/
├── inventories/<env>/   hosts.yml, group_vars/all/{vars,vault}.yml, one directory per environment
├── playbooks/           site.yml imports one playbook per host type
├── roles/               one role per function, each with a Molecule scenario
├── scripts/             run-playbook.sh, vault-init.sh, check-vault-encrypted.sh
├── .github/             CI, check and apply workflows, PR and commit templates
├── ansible.cfg  requirements.yml  pyproject.toml  Makefile
├── .ansible-lint  .yamllint  .pre-commit-config.yaml
└── AGENTS.md  README.md
```

## Everyday commands

| Command | What it does |
|---|---|
| `make lint` | yamllint and ansible-lint (production profile) |
| `make scan` | gitleaks secret scan of the history (needs Docker) |
| `make syntax` | `ansible-playbook --syntax-check` for every environment |
| `make test` | Molecule tests of every role (needs Docker with Compose v2) |
| `make check ENV=<env>` | Dry run with a diff, changes nothing |
| `make deploy ENV=<env>` | Real run. Protected environments also need `CONFIRM=apply-<env>` |
| `make vault-init ENV=<env>` | Create the encrypted `vault.yml` of an environment |
| `make vault-edit ENV=<env>` | Edit the encrypted `vault.yml` of an environment |

Environments: `staging`, `production`. Narrow a run with `LIMIT=<host>`, `TAGS=<tag>` or `SKIP_TAGS=<tag>`, for example `make check ENV=staging LIMIT=web01 TAGS=base`.

## Deploy

Always check, then apply, one environment at a time, staging first.

```bash
make check ENV=staging                 # read the diff
make deploy ENV=staging
make check ENV=production
make deploy ENV=production CONFIRM=apply-production
```

From GitHub: run **Ansible Check** (Actions tab), review the diff in the job summary, then run **Ansible Apply** with the check's run id and `confirm_apply = apply-<env>`. Apply refuses a check run from another commit or with other inputs.

### GitHub setup

Create one GitHub environment per environment (`staging`, `production`) and add:

| Name | Kind | Value |
|---|---|---|
| `ANSIBLE_VAULT_PASSWORD` | secret | Vault password of that environment |
| `ANSIBLE_SSH_PRIVATE_KEY` | secret | Private key of the deploy user |
| `ANSIBLE_SSH_KNOWN_HOSTS` | secret | `known_hosts` lines of the managed hosts (host key checking stays on) |
| `AWS_ROLE_ARN` | variable | IAM role the workflows assume through GitHub OIDC to reach SSM hosts (the `slack_bot` group). Leave unset for an environment with no SSM hosts. |

The role behind `AWS_ROLE_ARN` trusts the GitHub OIDC provider for this repository and environment. It needs `ssm:StartSession`, `ssm:TerminateSession` and `ssm:DescribeInstanceInformation` on the target instances, plus read, write and delete on the transfer bucket (`ansible_aws_ssm_bucket_name`). The check and apply jobs also check out `agentic-slack-bot` at the git tag that matches `slack_bot_deploy_image_tag`, so the compose file and skills come from the revision that built the image.

Protect the default branch: require a pull request, one review and the `Lint` and `Molecule` checks. With a plan that has no environment approvals, branch protection is the control that stops unreviewed changes.

## Agentic Slack Bot

The `slack_bot` group deploys the Agentic Slack Bot with the `slack_bot_deploy` role. Staging hosts are reached over AWS SSM, so run Ansible with AWS credentials and the [session-manager-plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) installed. The compose file and skills come from a checkout of `agentic-slack-bot` next to this repository, or from `-e slack_bot_deploy_src_dir=<path>`.

| Task | Command |
|---|---|
| Deploy | `make check ENV=staging LIMIT=slack_bot`, then `make deploy ENV=staging LIMIT=slack_bot` |
| Copy skills only | `make deploy ENV=staging TAGS=skills` |
| Restart without pulling | `make deploy ENV=staging TAGS=restart` |
| Stop | `make deploy ENV=staging PLAYBOOK=playbooks/slack_bot_stop.yml` |
| Logs | `make check ENV=staging PLAYBOOK=playbooks/slack_bot_logs.yml` |
| Ship a new image | Change `slack_bot_deploy_image_tag` in `inventories/staging/group_vars/slack_bot/vars.yml`, then check and deploy |

See [roles/slack_bot_deploy/README.md](roles/slack_bot_deploy/README.md) for the variables.

## Secrets

- Never commit a secret in plain text. Secrets live in `inventories/<env>/group_vars/all/vault.yml` under `vault_*` names, encrypted with Ansible Vault.
- One vault password per environment, kept in `~/.vault/ansible-infra_<env>` outside the repository.
- `vault.example.yml` shows the shape. `make vault-init ENV=<env>` creates the real file.
- Pre-commit and CI reject a `vault.yml` that is not encrypted and any private key. CI and `make scan` run gitleaks over the history.

## Adding things

- A role: copy `roles/base` as the shape (defaults, vars, tasks per component, argument_specs, README, Molecule).
- A host type: a playbook in `playbooks/` that lists roles, imported from `playbooks/site.yml`.
- A host: add it to `inventories/<env>/hosts.yml` under its group.
- An environment: copy an `inventories/<env>/` directory, add its name to `ENVIRONMENTS` in the `Makefile` and to the workflow `options`.

See [AGENTS.md](AGENTS.md) for the rules AI coding agents follow in this repository.
