# Aurora – Claude Code Project Contract

You are Claude running in **Claude Code** on this repository.

Your job is to implement and evolve the **Aurora V0 HTTP backend framework in D**, milestone by milestone, with a strong focus on:

- **Correctness & reliability** (tests first, no broken builds)
- **Performance constraints** from the spec
- **Stable project docs** that stay in sync with the code:
  - `docs/implementation_plan.md`
  - `docs/specs.md`
  - `docs/task.md`
  - `docs/walkthrough.md`

This project previously ran inside Antigravity.  
The current `docs/task.md` and `docs/walkthrough.md` are **imports from Antigravity** and must be preserved and extended, **not replaced**.

---

## 0. Sources of Truth

Always treat these files as your primary sources of truth:

- **Specs:**  
  `docs/specs.md`  
  → Full Aurora V0 Core spec (architecture, performance targets, modules).

- **Global implementation plan:**  
  `docs/implementation_plan.md`  
  → Milestones, components, test targets, coverage, performance goals.

- **Milestone task list (living):**  
  `docs/task.md`  
  → Current milestone breakdown and status, imported from Antigravity and then updated by you.

- **Milestone walkthrough (living):**  
  `docs/walkthrough.md`  
  → Narrative log of what has been done so far (also imported from Antigravity and then updated by you).

Do **not** ask the user to paste these files. Read them directly from disk when needed.

---

## 1. Current Milestone Context (M2)

You are currently working on **Milestone 2: Core Runtime / HTTP layer**, whose goal is:

> Build the HTTP/1.1 server runtime with Wire integration and the surrounding runtime (workers, reactor, connection management, etc.)

From `docs/task.md` (imported from Antigravity):

- Milestone 1 is complete (schema, mem pools, logging, metrics, config).
- Milestone 2 components include:
  - HTTP Parsing (Wire integration)
  - Worker Threads
  - Event Loop (Reactor)
  - Connection Management
- Current status:
  - HTTP tests have been created (17 test cases).
  - HTTP layer partially implemented.
  - **Current blocker:** Wire library linking / build integration.

Your job is to continue this milestone **from the current state**:
- Finish HTTP parsing / Wire integration.
- Then implement the other M2 components (workers, reactor, connection management).
- Keep `docs/task.md` and `docs/walkthrough.md` in sync as you go.

---

## 2. Tools & Environment

You have access to:

- **File editing**: read/modify files in this repo.
- **Shell / Bash**: to run commands like:

  - Build (unittest config):
    ```bash
    dub build --config=unittest --force 2>&1 | tail -n 60
    ```

  - Run the unittest binary (assuming it builds `./aurora` in the repo root):
    ```bash
    ./aurora 2>&1 | tail -n 80
    ```

  - Other variants: `dub test`, `dub build`, etc. when appropriate.

- **Sequential-thinking MCP**:  
  Use it for **structured, staged reasoning** when you:
  - break down a complex milestone task,
  - need deeper analysis on architecture / design,
  - are stuck on a tricky bug or tradeoff.

Follow Anthropic’s best practices for Claude Code:
- **Plan, then execute**: first make a short plan, then edit files and run tools.
- Prefer small, incremental edits + frequent tests over huge rewrites.

---

## 3. Reasoning Levels (think / deep think / ultra-think)

You should **always think** before editing, but with different levels:

### Level 1 – Normal think (default)
Use for **simple / local** changes:
- small refactors,
- obvious compile fixes,
- straightforward test additions.

Behavior:
- Make a short 2–5 bullet plan in the chat.
- Keep internal reasoning minimal.
- Don’t call sequential-thinking MCP for trivial tasks.

### Level 2 – “Deep think step-by-step”
Use for **non-trivial, multi-step coding tasks**, e.g.:

- Implementing a new module from the spec.
- Wiring together multiple components (e.g. HTTP parsing + connection state machine).
- Designing the shape of a struct / API that will be widely used.

Behavior:
- Before coding, explicitly say you’ll **“deep think step-by-step about this task”**.
- Use a concise, structured plan (3–7 steps).
- Optionally call the **sequential-thinking MCP** once for a more structured breakdown (analysis → plan → checks).
- Aim for ~10% more thoroughness than the bare minimum (check edge cases, error paths, integration with tests), but:
  - keep explanations in the chat concise and focused.

### Level 3 – “Ultra-think” (rare, high-cost)
Use **only** when:

- You are facing a **complex architectural decision** (worker threading model vs reactor integration vs NUMA).
- You are diagnosing a **nasty bug** (race condition, deadlock, weird perf regression) where normal reasoning failed.
- You need to reconcile conflicting requirements in the spec.

Behavior:
- Announce that you will **“ultra-think step-by-step”** for this specific decision.
- Use **sequential-thinking MCP** to:
  - enumerate assumptions,
  - explore alternatives,
  - compare tradeoffs,
  - reach a clear conclusion.
- Keep this level **rare** and targeted: it is intentionally more expensive. Use it only when the extra ~10–20% reasoning is clearly justified.

Even when you deep-think or ultra-think, keep the *visible output* focused and compact:
- Show plans and conclusions.
- Avoid dumping long, redundant paragraphs.
- Summarize logs and diffs instead of copying everything.

---

## 4. Milestone 2 Loop: Tasks + Walkthrough Auto-Maintenance

For **any work related to Milestone 2**, follow this loop:

### Step 1 – Align with specs & global plan
1. Read or re-read, as needed:
   - `docs/specs.md`
   - `docs/implementation_plan.md`
2. Use them as the **global constraints**:
   - Architecture layering,
   - Performance targets (no GC on hot paths, zero-copy, etc.),
   - Module boundaries (aurora.runtime.*, aurora.net.*, aurora.ext.*, etc.).

Do **not** ask the user to restate the spec or plan. They are all in these files.

### Step 2 – Read and update the task list (`docs/task.md`)
1. Read `docs/task.md`.
2. **Never wipe or discard** the existing content (imported from Antigravity).
3. When you start a new “session” of work on M2:
   - Identify the **next open task** or sub-task based on this file.
   - If needed, refine the task list:
     - add new bullets / sub-tasks under existing components,
     - annotate tasks with “In progress” or mark them as `[x]` when done.
4. For selecting & refining tasks:
   - Use **deep think** (Level 2) and, if appropriate, **sequential-thinking MCP** to break a big item (e.g. “Connection Management”) into concrete steps.

Keep `docs/task.md` as a **compact, structured checklist**, not a novel.

### Step 3 – Work on one task at a time (TDD loop)

For the active task:

1. **Plan briefly (in chat)**  
   - In 3–7 bullets, outline:
     - what files you will touch,
     - what tests you will add/modify,
     - how this ties back to `docs/task.md`.

2. **Tests first or test refresh**
   - If tests for this area already exist:
     - run them with:
       ```bash
       dub build --config=unittest --force 2>&1 | tail -n 60
       ./aurora 2>&1 | tail -n 80
       ```
       or use `dub test` if more appropriate.
     - inspect failures.
   - If there are no tests yet:
     - create or update tests under `tests/` (unit/integration) to specify the behavior you want, based on the spec and implementation plan.

3. **Implement / modify code**
   - Make small, focused edits.
   - Respect constraints from the spec:
     - No GC or allocations in the core HTTP hot path.
     - Use buffer pools, arenas and thread-local structures according to the V0 design.
   - Use idiomatic D and keep the design testable.

4. **Run tests frequently**
   - Re-run the same commands:
     ```bash
     dub build --config=unittest --force 2>&1 | tail -n 60
     ./aurora 2>&1 | tail -n 80
     ```
     or the relevant `dub test` variant.
   - When failures occur:
     - **deep think step-by-step** about the error,
     - explain briefly in chat:
       - root cause,
       - targeted fix,
       - why it doesn’t violate the spec.
   - Repeat until:
     - all tests related to this task pass, and
     - the whole test suite is in a consistent state (no new regressions).

### Step 4 – Update `docs/task.md` (task list)

When a task or sub-task is substantially complete:

- Open `docs/task.md` and:
  - mark the corresponding item as done (`[x]` instead of `[ ]`), or update its status line,
  - optionally add 1–3 short bullet notes under it (deviations, decisions, links to key tests).

Do not remove historical information about Milestone 1 or earlier notes.

### Step 5 – Update `docs/walkthrough.md` (development log)

For each **non-trivial** completed step (e.g. “HTTP parser integration with Wire”, “initial worker threads lifecycle”, “connection state machine basic implementation”):

1. Append a new section to `docs/walkthrough.md`.  
   Keep the existing content from Antigravity as is; only **add** to it.

2. Follow this minimal format:

   ```markdown
   ## [M2-XXX] <short title>
   - Date: YYYY-MM-DD
   - Task reference: <short label or excerpt from docs/task.md>
   - Files touched:
     - `path/to/file1.d`
     - `path/to/file2.d`
   - What was done:
     - bullet 1
     - bullet 2
     - bullet 3 (max ~7 bullets)
   - Tests run:
     - `dub build --config=unittest --force`
     - `./aurora`
     - and any specific configs if used
   - Notes:
     - important decisions / tradeoffs
     - known TODOs or follow-ups for this area

	3.	Continue the [M2-XXX] numbering based on the last ID present in the existing docs/walkthrough.md (imported from Antigravity). Never restart from [M2-001].

The walkthrough should be:
	•	Accurate (reflect real code & tests),
	•	Short and structured (easy to skim),
	•	Sufficient to reconstruct what happened in M2.

### Step 6 – Summarize to the user

After finishing work on a task (or a natural chunk of work):
	•	Reply in chat with a short summary:
	•	which task(s) in docs/task.md you advanced or completed,
	•	the key files you changed,
	•	the dub build/./aurora or dub test results,
	•	which walkthrough entry [M2-XXX] you added.

Do not paste entire files or full logs unless strictly necessary.

---

## 5. Special Handling: Wire / HTTP Parsing Blocker

From the current docs/walkthrough.md state:
	•	HTTP tests (17 cases) are written but blocked by Wire library linking.
	•	Wire is located at something like: …/federicofilippi/Desktop/D/Wire.
	•	Options mentioned:
	•	compile Wire and link as a library,
	•	hook Wire build into dub.json,
	•	or use Wire as a DUB package directly.

When you work on HTTP parsing:
	1.	Treat Wire build/linking as a first-class sub-task in docs/task.md.
	2.	Use deep think step-by-step (and, if helpful, sequential-thinking MCP) to choose the best integration route given the project context (D, dub, reproducibility).
	3.	Implement the integration solution.
	4.	Document in:
	•	docs/task.md (checked task + note),
	•	docs/walkthrough.md (step describing what you did and why).

---

## 6. Token & Context Discipline

To keep context and cost under control:
•	Do not paste full contents of large files in the chat if not needed.
	•	Use small snippets and concise descriptions.
•	Do not paste full dub build / ./aurora logs unless:
	•	parsing errors are unclear, or
	•	a specific error is important to show.
  Instead:
    •	quote only the relevant lines,
    •	summarize the rest.
•	When referring to spec or plan:
	•	mention the section or heading,
	•	but do not re-copy the entire document.

Your visible output should be technical, compact, and focused, even when you’re deep-thinking internally.

---

## 7. Things to Avoid
•	Do not:
	•	silently modify tests just to “make them pass” if they encode a valid requirement from the spec/plan.
	•	introduce GC allocations into hot paths where the spec requires @nogc and zero allocations.
	•	ignore performance and architecture constraints from docs/specs.md and docs/implementation_plan.md.
•	If you genuinely believe:
	•	a test is wrong, or
	•	the spec and current implementation are inconsistent,
  then:
    •	explain the inconsistency in the chat,
    •	propose a minimal change,
    •	and reflect the decision in docs/task.md and docs/walkthrough.md.

---

By following this contract, you should:
	•	reason slightly more thoroughly than the bare minimum (≈ +10% internal reasoning),
	•	keep the project’s spec, plan, tasks, walkthrough, and code in sync,
	•	and converge reliably on a correct, well-tested Aurora Milestone 2 implementation.