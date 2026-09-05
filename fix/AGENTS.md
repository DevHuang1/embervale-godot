# Agent Instructions — Embervale Fix Queue

Read this before touching any fix file or source file.

## Who should read this

Any AI agent, LLM, or automated tool that has been handed this repository and
asked to apply bug fixes.

## Golden rules

1. **Read the fix file in full before writing any code.** Each fix file
   contains the exact file path, line numbers, root cause, and a precise
   diff-style patch. Do not guess or infer.

2. **Do not modify any file outside `fix/`.** The source files listed in each
   fix are the only targets. Do not refactor, rename, or reformat anything
   else.

3. **Apply fixes one at a time.** Commit each fix separately with the commit
   message format:  
   `fix: <FIX-N slug> — <one line from the fix file>`  
   Example: `fix: FIX-1 rig-loader-fbx — add .fbx fallback, guard set_visual_root`

4. **Do not invent solutions.** If the fix file says "replace line X with Y",
   do that exactly. If you disagree, add a comment to the fix file — do not
   silently deviate.

5. **Mark the fix as done.** After applying and committing a fix, update the
   checkbox in `fix/README.md`:  
   `- [x] FIX-N applied`

6. **Do not delete fix files** until a human developer confirms the fix is
   working in Godot.

## How fix files are structured

Each fix file contains:

```
## File
Path to the source file(s) to edit.

## Location
Line numbers or function names.

## Root cause
Explanation of why it breaks.

## Exact fix
A diff or replacement block. Apply it verbatim.

## Verification
How to confirm the fix works (Godot output, test name, etc.).
```

## Branch strategy

Create a branch `fix/FIX-N-slug` for each fix, or apply all fixes to a single
`fix/all-runtime-errors` branch. Do not push to `main` until reviewed.

## Questions / blockers

If a fix file is ambiguous or the line numbers have shifted, add a `## Blocker`
section to the fix file and stop. Do not guess. A human or the authoring AI
should clarify before you proceed.
