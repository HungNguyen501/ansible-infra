# ansible-infra

Ansible automation for ansible-infra

## Prerequisites

- [uv](https://docs.astral.sh/uv/) and Python 3.12 or newer
- Docker, for `make test` (Molecule)
- SSH access to the hosts as the user in `group_vars/all/connection.yml`

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
| `make test` | Molecule tests of every role (needs Docker) |
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

Protect the default branch: require a pull request, one review and the `Lint` and `Molecule` checks. With a plan that has no environment approvals, branch protection is the control that stops unreviewed changes.

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
