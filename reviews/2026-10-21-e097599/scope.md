# Review run 2026-10-21-e097599: scope

## User request

The user asked Claude to write its independent review under `REVIEW_PROTOCOL.md` into a new
`reviews/` run folder ("do it", 21 October 2026, in reply to Claude's offer to do so).

## Scope

Both projects under `Projects/` (`ProjectManufacturingCell2026`, `ProjectRobot2026`):
P models and monitors (`Common/`, `PSrc/`, `PSpec/`, `PTst/`), PObserve packages (parsers,
JUnit tests, build and run scripts), sample logs and the log simulator, and the documentation
(`SPECIFICATION.md`, `ASSIGNMENT.md`, `INSTRUCTIONS.md`, `README.md`), assessed for
correctness, documentation consistency, reproducibility and suitability for graduate coursework.

Exclusions: `P-Tutorial/`; the GitHub Pages copies under `docs/` beyond a byte comparison with
`Projects/*/SPECIFICATION.html`; the Claude Docs source documents; writing style.

Acceptance criteria for a finding: a file and line reference verified at the snapshot, a
concrete claim, evidence with its status (observed, inferred or untested), and a check that would
demonstrate resolution.

## Snapshot

- Commit: `e097599c3c21b3c7f27ea0fa4a2efeab38ddf6f7` (branch `main`, merge of PR #24).
- Working-tree changes affecting the review: none in the cloud clone. The user's local clone at the
  same commit has three untracked files, `AGENTS.md`, `CLAUDE.md` and `REVIEW_PROTOCOL.md`; they
  govern the review process and do not affect project content.
- Review artifacts under `reviews/` are excluded from the snapshot.

## Reviewer and tools

- Reviewer: Claude (model configured as `claude-opus-5-5`), invoked in a Claude Code cloud session.
- Available: Python 3.13.16, OpenJDK 21.0.12.1, Gradle and Maven binaries, git 2.43.0.
- Not available: the P toolchain and .NET SDK. Network access to NuGet, the .NET download hosts,
  Maven Central and the Gradle plugin portal was refused by the session's network allowlist (HTTP
  status 000 for each host), so neither P nor the PObserve dependencies could be installed. The
  shell on the user's linked computer (an aarch64 Linux VM) has Java but no P or .NET.
- Consequently no `p compile`, `p check`, Gradle build, JUnit or PObserve run was performed in
  this review. Results labelled "mirror" come from an independent Python transcription of the P
  monitors (`evidence/mirror.py`) and are not P or PObserve results.

## Independence statement

Codex's review of an earlier snapshot (`reviews/evaluation-2026-10-21/codex-review.md`, snapshot
`d315bdc`) was read by Claude **before** this review was written, and Claude implemented its
findings CX-001 to CX-003 in PR #24. This review is therefore not independent of that earlier
review. Codex has not reviewed snapshot `e097599`; no Codex position on this snapshot exists, and
none is represented here.

## Exchange

Maximum three exchange rounds. The exchange can start only after Codex writes
`codex-review.md` for this snapshot in this folder.
