# CLAUDE.md

## Project
- EKS study notes site: MkDocs Material + PyMdown Extensions, GitHub Pages (main branch auto-deploy)
- Weekly EKS curriculum: week1 (Setup), week2 (Networking), week3 (Autoscaling), week4 (Identity & Access)
- Docs in Korean prose with English section headers
- Python tooling: `uv` (not pip) — `uv tool install` / `uvx` for CLI tools; verify PyPI availability first
- Local dev: `mise run build` / `mise run serve`

## Workflow Rules
- Always invoke `write-eks-notes` and `write-markdown` skills before starting document work
- Read ALL related docs in the same directory before making changes, not just one file
- When changing a doc title or structure, also update mkdocs.yml and index.md
- Present all proposed changes as a numbered list for review before applying edits
- Build with `mise run build` to verify after doc edits

## Verification Requirements
- Verify AWS/EKS claims against official docs (AWS Knowledge MCP or WebFetch) before writing
- Never fabricate or assume technical facts — if unsure, say so
- Check official docs for correct YAML syntax, extension configs, and API references

## Critical Thinking
- Do NOT act as a passive parrot — critically evaluate user suggestions too
- When simplifying, preserve essential detail — ask before aggressive removal
- Research MkDocs/pymdown extension approaches in docs BEFORE trying multiple layouts
