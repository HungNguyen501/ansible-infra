# ansible-infra

Ansible automation for ansible-infra. The project rules, commands and structure are in `AGENTS.md`: read it first.

## Skills

Installed from the agent-skills hub (see `.claude/skills/.hub-skills.json`):

- `ansible-code-style`: Conventions for writing and reviewing Ansible YAML, tasks, variables, Jinja2 and templates - FQCN, task names, variable
- `ansible-inventory-vars`: Inventory and variable design for Ansible - one directory per environment, group_vars and host_vars as directories, plai
- `ansible-roles-playbooks`: How to structure Ansible automation - the landscape, type, function, component hierarchy, role layout, defaults vs vars,
- `ansible-safe-deploys`: Safe execution of Ansible against live hosts - check then apply, --diff review, serial batches and max_fail_percentage,
- `ansible-testing`: Testing and quality gates for Ansible content - ansible-lint production profile, yamllint, syntax check, Molecule scenar
- `ansible-vault-secrets`: Handling secrets in Ansible repos - Ansible Vault files and encrypt_string, vault_ variable naming, per-environment vaul
