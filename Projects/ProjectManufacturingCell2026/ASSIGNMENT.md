# Assignment: verified regulation for a manufacturing cell

Graduate project · teams of 3 · 6 weeks

## Goal

A robot arm and an AGV share a work envelope, and a technician needs it locked out before entering. Starting from the model in this kit, your team will:

1. reproduce the baseline results with the P checker,
2. explain why the naive adaptation is unsafe, from a counterexample you found yourselves,
3. design, model and verify a regulation that keeps **two technicians** safe,
4. check the same properties on execution logs with PObserve, and say what a log can and cannot establish.

Read `ManufacturingCell/INSTRUCTIONS.md` first. It holds the commands, the log format and the validation record you will fill in.

## Ground rule: every claim needs evidence

A result counts only if it is reproducible. For every claim in your report ("the two-phase design is safe", "the naive design fails"), record:
- the exact command,
- tool versions (`p --version`, `java -version`, PObserve commit),
- the seed or number of schedules (`-s`),
- the actual output, and the trace for every failure (`PCheckerOutput/BugFinding/`).

"No bug found in N schedules" is a result. "The design is correct" is not, unless you argue why N schedules cover the relevant behaviors.

## Schedule

| Week | Work | Checkpoint (end of week) |
|---|---|---|
| 1 | Install the toolchain. Compile the model and fix the first-compile errors. Run `tcCellTwoPhase` and `tcCellNaive`. Read Yan et al. (COINE 2025) on the regulation capabilities. | Section 5 of `INSTRUCTIONS.md` filled in for the P steps. A one-page note mapping each machine in `Common/` to a regulation capability |
| 2 | Design experiments. Run at least three changes from section 2.4 of the guide, or your own. For each, **write your prediction before running**, then compare. | Experiment log: change, prediction, result, explanation of each counterexample |
| 3 | Two technicians, analysis. Add a second `HumanRequester` and reproduce the failure described in section 2.5. Write the property that fails as a new P monitor, and show it catches the bug. | Failing trace, with the interleaving explained step by step. The new monitor |
| 4 | Two technicians, fix. Change the regulation so a resource reopens only when no human is inside (e.g. lock-out holders tracked per resource). Re-run every existing test. | All monitors hold on the fixed model, including yours. A short argument for why your schedule count is enough |
| 5 | Run time. Build the PObserve package and run it on both sample logs. Generate logs that include your two-technician scenario (extend `tools/simulate_logs.py`) and check them. Calibrate the 5-tick bound of `AdaptationBoundedTime` from data (the guide shows the simulator exceeds it). Inject at least two log defects from section 3.9 (missing `LEAVE`, duplicate `COMMIT`, ...) and report what the monitors do. | PObserve output for every log. The chosen adaptation bound with its justification |
| 6 | Report and presentation. | Final submission |

## Deliverables

1. **Repository** (a branch or fork of this one): your model changes, new monitors, tests, scripts, generated logs, and the traces you cite. Every `p check` and PObserve command in the report must run from it.
2. **Report**, 8–12 pages, structured as:
   - the system and its regulation, with the capability mapping (week 1),
   - design-time results: baseline, experiments, the two-technician bug and fix,
   - run-time results: sample logs, your logs, log defects, bound calibration,
   - threats to validity: what the checker did not explore, what the logs cannot show, where the model differs from a real cell,
   - the filled validation record as an appendix.
3. **Presentation**, 15 minutes plus 5 for questions, including a live run of one counterexample.
4. **Contribution statement**: one paragraph per member on what they did.

## Grading

| Component | Weight | What earns full marks |
|---|---|---|
| Baseline reproduced, validation record | 10% | Every step recorded with command, versions, seed and actual output |
| Design experiments | 15% | Predictions made before running; counterexamples explained, not just reported |
| Two technicians: analysis and new monitor | 20% | The failure reproduced, the interleaving explained, a monitor that fails before the fix |
| Two technicians: fix and verification | 20% | All monitors hold after the fix; schedule count justified; no existing test weakened |
| Run-time monitoring | 15% | PObserve results on all logs; adaptation bound justified from data; log defects analyzed |
| Report and presentation | 20% | Claims match the evidence; limits stated plainly; clear explanation of the design-time / run-time split |

Individual grades may be adjusted from the contribution statements and the presentation questions.

## Suggested roles

Rotate if you prefer, but someone should own each area:
- **Modeler**: P machines, the two-technician fix.
- **Verifier**: monitors, checker runs, traces, the validation record.
- **Run time**: PObserve build, log generation, defect injection, bound calibration.

Everyone must be able to explain the counterexamples in the presentation.

## Going further (optional)

- Physical e-stop: model a safety layer below the multi-agent system and show which properties no longer depend on the agents' compliance.
- Instrument a JaCaMo prototype with `tools/instrumentation/RegulationLog.java` and check its logs.
