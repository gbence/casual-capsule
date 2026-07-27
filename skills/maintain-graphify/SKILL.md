---
name: maintain-graphify
description: >-
  Keep Graphify knowledge graphs current during Capsule development. Use for
  non-trivial codebase exploration, impact analysis, implementation, reviews,
  multi-file edits, refactors, file or symbol deletions, configuration and
  documentation changes, stale graphify-out artifacts, and decisions about
  Graphify watch, hooks, incremental updates, or forced rebuilds.
---

# Maintain Graphify

Use the installed `graphify` skill as the source of truth for extraction,
query, update, and export procedures. Add lifecycle decisions around it so the
graph stays useful without rewriting project instructions or hiding risky
rebuilds.

## Start a codebase task

1. Find the repository root with `git rev-parse --show-toplevel`. If the
   directory is not a Git repository, use the explicit workspace root.
2. Record the initial `git status --short`. Preserve unrelated user changes.
3. If `graphify` is unavailable, continue the task and report that graph
   maintenance was skipped.
4. If `graphify-out/graph.json` exists:
   - Run `graphify reflect --if-stale`.
   - Read `graphify-out/reflections/LESSONS.md` when it exists.
   - Query or traverse the graph before broad source reads.
5. If no graph exists, bootstrap it only when the task spans several files,
   asks about architecture or impact, or will materially change structure.
   Follow the installed `graphify` skill's full-build flow. For a code-only
   headless build, use `graphify extract ROOT --code-only`.

Do not build a graph for a trivial, isolated edit when direct inspection is
clearer.

## Plan changes with the graph

Use the smallest fitting operation:

- `graphify query` for broad context and neighboring concepts.
- `graphify explain` for one symbol or component.
- `graphify path` for a dependency or data-flow chain.
- `graphify affected` before changing a shared symbol or interface.
- `graphify god-nodes` to identify central refactor risks.

Follow the vocabulary-expansion and evidence rules in the installed
`graphify` skill. Never invent an edge or present an inferred edge as source
fact.

## Maintain the graph after changes

Track only files changed for the current task. Do not absorb unrelated dirty
worktree changes into maintenance decisions.

### Code changes

If a graph already exists, run:

```bash
graphify update ROOT
```

Current Graphify versions prune deleted files and removed symbols when the
loss is explained by the changed sources. Run the multigraph diagnostic after
the update:

```bash
graphify diagnose multigraph \
  --graph ROOT/graphify-out/graph.json
```

### Documentation, configuration, image, or paper changes

The direct `graphify update` command updates the structural code graph only.
Use the installed `graphify` skill's incremental semantic-update flow for
Markdown, YAML, Compose, CI, images, papers, and similar inputs.

If semantic extraction cannot run, preserve the existing graph, write or keep
the `graphify-out/needs_update` marker, and tell the user what remains stale.

### Deletions and intentional graph shrinkage

First run a normal update. If it refuses to overwrite a smaller graph:

1. Inspect the exact deleted and modified paths.
2. Confirm the missing nodes come only from files or symbols intentionally
   removed by the current task.
3. Confirm semantic extraction did not fail or omit an unrelated chunk.
4. Only then run:

```bash
graphify update ROOT --force
```

Never use `--force` merely to silence a shrink warning. Do not force a rebuild
when unrelated user deletions or extraction failures could explain the loss.

## Use watch and hooks deliberately

For a long, multi-wave editing session, use `graphify watch ROOT` when the
watch extra is installed and the watcher can stay attached to a controlled
terminal. Stop it when the session ends. Code changes rebuild automatically;
non-code changes still require semantic extraction.

Install repository hooks only when the user requests persistent commit and
checkout automation. Before `graphify hook install`, explain that Graphify
also writes a merge-driver entry to `.gitattributes`; preserve any existing
hooks and show the resulting diff.

Do not run project integration installers such as `graphify codex install`
implicitly. They modify tracked instruction files. The globally synchronized
skills already provide Capsule-wide behavior.

## Finish the task

1. Surface graph-health warnings instead of hiding them.
2. If the graph materially informed the result, save the useful, dead-end, or
   corrected outcome with `graphify save-result`.
3. Report whether the graph was built, updated, left unchanged, or marked for
   semantic refresh.
4. Keep `graphify-out/` as derived output unless the project explicitly tracks
   it.
