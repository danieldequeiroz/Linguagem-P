# Assignment: verified regulation for a manufacturing cell

Graduate project · teams of 3 · 45 days

## Goal

A robot arm and an AGV share a work envelope, and a technician needs it locked out before entering. Starting from the model in this kit, your team will:

1. reproduce the baseline results with the P checker,
2. explain why the naive adaptation is unsafe, from a counterexample you found yourselves,
3. design, model and verify a regulation that keeps **two technicians** safe,
4. check the same properties on execution logs with PObserve, and say what a log can and cannot establish.

Read `ManufacturingCell/INSTRUCTIONS.md` first. It holds the commands, the log format and the validation record you will fill in.

Section 8 of [`SPECIFICATION.md`](SPECIFICATION.md) is the authoritative source for phases, deliverables and grading; this file summarizes it. Property names (S1–S4, L1–L3, R1–R3) and experiment ids (E1–E8) refer to sections 7.2 and 7.3 of the specification.

## Ground rule: every claim needs evidence

A result counts only if it is reproducible. For every claim in your report ("the two-phase design is safe", "the naive design fails"), record:
- the exact command,
- tool versions (`p --version`, `java -version`, PObserve commit),
- the seed or number of schedules (`-s`),
- the actual output, and the trace for every failure (`PCheckerOutput/BugFinding/`).

"No bug found in N schedules" is a result. "The design is correct" is not. Justify N as in section 5.9 of the specification: report the schedule count at which the checker first finds the known naive-policy bug, and run the fixed model with a margin over that count. Show that every monitor can fail by running it against a mutant (section 5.11), so that a passing monitor is not a vacuous one.

## Schedule

The project runs over **45 calendar days** in five phases, the same plan as section 8 of [`SPECIFICATION.md`](SPECIFICATION.md). Deliverables D1–D5 are due at the end of their phase.

| Phase | Work | Due |
|---|---|---|
| **Days 1–7** · Background | Install the toolchain and work through the P tutorial ([`P-Tutorial/`](../../P-Tutorial/)). Read Yan et al. (COINE 2025) on the regulation capabilities. Run a first `p compile` and record the errors. **Toolchain preflight (exit criterion):** the PObserve Java package builds with a pinned Gradle wrapper, JUnit runs once on the sample logs, and the versions of P, .NET, JDK and Gradle are recorded. The independent evaluation of 21 October 2026 found neither Gradle nor Maven installed and no committed wrapper, so this step cannot be deferred to day 29. | **D1 (day 7):** background note, 2–3 pages, including a one-page mapping of each machine in `Common/` to a regulation capability; toolchain preflight passed |
| **Days 8–17** · Model | Fix the first-compile errors and justify each modelling choice. Run `tcCellTwoPhase` and `tcCellNaive` (experiments E1 and E2 of specification section 7.3). Then run at least three further experiments among E3, E5, E6, E7 and E8 (E4 belongs to the next phase), or your own. For each, **write your prediction before running** (the expected verdict and, for a failure, the property that fails), then compare. | Day 17 checkpoint: section 5 of `INSTRUCTIONS.md` filled in for the P steps; experiment log (change, prediction, result, explanation of each counterexample with the template of section 7.8) |
| **Days 18–28** · Verification | Two technicians (experiment E4). *Analysis (days 18–22):* add a second `HumanRequester` and reproduce the failure described in section 4.5 of the specification. Write property S4 (no committed norm set reopens a resource while a person is inside) as a new P monitor, show that it fails on the unfixed model, and check it against a mutant. *Fix (days 23–28):* change the regulation so that a resource reopens only when no person is inside (e.g., lock-out holders tracked per resource). Re-run every existing test. Run every monitor against a mutant (section 5.11) and calibrate the schedule count (section 5.9). | **D2 (day 28):** verified model: failing trace with the interleaving explained step by step, the S4 monitor, all monitors holding on the fixed model, the mutant results, and the schedule-count justification |
| **Days 29–38** · Run time | Build the PObserve package and run it on both sample logs. Generate logs that include your two-technician scenario (extend `tools/simulate_logs.py`) and check them. Calibrate the bound B of R2 (`AdaptationBoundedTime`, currently 5 ticks) from data by measuring the start-to-commit duration of each adaptation (`ADAPT_START` to `COMMIT`, protocol delay included), not the drain time alone: R2 holds only if B is at least the maximum observed start-to-commit duration. The observed maximum is empirical, not a bound for all executions; in the independent evaluation, 9 of 5,180 completed adaptations exceeded 5 ticks, with a maximum of 8 ([`python-verification.json`](https://github.com/perkusic/P-Language/blob/main/reviews/evaluation-2026-10-21/python-verification.json)). Inject at least one *system fault* (the system misbehaves, the log records it faithfully, e.g., a commit before the drain completes, or a simulator or model mutation that suppresses the actual sanction while ticks and other events are still recorded, which R1 must report) and at least two *log defects* from section 3.9 of `INSTRUCTIONS.md` (the log misrepresents the system: missing `LEAVE`, duplicate `COMMIT`, an existing `SANCTION` line deleted in post-processing, …), and report which monitor reacts, if any, and why. A deleted `SANCTION` line may make R1 report the same overdue obligation as the suppressed sanction, but the ground truth differs: keep both the original and the modified logs and explain the different causes despite their identical observable prefixes. | **D3 (day 38):** PObserve package and output for every log; the chosen bound B with its justification; the fault and defect analysis |
| **Days 39–45** · Analysis | Report and presentation. | **D4 and D5 (day 45):** report and presentation |

## Deliverables

1. **Repository**, kept up to date through D2 and D3 (a branch or fork of this one): your model changes, new monitors, tests, scripts, generated logs, and the traces you cite. Every `p check` and PObserve command in the report must run from it.
2. **Report (D4, day 45)**, 8–12 pages, structured as:
   - the system and its regulation, with the capability mapping (D1),
   - design-time results: baseline, experiments, the two-technician bug and fix,
   - run-time results: sample logs, your logs, log defects, bound calibration,
   - threats to validity, discussed per assumption as in section 7.7 of the specification: what the checker did not explore, what the logs cannot show, where the model over- or under-approximates a real cell,
   - the filled validation record as an appendix.
3. **Presentation (D5, day 45)**, 15 minutes plus 5 for questions, including a live run of one checker counterexample and one PObserve violation.
4. **Contribution statement**: one paragraph per member on what they did.

## Grading

The weights below match the rubric of section 8 of the specification, which also describes the adequate and insufficient levels.

| Component | Deliverable | Weight | What earns full marks |
|---|---|---|---|
| Background and capability mapping | D1 | 5% | Every machine mapped to a capability with justification; position in the grid argued |
| Baseline and validation record | D2 | 10% | Every step recorded with command, versions, seed and output; mutants for every monitor |
| Design experiments | D2 | 15% | Predictions recorded before running; counterexamples explained with the template of section 7.8 |
| Two technicians: analysis and S4 | D2 | 20% | Failure reproduced; interleaving explained; S4 fails before the fix |
| Two technicians: fix and verification | D2 | 20% | All monitors hold; schedule count justified by calibration; no test weakened |
| Run-time monitoring | D3 | 15% | All logs checked; R2 bound justified from data; system faults and log defects distinguished and analyzed |
| Report and presentation | D4, D5 | 15% | Claims match the evidence; threats to validity discussed per assumption; design-time / run-time split explained |

Individual grades may be adjusted from the contribution statements and the presentation questions.

## Suggested roles

Rotate if you prefer, but someone should own each area:
- **Modeler**: P machines, the two-technician fix.
- **Verifier**: monitors, mutants, checker runs, traces, the validation record.
- **Run time**: PObserve build, log generation, defect injection, bound calibration.

Everyone must be able to explain the counterexamples in the presentation.

## Going further (optional)

- Physical e-stop: model a safety layer below the multi-agent system and show which properties no longer depend on the agents' compliance.
- Instrument a JaCaMo prototype with `tools/instrumentation/RegulationLog.java` and check its logs.
