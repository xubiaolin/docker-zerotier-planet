# Compose Deployment Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace interactive script deployment with Docker Compose using `.env` configuration and fix file-server network security issues.

**Architecture:** Keep the existing single-container image and runtime layout. Add Compose and `.env.example` as the deployment interface, harden the in-container file download server, and update the entrypoint so runtime config consistently comes from environment variables and persisted config files.

**Tech Stack:** Docker Compose, Alpine shell, Node.js HTTP server, Markdown documentation, Bash static checks.

---

## File Structure

- Create `docker-compose.yml`: single-service Compose deployment driven by `.env`.
- Create `.env.example`: documented runtime configuration template.
- Modify `.gitignore`: ignore local `.env` secrets.
- Modify `patch/http_server.js`: path validation, key persistence, timing-safe key comparison, method restrictions.
- Modify `patch/entrypoint.sh`: safer quoting and consistent environment-driven config writes.
- Create `test/static_security_checks.sh`: repository-level static checks for the new deployment and security expectations.
- Modify `README.md` and `README.en.md`: make Compose the primary deployment flow and replace one-click script operations.

## Tasks

### Task 1: Static Checks

**Files:**
- Create: `test/static_security_checks.sh`

- [ ] **Step 1: Write the failing static checks**

```bash
#!/usr/bin/env bash
set -euo pipefail

require_file() {
  test -f "$1" || {
    echo "missing required file: $1" >&2
    exit 1
  }
}

require_grep() {
  local pattern="$1"
  local file="$2"
  grep -Eq "$pattern" "$file" || {
    echo "missing pattern '$pattern' in $file" >&2
    exit 1
  }
}

require_file docker-compose.yml
require_file .env.example

for key in DOCKER_IMAGE IP_ADDR4 IP_ADDR6 ZT_PORT API_PORT FILE_SERVER_PORT FILE_KEY ZEROTIER_DIST_DIR ZEROTIER_ZTNCUI_DIR ZEROTIER_ONE_DIR ZEROTIER_CONFIG_DIR; do
  require_grep "^${key}=" .env.example
done

require_grep '^\.env$' .gitignore
require_grep '\$\{DOCKER_IMAGE\}' docker-compose.yml
require_absent 'container_name:' docker-compose.yml
require_grep '\$\{ZT_PORT\}:\$\{ZT_PORT\}/tcp' docker-compose.yml
require_grep '\$\{ZT_PORT\}:\$\{ZT_PORT\}/udp' docker-compose.yml
require_grep '\$\{API_PORT\}:\$\{API_PORT\}' docker-compose.yml
require_grep '\$\{FILE_SERVER_PORT\}:\$\{FILE_SERVER_PORT\}' docker-compose.yml
require_grep '\$\{ZEROTIER_DIST_DIR\}:/app/dist' docker-compose.yml
require_grep 'FILE_KEY=\$\{FILE_KEY' docker-compose.yml

require_grep 'path\.resolve' patch/http_server.js
require_grep 'timingSafeEqual' patch/http_server.js
require_grep 'method !== .GET. && method !== .HEAD.' patch/http_server.js
require_grep 'existingKey' patch/http_server.js
require_grep 'FILE_KEY' patch/http_server.js

require_grep 'HTTP_ALL_INTERFACES=true' patch/entrypoint.sh
require_grep 'FILE_KEY' patch/entrypoint.sh

echo "static security checks passed"
```

- [ ] **Step 2: Run checks to verify they fail**

Run: `bash test/static_security_checks.sh`

Expected: FAIL with `missing required file: docker-compose.yml`.

### Task 2: Compose Configuration

**Files:**
- Create: `docker-compose.yml`
- Create: `.env.example`
- Modify: `.gitignore`

- [ ] **Step 1: Implement Compose files**

`docker-compose.yml` should define service `myztplanet`, use `${DOCKER_IMAGE}`, publish all four port mappings, pass environment variables, mount host directories from `.env`, and use `restart: unless-stopped`.

`.env.example` should provide safe placeholders and a strong `FILE_KEY` placeholder instruction.

`.gitignore` should include `.env`.

- [ ] **Step 2: Run static checks**

Run: `bash test/static_security_checks.sh`

Expected: FAIL until `patch/http_server.js` and `patch/entrypoint.sh` are hardened.

### Task 3: Harden File Server

**Files:**
- Modify: `patch/http_server.js`

- [ ] **Step 1: Implement file-server security fixes**

Use `path.resolve` to normalize requested paths, reject resolved paths outside `/app/dist`, load key from `FILE_KEY` or `/app/config/file_server.key`, generate and persist a random key only if needed, compare with `crypto.timingSafeEqual`, and allow only `GET` and `HEAD`.

- [ ] **Step 2: Verify Node syntax**

Run: `node --check patch/http_server.js`

Expected: PASS.

### Task 4: Harden Entrypoint

**Files:**
- Modify: `patch/entrypoint.sh`

- [ ] **Step 1: Implement shell improvements**

Quote paths, create config directories before writes, persist `FILE_KEY` when provided, continue public ztncui binding with `HTTP_ALL_INTERFACES=true`, and keep first-run initialization behavior.

- [ ] **Step 2: Verify shell syntax**

Run: `sh -n patch/entrypoint.sh`

Expected: PASS.

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `README.en.md`

- [ ] **Step 1: Update deployment docs**

Replace the one-click script install path with Compose deployment steps, update feature text, update prerequisites, add management commands, and update reset-password and uninstall FAQ entries to use `docker compose`.

- [ ] **Step 2: Search for stale one-click install guidance**

Run: `rg -n "deploy\\.sh|一键部署脚本|one-click deployment script|Run the Installer|执行安装脚本" README.md README.en.md`

Expected: No install-path references to the script remain.

### Task 6: Final Verification

**Files:**
- Verify all modified files

- [ ] **Step 1: Run all verification commands**

Run:

```bash
bash test/static_security_checks.sh
node --check patch/http_server.js
sh -n patch/entrypoint.sh
docker compose config
```

Expected: all commands exit 0.

- [ ] **Step 2: Review git diff**

Run: `git diff --stat && git diff --check`

Expected: no whitespace errors; diff only covers intended files.
