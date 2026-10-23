---
name: code-review
description: Run the team's code review checklist — correctness, idempotency/safety, secrets handling, overengineering, error handling — against a file/directory or the current uncommitted diff of Ansible playbooks/roles. Use before opening a PR, when asked to review a role or playbook, or via /code-review.
---

# Code review

Review the target (a given file/directory path, or the current uncommitted changes if none was
given) against this checklist. This is the team's own bar for this Ansible repo, not a generic
linter pass — every finding should be concrete enough to act on. `ansible-lint`/`yamllint`
(`make lint`) catch style issues; this review is for the things they don't.

## Correctness & Consistency

- Logic errors, edge cases (e.g. `SVC=all` vs a specific service list, missing env in a `when:`)
- Inconsistent tag naming — existing convention is `*_init` / `*_update` / `*_restart`; flag tasks
  that don't follow it or that use tags too coarse to target a partial deploy
- Variable naming/placement inconsistent with sibling roles or `group_vars`
- Values hardcoded in a role/playbook that should come from `group_vars/<env>` instead (breaks
  reuse across staging/production — see [[100x-ansible-inventory]])
- Jinja2 template (`.j2`) logic that silently produces wrong output for an unset/default variable

## Code Quality

- Duplicated tasks across roles/playbooks that should be a shared role, template, or `include_tasks`
- Dead code: unused variables in `defaults/main.yml`, unreferenced templates, unreachable `when:` branches
- A role or playbook doing too much — flag any `tasks/main.yml` mixing unrelated concerns that
  should split into separate tagged blocks or roles
- Role `README.md` not updated when a variable was added, renamed, or its default changed (see
  [[100x-ansible-roles]])

## Idempotency & Safety

- Non-idempotent `shell`/`command` tasks missing `creates`/`removes`, `changed_when`, or a guard —
  re-running the playbook should not redo work or error out
- Destructive operations (`rm -rf`, `docker system prune`, `docker compose down -v`, overwriting a
  file with no backup) run unconditionally or without confirmation gating
- Tasks that aren't safe to dry-run — verify `--check --diff` behavior isn't broken by a task that
  always reports "changed" or crashes under check mode
- Missing `become`/privilege scoping — tasks running as root that don't need to, or vice versa

## Secrets & Vault Handling

- Plaintext secrets in `group_vars`, playbook vars, or committed `.env`/`secret.env` files instead
  of `vault.yml` (see [[100x-ansible-vault]])
- Tasks handling secrets without `no_log: true` — check whether a failure or `-v` run would leak a
  credential to the console/CI log
- `vault.yml` or `secret.env` edited in a way that suggests it was decrypted and re-saved unencrypted
- New credentials introduced without checking whether an existing vaulted var already covers them

## Overengineering

- Premature abstraction — a new role, variable, or conditional added for a single call site with no
  second consumer in sight
- Config-driven logic (a flag, a lookup table) where a plain task would do
- Wrapper playbooks/roles that just pass variables through without adding behavior

## Error Handling & Resilience

- `ignore_errors: true` or `failed_when: false` masking a real failure instead of a narrow, checked
  condition
- Missing `retries`/`until` on tasks that hit the network (image pulls, API calls, SSM) or an
  external service that can be briefly unavailable
- A multi-step deploy with no rollback or clear failure point if a middle step fails (e.g. compose
  up succeeds but a health check after it isn't verified)
- Missing input validation for required extra-vars (compare against the `check-env`/`check-svc`/
  `check-mode` guards already used in the `Makefile`)

## Output format

For each issue found, provide:

- File:line — exact location
- Severity — critical / major / minor
- Issue — one-sentence description
- Fix — concrete code change or refactor (not just "consider improving")
