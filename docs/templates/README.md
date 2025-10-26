# Project Templates

This directory contains reusable templates for setting up future projects.

## Available Templates

### 1. `coding-rules-template.md`
**Purpose**: Standard coding principles and style guidelines

**Contains**:
- Fundamental development principles (NO HARDCODING, ROOT CAUSE fixes, etc.)
- Code quality standards
- Environment and security best practices
- Terraform code style guidelines

**How to use**: Copy into new project's `CLAUDE.md` under "Coding Standards & Principles" section

---

### 2. `error-rules-template.md`
**Purpose**: Error handling workflow and documentation standards

**Contains**:
- Rules for accessing and updating errorlog.md
- Process for documenting errors and solutions

**How to use**: Copy into new project's `CLAUDE.md` under "Error Handling" section, then create an `errorlog.md` file

---

## Important Notes

⚠️ **These templates use `inclusion: always` frontmatter, which does NOT work in `docs/` directories.**

Claude Code only processes frontmatter in:
- `.claudecontext` files (in `.claude/` directory)
- Project root `CLAUDE.md` file

**For active use**: Copy template content into your project's `CLAUDE.md` file.

---

## Template Usage Workflow

1. **Start new project**
2. **Copy relevant template content** into new project's `CLAUDE.md`
3. **Customize rules** based on project tech stack and requirements
4. **Remove or modify** rules that don't apply
5. **Create supporting files** (like `errorlog.md` if using error-rules template)

---

## Related Files in AI-DP Project

For examples of how these templates are used in practice, see:
- [`CLAUDE.md`](../../CLAUDE.md) - Active project configuration with error handling rules
- [`docs/errorlog.md`](../errorlog.md) - Active error log tracking errors encountered in this project
- [`.claude/agents/portfolio.md`](../../.claude/agents/portfolio.md) - Portfolio implementation agent

---

**Last Updated**: 2025-10-23
