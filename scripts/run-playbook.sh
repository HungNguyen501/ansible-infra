#!/usr/bin/env bash
# Single entry point that runs a playbook against one environment. The Makefile and the GitHub workflows both call it, so input validation lives in one place.
# Reads its inputs from environment variables, never from the command line, so CI can pass untrusted workflow inputs without shell interpolation.
#   ENVIRONMENT  required, a directory name under inventories/
#   MODE         required, check (dry run with a diff) or apply
#   PLAYBOOK     optional, path under playbooks/ (default: playbooks/site.yml)
#   LIMIT, TAGS, SKIP_TAGS  optional
#   SERVICE      optional, comma-separated compose services of the Agentic Slack Bot to start or restart (default: all of them)
#   IMAGE_TAG    optional, the image tag of the Agentic Slack Bot. Passed as slack_bot_deploy_image_tag, which the role requires
#   VAULT_DIR    optional, where vault password files live (default: ~/.vault)
set -euo pipefail

project="ansible-infra"
environment="${ENVIRONMENT:?ENVIRONMENT is required}"
mode="${MODE:?MODE is required (check or apply)}"
playbook="${PLAYBOOK:-playbooks/site.yml}"
limit="${LIMIT:-}"
tags="${TAGS:-}"
skip_tags="${SKIP_TAGS:-}"
image_tag="${IMAGE_TAG:-}"
service="${SERVICE:-}"

fail() {
    echo "error: $*" >&2
    exit 1
}

[[ "${environment}" =~ ^[a-z][a-z0-9]*$ ]] || fail "ENVIRONMENT must be lowercase letters and digits"
[ -d "inventories/${environment}" ] || fail "no inventory directory inventories/${environment}"
[[ "${mode}" == "check" || "${mode}" == "apply" ]] || fail "MODE must be check or apply"
[[ "${playbook}" =~ ^playbooks/[A-Za-z0-9_./-]+\.yml$ && "${playbook}" != *..* ]] || fail "PLAYBOOK must be a .yml path under playbooks/"
[ -f "${playbook}" ] || fail "playbook ${playbook} does not exist"
[[ -z "${limit}" || "${limit}" =~ ^[A-Za-z0-9_.,:*!@\&-]+$ ]] || fail "LIMIT has characters outside A-Z a-z 0-9 _ . , : * ! @ & -"
[[ -z "${tags}" || "${tags}" =~ ^[A-Za-z0-9_,-]+$ ]] || fail "TAGS must be comma-separated tag names"
[[ -z "${skip_tags}" || "${skip_tags}" =~ ^[A-Za-z0-9_,-]+$ ]] || fail "SKIP_TAGS must be comma-separated tag names"
[[ -z "${service}" || "${service}" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*(,[A-Za-z0-9][A-Za-z0-9_.-]*)*$ ]] || fail "SERVICE must be comma-separated compose service names: letters, digits, _ . -"
[[ -z "${image_tag}" || "${image_tag}" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]] || fail "IMAGE_TAG must be a Docker image tag: letters, digits, _ . - and at most 128 characters"

# --- Agentic Slack Bot: suggest values instead of failing later with a bare "missing argument". ---
# The services are the ones of the compose template, so the hint cannot go stale.
slack_bot_services() {
    awk '/^services:/{s=1;next} /^[a-z]/{s=0} s && /^  [a-z][a-z0-9_-]*:[[:space:]]*$/{gsub(/[ :]/,"");print}' \
        roles/slack_bot_deploy/templates/docker-compose.yml.j2
}

# True when the playbook deploys the bot and the environment has hosts for it.
deploys_slack_bot() {
    [[ "${playbook}" =~ ^playbooks/(site|slack_bot)\.yml$ ]] || return 1
    local graph
    graph="$(ansible-inventory -i "inventories/${environment}" --graph slack_bot 2>/dev/null || true)"
    [[ "${graph}" == *"|--"* ]]
}

# Newest tags of the image on Docker Hub, if it can be reached in a few seconds. Silent when it cannot.
recent_image_tags() {
    local repo
    repo="$(sed -nE 's/^slack_bot_deploy_image_repo:[[:space:]]*"?([^"[:space:]]+)"?[[:space:]]*$/\1/p' \
        "inventories/${environment}/group_vars/slack_bot/vars.yml" 2>/dev/null || true)"
    [[ "${repo}" =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || return 0
    curl -fsS --connect-timeout 3 --max-time 5 "https://hub.docker.com/v2/repositories/${repo}/tags?page_size=5&ordering=last_updated" 2>/dev/null \
        | python3 -I -c 'import json, sys; print("\n".join("    " + t["name"] for t in json.load(sys.stdin)["results"]))' 2>/dev/null || true
}

if [ -z "${image_tag}" ] && deploys_slack_bot; then
    {
        echo "error: ${playbook} deploys the Agentic Slack Bot on ${environment}, which needs IMAGE_TAG."
        echo "  make ${mode/apply/deploy} ENV=${environment} PLAYBOOK=${playbook} IMAGE_TAG=<tag> [SERVICE=<name>[,<name>]]"
        recent="$(recent_image_tags)"
        if [ -n "${recent}" ]; then
            echo "  latest image tags:"
            echo "${recent}"
        fi
        echo "  services: $(slack_bot_services | tr '\n' ' ')(default: all)"
    } >&2
    exit 1
fi

if [ -n "${service}" ]; then
    known="$(slack_bot_services)"
    IFS=',' read -ra requested <<< "${service}"
    for name in "${requested[@]}"; do
        grep -qx -- "${name}" <<< "${known}" || fail "SERVICE ${name} is not a service of the Agentic Slack Bot. Services: $(tr '\n' ' ' <<< "${known}")"
    done
fi

args=(-i "inventories/${environment}" "${playbook}" --diff)
[ "${mode}" = "check" ] && args+=(--check)
[ -n "${limit}" ] && args+=(--limit "${limit}")
[ -n "${tags}" ] && args+=(--tags "${tags}")
[ -n "${skip_tags}" ] && args+=(--skip-tags "${skip_tags}")
[ -n "${image_tag}" ] && args+=(-e "slack_bot_deploy_image_tag=${image_tag}")
if [ -n "${service}" ]; then
    # The names passed the check above, so they hold no quote or backslash and can go into JSON as they are.
    args+=(-e "{\"slack_bot_deploy_services\": [\"${service//,/\",\"}\"]}")
fi

# The vault password file is optional: a repository with no vault.yml yet needs none.
password_file="${VAULT_DIR:-${HOME}/.vault}/${project}_${environment}"
if [ -f "${password_file}" ]; then
    export ANSIBLE_VAULT_PASSWORD_FILE="${password_file}"
fi

echo "==> ${mode} ${playbook} on ${environment}" >&2
exec ansible-playbook "${args[@]}"
