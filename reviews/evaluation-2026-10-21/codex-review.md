# Independent evaluation of the two P-language projects

Date: October 21, 2026. Reviewer: Codex. Snapshot:
`d315bdce47293d6f4b4ee453fa16e6afb009f32e` (`main`).
This is an independent report, with no Claude review or joint approval.

## Assessment

Both projects are credible graduate-course starter kits. The manufacturing cell
has the tighter scope and is the easier first project. The fleet adds meaningful
distributed admission and a useful research problem in sanction attribution, with
greater workload and more monitor-design ambiguity. The current documentation
is substantially stronger than the first version: explicit hypotheses, traceability,
mutants, assumptions, grading, and reproducible reporting are now built into the work.

The model-checking path works on the installed toolchain: both projects compile
without errors or warnings, their naive variants produce the intended violations,
and neither two-phase baseline produced a violation within a 30-second run. The
fleet fairness test also produces the expected flagged sanction. These are bounded
bug-finding results, not a proof and not completion of the specified 100,000-schedule
baseline acceptance criterion.

PObserve Java generation works for both projects, including the tuple types named
by the parsers. The full Java package builds, JUnit tests and PObserve replay remain
unvalidated here because Gradle/Maven and the required runtime dependencies were
not available through the local command environment. Generation success is not a
successful Java compilation or runtime check.

## Actual verification

All five baseline checks used random scheduling and seed 42. Requested limit:
10,000 schedules, with a 30-second timeout per check. The actual counts below,
not the requested maximum, describe coverage.

| Check | Actual result | Evidence |
|---|---|---|
| Manufacturing `p compile` | succeeds; 0 warnings/errors | [build log](evidence/cell-compile.txt) |
| Fleet `p compile` | succeeds; 0 warnings/errors | [build log](evidence/fleet-compile.txt) |
| `tcCellTwoPhase` | 0 bugs in 5,370 schedules; 201 timelines; timeout reached | [run](evidence/tcCellTwoPhase.txt) |
| `tcFleetTwoPhase` | 0 bugs in 3,442 schedules; 64 timelines; timeout reached | [run](evidence/tcFleetTwoPhase.txt) |
| `tcCellNaive` | S1: human enters occupied resource 0; found on schedule 2 | [trace](evidence/tcCellNaive-output/BugFinding/ManufacturingCell_0_0.txt) |
| `tcFleetNaive` | S2: robot 2 admitted to closed zone 1 using v0 after v1 commit; schedule 1 | [trace](evidence/tcFleetNaive-output/BugFinding/MobileRobots_0_0.txt) |
| `tcFleetSanctionFairness` | obligation 0 of robot 1 sanctioned after abandonment; schedule 1 | [trace](evidence/tcFleetSanctionFairness-output/BugFinding/MobileRobots_0_0.txt) |
| Both `p compile --mode pobserve` | Java generation succeeds | [cell](evidence/cell-pobserve-compile.txt), [fleet](evidence/fleet-pobserve-compile.txt) |
| Four committed samples regenerated in memory | all match after newline normalization; advertised Python verdicts match | [results](python-verification.json) |
| Two-phase simulation, seeds 0–499, 60 ticks each | 500 fleet and 500 cell runs checked | [script](verify_samples.py), [results](python-verification.json) |

Across the 500 fleet simulations, the only reported property failure was F1
(all 500 runs). The obligation-based monitor flagged 3,468 sanctions, versus 4,255
using the legacy agent-based correlation, out of 4,479 sanctions. These reproduce
the guide's aggregate claims. Maximum completed adaptation duration was 3 ticks.

Across the 500 cell simulations, the only reported property failure was R2,
in 9 runs. Of 5,180 completed adaptations, 9 exceeded 5 ticks; the maximum was
8 ticks. Seed 64 is the first failing seed. This reproduces the limitation already
documented in the guide. It is not evidence of a physical-safety violation.

These simulation counts are Python-mirror results, not PObserve results.

## Findings requiring correction

### CX-001 — Medium: the manufacturing S2 formula promises a version check the monitor does not implement

Evidence status: observed by source inspection and an executable P probe.

[Manufacturing specification, line 984](../../Projects/ProjectManufacturingCell2026/SPECIFICATION.md#L984)
adds `v = version(committed)` to its formal admission property.
`Common/Specs.p:53–57` in both projects checks only whether the resource is closed;
it prints the admission version but never compares it with the committed version.
The probe `tcStaleOpenZone` commits v1 closing zone 1 and then announces a v0
admission to still-open zone 0. The current S2 monitor accepts it.
See [probe source](MonitorProbes.p) and [result](probe-stale.txt).

Consequence: a student can pass S2 while violating the written formula. This
also matters architecturally because unaffected fleet guards deliberately keep
serving while commits propagate; strict global version equality is a stronger
requirement than closure safety.

Correction: align the formula with the implemented resource-closure property,
or explicitly introduce a separate strict-version property and justify its protocol.
Do not silently strengthen the fleet monitor without reconsidering unaffected zones.
Acceptance: rerun the stale-open-zone probe and explain the expected verdict in
the specification, then recheck both baselines.

### CX-002 — Medium: E9 cannot satisfy the existing L2 property by aborting a prepare

Evidence status: source-supported inference; the abort variant is not implemented.

[Fleet specification, line 1057](../../Projects/ProjectRobot2026/SPECIFICATION.md#L1057)
and the assignment's experiment summary predict that timeout-and-abort makes L2
hold while allowing refusal of the picker. However, `Common/Specs.p:97–105`
defines L2 as every adaptation start eventually committing. The hot state has
only a commit transition; it has no abort outcome.

Consequence: a correct abort that deliberately never commits that adaptation
cannot meet the stated progress property. Students may confuse legitimate refusal
with a liveness defect or weaken the property without recording a requirements change.

Correction: define a separate termination property, such as every start eventually
committing or explicitly aborting, with version correlation. Retain successful
installation as a distinct stronger property when it is required. Update E9's
expected result and the event/log vocabulary accordingly.
Acceptance: a timeout followed by abort satisfies termination, an unresolved
prepare fails it, and aborted preparation never admits the human or leaves guards stuck.

### CX-003 — Medium: deletion of a log line is mislabeled as a system fault

Evidence status: observed documentation contradiction.

[Manufacturing specification, line 958](../../Projects/ProjectManufacturingCell2026/SPECIFICATION.md#L958)
and [fleet specification, line 1080](../../Projects/ProjectRobot2026/SPECIFICATION.md#L1080)
describe deleting a `SANCTION` line as an injected system fault. Elsewhere the
assignments correctly distinguish system misbehavior from recording defects.
Deleting evidence does not establish that the organization failed to sanction.

Correction: use a simulator/model mutation that suppresses the actual sanction
while faithfully recording ticks and other events as the system-fault experiment.
Use post-processing deletion of an existing sanction record as the logging-defect
experiment. The monitor may report the same overdue obligation in both cases;
the ground truth and interpretation differ.
Acceptance: retain the original and modified executions/logs and explain the
different causes despite identical observable prefixes.

## Confirmed limits and readiness gaps

These are already acknowledged in the kit or are incomplete validation, rather
than newly discovered defects to count as surprise findings.

- **F1 is order-sensitive and does not establish causation.** Real P probes
  confirm that `ABANDON → SANCTION` fails while `SANCTION → ABANDON` for the same
  obligation passes. See [first ordering](probe-abandon-first.txt) and
  [reverse ordering](probe-sanction-first.txt). The assignment now explicitly
  asks students to refine order sensitivity and record denial causes. That is
  a legitimate project task, but counts from the current monitor are not a count
  of all unfair sanctions. Retain both orderings as acceptance cases for the refinement.
- **R2's five-tick bound is not a general cell guarantee.** The 500-run check
  reproduces the documented exceptions. Calibration should measure start-to-commit
  duration, including protocol delay, rather than drain time alone. Observed maxima
  are empirical evidence; they do not bound every future execution.
- **No full PObserve/JUnit execution was obtained.** Add a validated Gradle wrapper
  and record one clean build with pinned dependencies before relying on the late
  runtime phase of the course. Move this toolchain preflight to the first week.
- **The documented status can now be updated with actual P evidence.** Both models
  compile and the intended negative checks fail for the intended assertions.
  Keep the original published status distinct from this dated evaluation and record
  the actual schedule counts; do not claim the baseline's 100,000-schedule requirement
  was completed.
- **Two technicians remain an extension, not baseline functionality.** Human events
  carry only the resource ID and the current safety monitor stores a set of resources.
  The extension needs identities/counting or explicit lock-out holders, new tests,
  and matching log/parser changes. It is appropriate as the cell project's central task.

## Educational suitability

The manufacturing project is the stronger first assignment: one resource, one
controller, an understandable naive-policy failure, and a concrete extension whose
success can be demonstrated with a before/after trace. Its assignment, rubric,
prediction log, mutants and assumption table form a coherent assessment.

The fleet project is the stronger research-oriented assignment: three independent
admission controllers, hold-and-wait, bounded retries, and policy-dependent sanctions.
The distributed/centralized split is now explicit. Denial-cause instrumentation,
order-independent correlation and a targeted remedy must be treated as substantial
work, with scaling and refinement kept optional for the 45-day schedule.

Both provide good mechanisms for students to justify claims instead of collecting
passing tests. A teaching release would benefit from correcting CX-001–003 and
preflighting the Java stack. Neither project should be presented as a verified
physical deployment or a completed student solution.

## Suggested next actions

1. Correct the three specification inconsistencies, preserving the intended
   open-ended project tasks.
2. Record the successful P compilation and negative-test evidence from this run.
3. Validate the PObserve Java packages with Gradle/JUnit and preserve the outputs.
4. Complete the published baseline schedule counts and monitor-mutant checks
   before making the stronger acceptance claims.
5. For an independent second opinion, give Claude this commit and the scope,
   ask it to review independently, then exchange findings. No Claude agreement
   has been assumed here.

## Reproduction and limitations

Run `python -B reviews/evaluation-2026-10-21/verify_samples.py` from the repository
root to repeat sample and 500-seed simulation checks. It writes only its JSON result.
The exact baseline commands are `p compile`, followed by
`p check -tc <case> -s 10000 --seed 42 --timeout 30 --outdir <separate-output>`
from each copied model directory. Output paths change only artifact locations.
Compile the probe from this review directory with `p compile --pproj MonitorProbes.pproj`,
then run its generated DLL with the named test cases and one schedule.

Original project sources were unchanged. Generated files are confined to the review
directory. No external references were independently verified, no robot/PLC was run,
and no claim is made about exhaustive interleavings, all mutants, the unimplemented
two-technician/abort variants, or the complete Java runtime path.
