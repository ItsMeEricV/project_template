# MEMORY.md: The AI Journal

This file is the "journal" of the project and is **always AI-maintained**. It is NOT for humans to edit manually.

## Purpose
This document captures the non-obvious: bugs, quirks, gotchas, and patterns discovered during development. It exists to prevent the AI from repeating mistakes, struggling with known environment issues, or violating established project conventions.

---

## Project Context & Quirks

- **Naming Convention:** The project has transitioned from `camelCase` to `snake_case` for all file names and database fields. Ensure all new contributions adhere to `snake_case`.
- **Database Access:** The staging database is not directly accessible. It requires a specific SSH tunnel to be established before running any migrations or seeding scripts.

---

## Lessons Learned & Edge Cases

### Prisma / Database
- **Prisma Edge Case (Fixed):** Encountered a weird edge case where composite unique constraints on optional fields were not being correctly handled during `upsert` operations. 
    - **Discovery:** Prisma would fail to find the record if one of the optional fields in the unique constraint was `null`.
    - **Solution:** Always explicitly check for the record existence or ensure that fields used in unique constraints are either required or handled with a fallback value during the application layer logic.

### Infrastructure & Environment
- **SSH Tunneling:** When connecting to the staging environment, use the internal bastion host. Standard connection strings will fail with a timeout if the tunnel is not active on port `5433`.
