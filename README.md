# Markdown Template for a New Project

This is a collection of foundation markdown `.md` files to describe a project. These serve as the "Source of Truth" for both human developers and AI agents.

## The Core Files

1. **`SPEC.md`**: **The "What."** Product requirements, user stories, and milestones.
2. **`ARCHITECTURE.md`**: **The "Where."** Tech stack, directory structure, and system flow.
3. **`AGENTS.md`**: **The "How" and "Who."** Personas, boundaries, and engineering standards.
4. **`MEMORY.md`**: **The "Journal."** An AI-maintained record of quirks, bugs, and patterns. It prevents repeating past mistakes and captures non-obvious context.
5. **`IMPLEMENTATION_PLAN.md`**: **The "When."** A living document for task tracking and inter-agent communication/handovers.

## How to use this Template
1. **Copy** these files to the root of your new project.
2. **Edit `SPEC.md`** first to define the problem and requirements.
3. **Refine `ARCHITECTURE.md`** to lock in your tech stack and folder structure.
4. **Update `AGENTS.md`** with project-specific personas and "Hard Refusal" anti-patterns.
5. **Initialize `MEMORY.md`** (or let the AI do it) to start capturing project context.
6. **Create `IMPLEMENTATION_PLAN.md`** as you begin the execution phase.

## The Philosophy
Documentation is code. If an LLM or a new developer cannot understand the project's intent and constraints by reading these files, the project is under-documented.

- **`AGENTS.md`** ensures everyone knows their role and the rules of engagement.
- **`MEMORY.md`** ensures that the "hard-earned" context isn't lost between sessions.
- **`IMPLEMENTATION_PLAN.md`** ensures that complex tasks are broken down and dependencies are respected.

Use the "Good/Bad" examples within the template as a guide for your own documentation.
