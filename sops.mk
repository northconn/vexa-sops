# sops.mk — shared SOPS encrypt/decrypt/rotate targets for the Vexa repositories.
#
# A repo vendors this file with `make sops-init` (see README) into ./.sops-tools
# and loads it via `-include .sops-tools/sops.mk`. Encryption is pinned to the
# shared recipient list in .sops-tools/.sops.yaml through --config, so it does
# not depend on where the repo is checked out (no directory-tree search).
# Decryption and key rotation read recipients from each encrypted file's own
# metadata and need no config.

SOPS        ?= sops
SOPS_CONFIG ?= .sops-tools/.sops.yaml

# Extra, already-encrypted paths or globs a repo wants rotated alongside the
# standard set (e.g. vexa-iac's k3s kubeconfigs). Space separated; may glob.
SOPS_EXTRA_ENC ?=

.PHONY: _sops-require sops-encrypt sops-decrypt sops-update

_sops-require:
	@command -v $(SOPS) >/dev/null 2>&1 || { echo >&2 "sops is required but not installed: https://github.com/getsops/sops/releases"; exit 1; }

sops-encrypt: _sops-require ## encrypt this repo's .env*/*.tfvars -> .env*.enc / .enc.tfvars (recipients from $(SOPS_CONFIG))
	@echo "Encrypting secrets with sops (config: $(SOPS_CONFIG))..."
	@find . \( -path ./.sops-tools -o -path ./.git \) -prune -o -type f \
		\( -name "*.tfvars" -o -name ".env" -o -name ".env.*" \) \
		! -name "*.enc.*" ! -name "*.enc" ! -name ".env.example" -print | while IFS= read -r file; do \
		echo "  -> $$file"; \
		case "$$file" in \
			*.tfvars) $(SOPS) --config $(SOPS_CONFIG) --encrypt "$$file" > "$${file%.tfvars}.enc.tfvars" ;; \
			*)        $(SOPS) --config $(SOPS_CONFIG) --encrypt --input-type binary --output-type json "$$file" > "$$file.enc" ;; \
		esac; \
	done
	@echo "Encryption complete."

sops-decrypt: _sops-require ## decrypt this repo's .enc.tfvars / .env*.enc / *.enc.yaml back to plaintext working files
	@echo "Decrypting secrets with sops..."
	@find . \( -path ./.sops-tools -o -path ./.git \) -prune -o -type f \
		\( -name "*.enc.tfvars" -o -name ".env.enc" -o -name ".env.*.enc" -o -name "*.enc.yaml" \) -print | while IFS= read -r file; do \
		echo "  -> $$file"; \
		case "$$file" in \
			*.enc.tfvars) $(SOPS) --decrypt "$$file" > "$${file%.enc.tfvars}.tfvars" ;; \
			*.enc.yaml)   $(SOPS) --decrypt "$$file" > "$${file%.enc.yaml}.yaml" ;; \
			*.enc)        $(SOPS) --decrypt "$$file" > "$${file%.enc}" ;; \
		esac; \
	done
	@echo "Decryption complete."

sops-update: _sops-require ## rotate recipients on every encrypted file (.enc/.enc.tfvars/.enc.yaml + SOPS_EXTRA_ENC)
	@echo "Updating sops keys on encrypted files..."
	@{ find . \( -path ./.sops-tools -o -path ./.git \) -prune -o -type f \
		\( -name "*.enc.tfvars" -o -name ".env.enc" -o -name ".env.*.enc" -o -name "*.enc.yaml" \) -print; \
		for extra in $(SOPS_EXTRA_ENC); do printf '%s\n' "$$extra"; done; } | sort -u | while IFS= read -r file; do \
		[ -f "$$file" ] || continue; \
		if grep -ql 'ENC\[' "$$file" 2>/dev/null; then \
			echo "  -> $$file"; $(SOPS) updatekeys -y "$$file"; \
		else \
			echo "  -- skip (not sops-encrypted): $$file"; \
		fi; \
	done
	@echo "Key update complete."
