# AGENTS.md: Rules of Engagement

This document defines the **"How"** and the **"Who."** It acts as the system prompt extension for AI agents and the style guide for humans.

## 1. AI Assistant Hook
*Purpose: This is the first thing an LLM reads. It tells the agent how to process the rest of the project files.*

### Good Hook Example
"Before starting, identify your persona. If you are Gemini, acknowledge these rules by summarizing the [Tech Stack] from ARCHITECTURE.md before starting a task. If you are Claude, adhere to these as your 'System Prompt' extension."
*Why: It forces the agent to prove it has read the context before writing code.*

### Bad Hook Example
"Please help me code this project."
*Why: Too vague; doesn't provide a protocol for context validation.*

---

## 2. Personas & Boundaries
*Purpose: Define specific roles to prevent 'context bleed' (e.g., a frontend agent accidentally modifying database schemas).*

### How to define a Persona:
Each persona should have:
- **Domain:** The specific languages/frameworks (e.g., Swift, TypeScript).
- **Boundary:** What they are **strictly forbidden** from touching.
- **Success Metric:** A measurable outcome (e.g., "Zero accessibility violations").

### Good Persona Example
**Persona: [Staff Backend Architect]**
- **Domain:** Node.js, Next.js Server Actions, PostgreSQL.
- **Responsibilities:** Schema design, API contracts, and server-side logic.
- **Boundary:** Strictly backend structure. Does not touch `.swift` files or frontend CSS/Tailwind presentation logic.
- **Success Metric:** Sub-100ms API response times.

### Bad Persona Example
**Persona: [Fullstack Developer]**
- **Responsibilities:** Writes code and fixes bugs across the whole stack.
*Why: No boundaries. The AI will try to do everything, leading to architectural drift and logic fragmentation.*

---

## 3. Engineering Standards (The "DOs")
*Purpose: High-level technical mandates that apply to everyone.*

### Examples of Good Standards
- **i18n:** "Never hardcode strings; use `t('key')` for all UI text."
- **Testing:** "All new logic requires a corresponding `.test.ts` file."
- **Git:** "Use prefixes: `Feature:`, `Fix:`, `Chore:`."

### Examples of Bad Standards
- "Write clean code." (Subjective)
- "Test your work." (Not specific on framework or naming conventions)

---

## 4. Anti-Patterns (The "DO NOTs")
*Purpose: Explicit 'Hard Refusals' for the AI. This is the most powerful section for preventing common AI mistakes.*

### Examples of Good Constraints
- **Naming:** "Never use `.spec.ts`; only use `.test.ts`."
- **Types:** "No use of `any` or `@ts-ignore`."
- **UI:** "No inline styles; use Tailwind classes only."

### Examples of Bad Constraints
- "Don't make bugs." (Impossible to follow)
- "Avoid complex logic." (Subjective)

---

## 5. Workflow & Validation
*Purpose: Define how a task is considered "Done."*

### Good Example
"A task is complete only when: 1. Linting passes, 2. Tests pass, 3. The change is verified in the browser/emulator."

### Bad Example
"Tell me when you are finished."
