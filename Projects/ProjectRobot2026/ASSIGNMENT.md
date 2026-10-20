# Assignment: verified regulation for a mobile robot fleet

Graduate project · teams of 3 · 45 days

This page summarizes the assignment. Where it and section 8 of [`SPECIFICATION.md`](SPECIFICATION.md) differ, the specification is authoritative.

## Goal

Two robots cross a three-zone corridor head-on, and a picker needs zone 1 closed. Admission is regimented in a distributed way, by one controller per zone; adaptation and sanctioning are centralized. Starting from the model in this kit, your team will:

1. reproduce the baseline results with the P checker, after showing that every monitor can fail (experiment E0),
2. explain why the naive adaptation is unsafe, from a counterexample you found yourselves,
3. show that robots are sanctioned for situations the regulation created, find out **why** in each case, and design, model and verify a remedy,
4. check the same properties on execution logs with PObserve, and state what a log can and cannot establish.

Read `MobileRobots/INSTRUCTIONS.md` first. It holds the commands, the log format and the validation record you will fill in.

## Ground rule: every claim needs evidence

A result counts only if it is reproducible. For every claim in your report ("the prepare–drain–commit design is safe", "the remedy removes regulation-caused sanctions"), record:
- the exact command,
- tool versions (`p --version`, `java -version`, PObserve commit),
- the seed and the number of schedules (`-s`),
- the actual output, and the trace for every failure (`PCheckerOutput/BugFinding/`).

"No bug found in N schedules" is a result. "The design is correct" is not, unless you argue why N schedules cover the relevant behaviors (specification, section 5.9). Final evidence for E1 uses `-s 100000`; exploratory runs use `-s 10000`.

## Experiments

The experiments are numbered as in section 7.3 of the specification. For each one, **write your prediction before running**, then compare. The predictions below are the specification's hypotheses, not observed results.

| # | Change to the model | Prediction | Min. `-s` |
|---|---|---|---|
| E0 | Monitor sanity: one mutant per monitor | every monitor fails on its mutant | 10,000 |
| E1 | Baseline, prepare–drain–commit (`tcFleetTwoPhase`) | S1–S3, L1, L2 and R3 hold | 100,000 |
| E2 | Baseline, naive (`tcFleetNaive`) | S1 or S2 fails in zone 1 | 10,000 |
| E3 | Sanction fairness (`tcFleetSanctionFairness`) | F1 fails after closures and after head-on conflicts | 10,000 |
| E4 | Every controller blocks during prepare | L2 holds only with parking | 10,000 |
| E5 | No parking: robots retry forever | L2 violated by circular wait | 10,000 |
| E6 | Remedy 1: one travel direction at a time | traffic-caused cases disappear | 10,000 |
| E7 | Remedy 2: deadlines suspended while blocked, abandoned obligations excused | suspension alone: F1 still fails; with excusal: no regulation-caused case | 10,000 |
| E8 | Scale: 3–4 robots or 4–5 zones | run time grows rapidly | as feasible |
| E9 | Prepare timeout and abort after k ticks | L2 holds; the picker may be refused | 10,000 |

## Schedule

The project runs over **45 calendar days** in five phases, as in section 8 of the specification. Deliverables D1–D5 are due at the end of their phase.

| Phase | Work | Due | Exit criterion |
|---|---|---|---|
| **Days 1–7** · Background | Install the toolchain and work through the P tutorial ([`P-Tutorial/`](../../P-Tutorial/)). Read sections 2–5 of the specification and Yan et al. (COINE 2025) on the regulation capabilities. Run a first `p compile` and record the errors. | **D1 (day 7):** background note, 2–3 pages, with the fleet placed in the unified-view grid and a one-page mapping of each machine to a regulation capability, stating which responsibilities are distributed and which centralized | note submitted; toolchain versions recorded |
| **Days 8–17** · Model | Fix the first-compile errors and justify each modeling choice. Run E0, E1 and E2, and at least three of E3, E4, E5 and E9, each with a prediction recorded before the run. | **Checkpoint (day 17):** section 5 of `INSTRUCTIONS.md` filled in for the P steps; experiment log (change, prediction, result, explanation of each counterexample with the template of specification section 7.8) | project compiles; E0 shows that every monitor can fail; E1 and E2 recorded |
| **Days 18–28** · Verification | Sanction fairness. *Analysis (days 18–22):* the current monitor flags a sanction after a robot abandons that obligation, but cannot say why access was denied. Record the cause of each denial (zone closed by the regulation, or zone held by the other robot), carry it in `eTaskAbandoned`, and refine the monitor so it reports regulation-caused and traffic-caused cases separately, independently of the order of `ABANDON` and `SANCTION`. *Remedy (days 23–28):* implement E6 or E7. Verify that the refined monitor holds for the cases your remedy targets, and re-run every existing test. | **D2 (day 28):** verified model with the refined monitor; counterexample traces for both causes (or an argument that one cannot occur); all safety monitors still holding; the result of the remedy; the justification of the schedule count (specification, section 5.9) | the Must requirements of specification section 7.5 that concern the model are met |
| **Days 29–38** · Run time | Build the PObserve package and run it on both sample logs. Extend `tools/simulate_logs.py` to log denial causes and your remedy, generate logs, and report **how many** sanctions each cause produces before and after the remedy. Inject at least one **system fault** (a behavior the regulation forbids, e.g. a stale admission) and at least two **log defects** (a recording error, e.g. missing `LEAVE`, duplicate `COMMIT`, out-of-order lines; guide section 3.6) and report what the monitors do in each case. | **D3 (day 38):** PObserve package, verdicts for every log, counts of flagged sanctions by cause before and after the remedy | JUnit tests pass on the sample logs; every log has a recorded verdict |
| **Days 39–45** · Analysis | Report and presentation. | **D4 and D5 (day 45):** report and presentation | report and presentation delivered |

## Deliverables

1. **Repository**, kept up to date through D2 and D3 (a branch or fork of this one): your model changes, refined monitor, tests, scripts, generated logs, and the traces you cite. Every `p check` and PObserve command in the report must run from it.
2. **Report (D4, day 45)**, 8–12 pages in a workshop-paper format (e.g., EMAS, COINE or WESAAC), structured as:
   - the system and its regulation, with the capability and architecture mapping (D1),
   - design-time results: baseline, experiments E0–E9 that you ran, the fairness analysis and remedy,
   - run-time results: sample logs, your logs, sanction counts by cause, system faults and log defects, clock skew,
   - threats to validity (specification, section 7.6): what the checker did not explore, what the logs cannot show (in particular, causation), where the model differs from a real fleet,
   - the filled validation record as an appendix.
3. **Presentation (D5, day 45)**, 15 minutes plus 5 for questions, with one counterexample replayed live and one PObserve result shown.
4. **Contribution statement**: one paragraph per member on what they did.

## Grading

The full rubric, with Excellent, Adequate and Insufficient levels for each component, is in section 8 of the specification.

| Component | Weight | What earns full marks |
|---|---|---|
| Baseline and validation record | 10% | Every step has command, versions, seed and output, and is reproducible from the repository |
| Design experiments (E0–E5, E9) | 15% | Predictions recorded before running; every counterexample explained with the template of section 7.8; mutants for all monitors |
| Sanction fairness: analysis and refined monitor | 20% | Causes recorded and distinguished; traces for each cause explained; order sensitivity addressed |
| Sanction fairness: remedy and verification | 20% | Remedy verified for the targeted cases; safety monitors still hold; schedule count justified by calibration |
| Run-time monitoring | 15% | Verdicts for all logs; counts by cause before and after the remedy; system faults and log defects analyzed; clock skew discussed |
| Report and presentation | 20% | Claims match the evidence; no causal claim beyond what the monitors support; threats to validity complete |

Individual grades may be adjusted from the contribution statements and the presentation questions.

## Suggested roles

Rotate if you prefer, but someone should own each area:
- **Modeler**: P machines, denial causes, the remedy.
- **Verifier**: monitors, mutants, checker runs, traces, the validation record.
- **Run time**: PObserve build, log generation, sanction counts, fault and defect injection.

Everyone must be able to explain the counterexamples in the presentation.

## Going further (optional)

- Failure of a centralized component: model the adaptation coordinator crashing mid-adaptation, and show which properties break.
- Instrument a ROS 2 simulation with `tools/instrumentation/regulation_log.py` and check its logs.
