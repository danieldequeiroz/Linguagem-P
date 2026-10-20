# Assignment: verified regulation for a mobile robot fleet

Graduate project · teams of 3 · 6 weeks

## Goal

Two robots cross a three-zone corridor head-on, and a picker needs zone 1 closed. Admission is distributed across zone controllers; adaptation and sanctions are centralized. Starting from the model in this kit, your team will:

1. reproduce the baseline results with the P checker,
2. explain why the naive adaptation is unsafe, from a counterexample you found yourselves,
3. show that robots are sanctioned for situations the regulation created, find out **why** in each case, and design, model and verify a remedy,
4. check the same properties on execution logs with PObserve, and say what a log can and cannot establish.

Read `MobileRobots/INSTRUCTIONS.md` first. It holds the commands, the log format and the validation record you will fill in.

## Ground rule: every claim needs evidence

A result counts only if it is reproducible. For every claim in your report ("the two-phase design is safe", "the remedy removes unfair sanctions"), record:
- the exact command,
- tool versions (`p --version`, `java -version`, PObserve commit),
- the seed or number of schedules (`-s`),
- the actual output, and the trace for every failure (`PCheckerOutput/BugFinding/`).

"No bug found in N schedules" is a result. "The design is correct" is not, unless you argue why N schedules cover the relevant behaviors.

## Schedule

| Week | Work | Checkpoint (end of week) |
|---|---|---|
| 1 | Install the toolchain. Compile the model and fix the first-compile errors. Run `tcFleetTwoPhase`, `tcFleetNaive` and `tcFleetSanctionFairness`. Read Yan et al. (COINE 2025) on the regulation capabilities. | Section 5 of `INSTRUCTIONS.md` filled in for the P steps. A one-page note mapping each machine to a regulation capability, and saying which are distributed and which centralized |
| 2 | Design experiments. Run at least three changes from section 2.3 of the guide, or your own. For each, **write your prediction before running**, then compare. | Experiment log: change, prediction, result, explanation of each counterexample |
| 3 | Fairness, analysis. The current monitor flags a sanction after a robot abandons that obligation, but cannot say why access was denied (section 2.2). Record the cause of each denial (zone closed by the regulation, or zone held by the other robot), carry it in `eTaskAbandoned`, and refine the monitor so it reports regulation-caused and traffic-caused cases separately. | Refined monitor. Counterexample traces for both causes, or an argument that one cannot occur |
| 4 | Fairness, remedy. Implement one remedy: a one-direction traffic norm, or deadlines suspended or extended while the regulation blocks a robot. Verify that the refined monitor holds for the cases your remedy targets, and re-run every existing test. | All safety monitors still hold; fairness result for the remedy; a short argument for why your schedule count is enough |
| 5 | Run time. Build the PObserve package and run it on both sample logs. Extend `tools/simulate_logs.py` to log denial causes and your remedy, generate logs, and report **how many** sanctions each cause produces before and after the remedy. Inject at least two log defects from section 3.6 (missing `LEAVE`, duplicate `COMMIT`, ...) and report what the monitors do. | PObserve output for every log. Counts of flagged sanctions by cause, before and after |
| 6 | Report and presentation. | Final submission |

## Deliverables

1. **Repository** (a branch or fork of this one): your model changes, refined monitor, tests, scripts, generated logs, and the traces you cite. Every `p check` and PObserve command in the report must run from it.
2. **Report**, 8–12 pages, structured as:
   - the system and its regulation, with the capability and architecture mapping (week 1),
   - design-time results: baseline, experiments, the fairness analysis and remedy,
   - run-time results: sample logs, your logs, sanction counts, log defects,
   - threats to validity: what the checker did not explore, what the logs cannot show (in particular, causation), where the model differs from a real fleet,
   - the filled validation record as an appendix.
3. **Presentation**, 15 minutes plus 5 for questions, including a live run of one counterexample.
4. **Contribution statement**: one paragraph per member on what they did.

## Grading

| Component | Weight | What earns full marks |
|---|---|---|
| Baseline reproduced, validation record | 10% | Every step recorded with command, versions, seed and actual output |
| Design experiments | 15% | Predictions made before running; counterexamples explained, not just reported |
| Fairness: analysis and refined monitor | 20% | Denial causes recorded and distinguished; traces for each cause explained |
| Fairness: remedy and verification | 20% | Remedy verified on the cases it targets; safety monitors still hold; schedule count justified |
| Run-time monitoring | 15% | PObserve results on all logs; sanction counts by cause, before and after; log defects analyzed |
| Report and presentation | 20% | Claims match the evidence; no causal claim the monitor cannot support; limits stated plainly |

Individual grades may be adjusted from the contribution statements and the presentation questions.

## Suggested roles

Rotate if you prefer, but someone should own each area:
- **Modeler**: P machines, denial causes, the remedy.
- **Verifier**: monitors, checker runs, traces, the validation record.
- **Run time**: PObserve build, log generation, sanction counts, defect injection.

Everyone must be able to explain the counterexamples in the presentation.

## Going further (optional)

- Failure of a centralized component: model the adaptation coordinator crashing mid-adaptation, and show which properties break.
- Instrument a ROS 2 simulation with `tools/instrumentation/regulation_log.py` and check its logs.
