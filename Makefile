MODULES := omerta_node omerta_mesh omerta_lang omerta_protocol omerta_infra
REPO_BASE := https://github.com/mjtomei

.PHONY: all update pull-all $(addprefix pull-,$(MODULES))

# Default: clone any module that hasn't been cloned yet
all:
	@for mod in $(MODULES); do \
		if [ ! -d "$$mod/.git" ]; then \
			echo "Cloning $$mod..."; \
			rm -rf "$$mod.tmp"; \
			git clone "$(REPO_BASE)/$$mod" "$$mod.tmp"; \
			mv "$$mod/.commit" "$$mod.tmp/.commit" 2>/dev/null || true; \
			mv "$$mod/REPO.md" "$$mod.tmp/REPO.md" 2>/dev/null || true; \
			rm -rf "$$mod"; \
			mv "$$mod.tmp" "$$mod"; \
		else \
			echo "$$mod already cloned"; \
		fi; \
	done

# Update .commit files to latest remote master SHA and commit
update:
	@changed=0; \
	for mod in $(MODULES); do \
		remote_sha=$$(git ls-remote "$(REPO_BASE)/$$mod" refs/heads/master | cut -f1); \
		if [ -z "$$remote_sha" ]; then \
			echo "WARNING: could not resolve master for $$mod"; \
			continue; \
		fi; \
		current_sha=$$(cat "$$mod/.commit" 2>/dev/null | tr -d '[:space:]'); \
		if [ "$$remote_sha" != "$$current_sha" ]; then \
			echo "$$remote_sha" > "$$mod/.commit"; \
			echo "Updated $$mod: $${current_sha:0:8} -> $${remote_sha:0:8}"; \
			git add -f "$$mod/.commit"; \
			changed=1; \
		else \
			echo "$$mod is up to date ($${current_sha:0:8})"; \
		fi; \
	done; \
	if [ $$changed -eq 1 ]; then \
		git commit -m "Update .commit hashes to latest master"; \
	else \
		echo "All .commit files are current"; \
	fi

# Pull individual modules
$(addprefix pull-,$(MODULES)):
	@mod=$(subst pull-,,$@); \
	if [ -d "$$mod/.git" ]; then \
		git -C "$$mod" pull origin master; \
	else \
		echo "$$mod not cloned yet — run 'make' first"; \
	fi

# Pull all modules
pull-all: $(addprefix pull-,$(MODULES))
