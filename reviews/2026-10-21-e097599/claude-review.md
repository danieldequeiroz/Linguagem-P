# Claude review of snapshot e097599

Run: `2026-10-21-e097599` (see `scope.md`). Reviewer: Claude. Snapshot:
`e097599c3c21b3c7f27ea0fa4a2efeab38ddf6f7`, branch `main`.

Line references were checked against the snapshot. Paths are relative to `Projects/`;
`Cell` = `ProjectManufacturingCell2026`, `Fleet` = `ProjectRobot2026`. `Common/*.p` is identical
in both projects except for the experiment number in two comments (E8 in Cell, E9 in Fleet).

## Summary

The regulation designs are sound as modelled: on reading, the two-phase guard
(`Common/ResourceGuard.p`) keeps an affected resource closed from prepare to commit, which is what
S1 and S2 require, and the Codex P runs of 21 October (earlier snapshot) are consistent with that.
The sample logs are reproducible byte for byte, and an independent Python transcription of the
monitors agrees with every row of the documented expected results.

The findings concern what students are told to expect. Three of them affect experiments directly:
the newly added L3 monitor is documented as checked but is not asserted by any test (CL-001); the
two-technician experiment predicts an S1 failure that S1, as written, does not detect on the
described trace (CL-002); and the abort experiment interacts with L2 and R2 in ways the
documentation does not predict (CL-003). The remaining findings are low severity.

No P, PObserve or Gradle command was run in this review (see `scope.md`). Every statement about P
behaviour below is therefore inferred from the source and from P's documented semantics unless it
cites the Codex evidence of the earlier snapshot.

## Checks performed

| Check | Environment | Result | Evidence |
|---|---|---|---|
| Regenerate the four sample logs with `tools/simulate_logs.py` (cell and fleet; twophase seed 1, naive seed 2; 60 ticks) and compare with the committed logs | Python 3.13.16 | all four identical (`cmp`), SHA-256 equal | `evidence/regenerated-sample-logs.sha256`, `evidence/committed-sample-logs.sha256` |
| Independent transcription of S1–S3, L1–L3, R1–R3 and F1 into Python, written from `Common/Specs.p`, `Common/RuntimeSpecs.p` and `Fleet/MobileRobots/PSpec/FleetSpecs.p` without reusing the simulator's checker or Codex's `verify_samples.py`; run on the four sample logs | Python 3.13.16 | matches `Cell/ManufacturingCell/INSTRUCTIONS.md` 3.4 and `Fleet/MobileRobots/INSTRUCTIONS.md` 3.4 row by row (first-violation messages and ticks) | `evidence/mirror.py`, `evidence/mirror-output.txt` |
| Same transcription on three hand-written traces: start–abort–restart–commit, start–abort, two technicians | Python 3.13.16 | see CL-002 and CL-003 | `evidence/abort_retry.log`, `evidence/abort_noretry.log`, `evidence/e4_two_technicians.log` |
| Byte comparison of `docs/projects/*/index.html` with `Projects/*/SPECIFICATION.html` | `cmp` | identical | — |
| Source reading of all `.p`, parser, test, build and run files | — | findings below | — |

Not performed: `p compile`, `p check`, `p compile --mode pobserve`, Gradle build, JUnit, PObserve
CLI. The mirror models two P semantics that matter here (an observed event without a handler in
the current state is an error; reading a missing map key is an error); its agreement with P is
itself untested.

## Findings

### CL-001 · L3 is documented as checked, but no test case asserts it

- Severity: medium.
- Files: `Common/Specs.p:112–130` (monitor `AdaptationTerminates`);
  `Cell/ManufacturingCell/PTst/TestScript.p:10–12, 19–21`; `Fleet/MobileRobots/PTst/TestScript.p:10–12, 19–21`
  (assert lists name S1–S3, L1, L2 and R3 only); `Fleet/ASSIGNMENT.md:35` and
  `Fleet/SPECIFICATION.md:1051` (E1: "S1–S3, L1–L3 and R3 hold"); `Fleet/SPECIFICATION.md:1038`
  and `Cell/SPECIFICATION.md:922` (L3 "holds / holds"); `Fleet/SPECIFICATION.md:1130` (L3 checked by
  `tcFleetTwoPhase`).
- Claim evaluated: the documentation states that L3 is checked in the baseline test cases.
- Evidence: `p check -tc tcFleetTwoPhase` checks only the monitors listed after `assert`;
  `AdaptationTerminates` is not listed in any `test` declaration. The monitor was also added after
  the last compilation (`Fleet/README.md:42, 48`), so it has not been compiled.
- Consequence: an E1 run reported as "L1–L3 hold" contains no L3 evidence; a student who writes the
  E8/E9 abort has no test case that exercises L3.
- Correction: add `AdaptationTerminates` to the assert lists of the two-phase and naive test cases
  in both projects (it should hold in both, since the starter coordinator always commits), then
  compile and check; or narrow the documentation to "L3 is defined for E8/E9".
- Evidence status: observed (source); P behaviour of uncompiled L3 untested.
- Acceptance check: `p compile` succeeds; `p check -tc tcCellTwoPhase` and
  `p check -tc tcFleetTwoPhase` print `AdaptationTerminates` among the checked monitors and find no
  bug.

### CL-002 · The two-technician experiment predicts an S1 failure that S1 does not detect on the described trace

- Severity: medium.
- Files: `Common/Specs.p:12, 24–25, 30–37` (`humanIn` is a `set[int]` of resources;
  `eHumanLeft` removes the resource); `Common/MonitorEvents.p:39–40` (`eHumanEntered`, `eHumanLeft`
  carry only a resource id); `Common/HumanRequester.p:27, 35`;
  `Cell/ManufacturingCell/INSTRUCTIONS.md:136–141` (steps 1–4, "`RegimentationSafety` should
  fail"); `Cell/SPECIFICATION.md:936` (E4: "S1 and S4 fail on reopening"); `Cell/SPECIFICATION.md:919, 987`
  and `Cell/ManufacturingCell/INSTRUCTIONS.md:145` (S4 over `eHumanEntered`, `eHumanLeft`,
  `eNormCommitted`).
- Claim evaluated: in E4, after A leaves and the cell is reopened while B is inside, the admission of
  the arm violates S1.
- Evidence: on the described trace (A enters, B enters, A leaves, v3 reopens, arm admitted), A's
  `eHumanLeft` removes resource 0 from `humanIn` although B is still inside, so S1's assertion at
  `Specs.p:24` holds when the arm enters. The mirror reports no violation from any monitor on this
  trace (`evidence/e4_two_technicians.log`, `evidence/mirror-output.txt`). S1 can still fail on
  other interleavings of E4, e.g. when B's `eHumanEntered` is announced after A's `eHumanLeft` and
  before the reopening, so the checker may still report an S1 failure, but not by the mechanism the
  instructions describe. The same vocabulary limits S4: with resource-only events, a monitor that
  stores presence as a set cannot express "a person is still inside"; it needs a count per resource
  or a person identifier.
- Consequence: the explanation students are graded on (D2, "interleaving explained") may not match
  the trace the checker produces; a student who writes S4 with a set will obtain a vacuous S4. At run
  time, the same limitation applies to any site with more than one person per resource (several
  pickers in the fleet).
- Correction: count people per resource in S1 (`map[int, int]`, increment on enter, decrement on
  leave) or add a person id to `eHumanEntered`/`eHumanLeft` and the `HUMAN_ENTER`/`HUMAN_LEAVE`
  records; state in INSTRUCTIONS 2.5 that S4 must count people; restate the expected E4 trace.
- Evidence status: observed in the mirror; inferred for P (not run).
- Acceptance check: with a second `HumanRequester`, `p check` finds a counterexample in which the arm
  is admitted after the reopening while B is inside, and the failing monitor is S1 (with counting) or
  S4; the mirror flags `evidence/e4_two_technicians.log`.

### CL-003 · An abort (E8/E9) makes L2 and R2 fail in ways the documentation does not predict

- Severity: medium.
- Files: `Common/Specs.p:98–106` (L2: `InProgress` handles only `eNormCommitted`);
  `Common/RuntimeSpecs.p:47–68` (R2: `InProgress` handles `eTick` and `eNormCommitted`, does not
  observe `eAdaptationAborted`); `Common/AdaptationCoordinator.p:35` (`pending.ver = current.ver + 1`,
  so a retry after an abort reuses the aborted version); `Fleet/ASSIGNMENT.md:43`,
  `Fleet/SPECIFICATION.md:1059`, `Fleet/MobileRobots/INSTRUCTIONS.md:127`,
  `Cell/ManufacturingCell/INSTRUCTIONS.md:132`, `Cell/SPECIFICATION.md:940` ("L2 fails by design").
- Claim evaluated: with an abort, L3 holds and L2 "fails by design"; R2 is not mentioned.
- Evidence (mirror, `evidence/mirror-output.txt`): for start v1 → abort v1 → start v1 → commit v1,
  L2 and R2 both receive `eAdaptationStarted` in `InProgress`, where no handler exists, which P
  reports as an unhandled-event error rather than as a hot-state liveness failure; for start v1 →
  abort v1 with ticks continuing, R2 reports "not committed" after 5 ticks, a bounded-response
  violation for a change that was correctly abandoned. L3 behaves as documented in both traces.
- Consequence: students will see an error message whose cause (unhandled event) differs from the
  predicted one, and PObserve will flag correct aborts through R2. Reusing the version number makes
  `ADAPT_START`/`ADAPT_ABORT`/`COMMIT` records ambiguous in a log.
- Correction: make R2 observe `eAdaptationAborted` (abort returns to `Idle`); state the expected L2
  outcome for both abort-only and abort-and-retry; decide whether a retry reuses or increments the
  version and document it; optionally add an R2-style bounded monitor for L3.
- Evidence status: observed in the mirror; inferred for P (unhandled event in a spec monitor) and
  untested in PObserve.
- Acceptance check: a P probe (as in `reviews/evaluation-2026-10-21/MonitorProbes.p`) announcing
  start–abort–start–commit gives the documented L2 and R2 outcomes; the mirror's `abort_noretry.log`
  passes R2 after the correction.

### CL-004 · Statements that P results have not been obtained contradict the recorded evidence

- Severity: low.
- Files: `Fleet/MobileRobots/INSTRUCTIONS.md:107` and `Cell/ManufacturingCell/INSTRUCTIONS.md:106`
  ("Expected results (hypotheses, not yet run)"); `Fleet/MobileRobots/INSTRUCTIONS.md:214`
  ("neither has been confirmed with P tools yet"); `Fleet/MobileRobots/PSpec/FleetSpecs.p:29`
  ("not yet run").
- Evidence: the validation record in the same files (`Fleet/MobileRobots/INSTRUCTIONS.md`, section 5)
  and `Fleet/README.md:42` record first-schedule results for all three test cases (F1 fails on
  schedule 1 as intended).
- Correction: replace with "first schedules observed in the independent evaluation (section 5);
  acceptance runs to do".
- Evidence status: observed.
- Acceptance check: `grep -n "not yet run\|neither has been confirmed"` returns only rows of the
  validation record that are genuinely not run.

### CL-005 · Cell sample logs contain `ABANDON` records that the cell parser silently drops

- Severity: low.
- Files: `Cell/tools/simulate_logs.py:209` (emits `ABANDON` in the cell scenario);
  `Cell/ManufacturingCell/pobserve/src/test/resources/cell_twophase.log:9, 22, 93` (6 records; 2 in
  `cell_naive.log`); `Cell/ManufacturingCell/pobserve/src/main/java/regulation/cell/parser/CellRegulationParser.java:87–88`
  (unknown events return `null`).
- Evidence: the cell project has no `eTaskAbandoned` event or fairness monitor, and the cell
  INSTRUCTIONS do not mention `ABANDON`. The mirror's F1 flags candidate unfair sanctions in both
  cell logs (`evidence/mirror-output.txt`), which shows the data for a cell fairness analysis is
  already present.
- Consequence: harmless for the shipped monitors, but a reader of the logs meets an undocumented
  record type; a fairness question for the cell is left implicit.
- Correction: either document `ABANDON` in the cell log-format table as "ignored by the cell
  parser", or stop emitting it for the cell scenario, or offer the cell fairness monitor as an
  optional experiment.
- Evidence status: observed.
- Acceptance check: the cell log-format table lists every event type present in the cell sample logs.

### CL-006 · `run_pobserve.sh` reports any failure as a monitor violation

- Severity: low.
- Files: `Cell/ManufacturingCell/pobserve/run_pobserve.sh:29, 40` and the same lines in
  `Fleet/MobileRobots/pobserve/run_pobserve.sh`.
- Evidence: line 40 prints "reported a violation" for any non-zero exit of the PObserve CLI,
  including a wrong jar path, a missing spec name or a parser exception (`num()` throws on a missing
  field). Line 29 calls `./gradlew`, which exists only after `gradle wrapper` (INSTRUCTIONS step 3.2);
  the script does not say so.
- Consequence: a tool or configuration failure can be recorded as a regulation violation in the
  validation record.
- Correction: distinguish the CLI's violation exit status (or the presence of a violation report in
  `pobserve-out/<Spec>/`) from other failures; check for `./gradlew` and print the setup hint.
- Evidence status: observed (script); PObserve exit codes untested.
- Acceptance check: running the script with a misspelled spec name prints an error that is not
  "reported a violation".

### CL-007 · The log-assumption table describes a missing `ENTER` inaccurately

- Severity: low.
- Files: `Cell/ManufacturingCell/INSTRUCTIONS.md:295`, `Fleet/MobileRobots/INSTRUCTIONS.md:253`
  ("occupancy goes negative and hides real capacity violations"); `Common/Specs.p:27–29`.
- Evidence: `occupancy[l.res]` is read without a key check. If no `ENTER` for that resource has been
  seen, the key is absent and P raises a map-access error instead of decrementing; the occupancy
  goes negative only if an earlier `ENTER` created the key.
- Correction: state both cases, or initialise `occupancy` from `eMonitorConfig`.
- Evidence status: inferred (P map semantics; not run).
- Acceptance check: a log beginning with `LEAVE` for a resource produces the behaviour the table
  describes.

## Earlier findings CX-001 to CX-003 at this snapshot

These were raised by Codex on snapshot `d315bdc`. This is Claude's reassessment of whether the
snapshot `e097599` still exhibits them; it is not a response in the sense of the protocol's
exchange, which requires a Codex review of the same snapshot, and it does not represent Codex's
view.

| Finding | Status at `e097599` (Claude's assessment) | Evidence |
|---|---|---|
| CX-001 S2 formula versus monitor | addressed: S2 is defined as a closure property in both specifications, matching `Common/Specs.p:41–59` | `Cell/SPECIFICATION.md:995` |
| CX-002 E9 abort versus L2 | partly addressed: L3 and `eAdaptationAborted` were added and the documentation separates L2 and L3; CL-001 and CL-003 above remain | `Common/Specs.p:108–130`, `Common/MonitorEvents.p:36–38` |
| CX-003 deleted `SANCTION` treated as a system fault | addressed: a deleted line is labelled a log mutant (logging defect), and injected system faults are described separately | `Cell/SPECIFICATION.md:818`, `Cell/ManufacturingCell/INSTRUCTIONS.md:301`, `Fleet/SPECIFICATION.md:1082` |

## Suitability for coursework

The scope (45 days, staged deliverables, explicit hypotheses, validation records) is appropriate for
graduate students. The main risk is that students spend effort reconciling predicted and actual
checker output in E4 and E8/E9 (CL-002, CL-003); correcting those predictions before release would
remove most of that risk. The toolchain preflight in days 1–7 of `ASSIGNMENT.md` (`Fleet/ASSIGNMENT.md:51`; the cell
assignment has the same row) addresses the remaining reproducibility gap (no committed Gradle wrapper,
PObserve not yet run).
