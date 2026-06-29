# vexa-sops

Single source of truth for the Vexa projects' [SOPS](https://github.com/getsops/sops) configuration and tooling. This repository holds **no secrets** — only public material:

- **`.sops.yaml`** — the age recipients every encrypted file is encrypted to (one developer key + one shared CI key).
- **`sops.mk`** — shared `make` targets (`sops-encrypt`, `sops-decrypt`, `sops-update`) used by every project repo.
- **`.sops-version`** — the pinned sops binary version the CI install actions are expected to match.

It is consumed by each project repo (vexa-iac, vexa-web, vexa-api, vexa-data, vexa-ctx) by cloning a pinned tag into a gitignored `.sops-tools/` directory and including `sops.mk`. Because encryption is pinned to this repo's `.sops.yaml` via `sops --config`, it works regardless of where a repo is checked out — no dependency on a parent directory layout.

## Consuming this repo

Add the following to a project repo's `Makefile`:

```make
# --- secrets (shared SOPS tooling from northconn/vexa-sops) --------------------
VEXA_SOPS_REPO ?= https://github.com/northconn/vexa-sops
VEXA_SOPS_REF  ?= v1

.PHONY: sops-init
sops-init: ## vendor the shared SOPS tooling into ./.sops-tools (pinned to VEXA_SOPS_REF)
	@if [ -d .sops-tools/.git ]; then \
		git -C .sops-tools fetch --depth 1 origin "refs/tags/$(VEXA_SOPS_REF):refs/tags/$(VEXA_SOPS_REF)" 2>/dev/null || true; \
		git -C .sops-tools -c advice.detachedHead=false checkout -q "$(VEXA_SOPS_REF)"; \
	else \
		git -c advice.detachedHead=false clone --depth 1 --branch "$(VEXA_SOPS_REF)" "$(VEXA_SOPS_REPO)" .sops-tools; \
	fi
	@echo "vexa-sops pinned at $(VEXA_SOPS_REF) in ./.sops-tools"

-include .sops-tools/sops.mk
```

Add `.sops-tools/` to the repo's `.gitignore`. The leading dash on `-include` keeps `make` working before `sops-init` has run.

Then:

```bash
make sops-init       # once per clone (and whenever VEXA_SOPS_REF changes)
make sops-decrypt    # restore plaintext working files from the committed *.enc*
make sops-encrypt    # re-encrypt changed .env*/*.tfvars to the shared recipients
```

### Repo-specific extra encrypted files

`sops-update` rotates the standard encrypted types (`*.enc`, `*.enc.tfvars`, `*.enc.yaml`). A repo with other encrypted artifacts injects them via `SOPS_EXTRA_ENC` (space separated, globs allowed), for example in vexa-iac's Makefile:

```make
SOPS_EXTRA_ENC = ansible/playbooks/kubeconfigs/*.yaml
```

Only files containing sops ciphertext (`ENC[...]`) are touched; plaintext files matching a glob are skipped.

## What the targets do

| Target         | Action                                                                                                                                                                          |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sops-encrypt` | Encrypts `.env`, `.env.*`, and `*.tfvars` (excluding `*.example` and already-encrypted files) to `.env*.enc` / `.enc.tfvars`, using the recipients in `.sops-tools/.sops.yaml`. |
| `sops-decrypt` | Decrypts `*.enc.tfvars`, `.env.enc`, `.env.*.enc`, and `*.enc.yaml` back to their plaintext working files.                                                                      |
| `sops-update`  | Rotates the recipient list on every encrypted file (standard types + `SOPS_EXTRA_ENC`).                                                                                         |

Encryption needs the recipients (`--config`); decryption and rotation read recipients from each file's metadata and use your age key (`SOPS_AGE_KEY`, `SOPS_AGE_KEY_FILE`, or `~/.config/sops/age/keys.txt`).

## Rotating the age key

Recipients are public, so rotation is a re-key of existing files — no plaintext leaves the repos.

1. Generate the new key: `age-keygen -o new-key.txt`.
2. Add its public recipient to this repo's `.sops.yaml` **without removing the old one**; commit and cut a new tag.
3. In each consuming repo: `make sops-init VEXA_SOPS_REF=<new-tag>` then `make sops-update` (rotates **all** encrypted files, including ansible `*.enc.yaml` and k3s kubeconfigs via `SOPS_EXTRA_ENC`). Commit.
4. Update the `SOPS_AGE_KEY` GitHub Actions secret on each repo and confirm CI passes.
5. Remove the old recipient from `.sops.yaml`, cut another tag, re-run `make sops-init` + `make sops-update` in each repo, commit, and shred the old key from developer machines.

## Version pin

`.sops-version` is the single source of the pinned sops version. The project repos install sops in CI through their own actions (`setup-sops` in vexa-web/vexa-api, `setup-iac-tools` in vexa-iac); a drift-check workflow here asserts those pins match `.sops-version` so CI never has to clone this repo at decrypt time.
