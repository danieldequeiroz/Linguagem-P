# Manufacturing cell: instructions

A robot arm and an AGV share one work envelope (resource `0`, capacity 1). A single cell controller regiments access to it, and one organizational engine manages job obligations. A maintenance technician triggers a **lock-out adaptation** before entering the cell.

> **Verification status.** Nothing in this guide has been confirmed by running P or PObserve yet. The P files have not been compiled, and the Java parser has not been built (it depends on classes that `p compile --mode pobserve` generates). Every "expected" result below is a hypothesis. The only results actually produced so far come from the Python mirror of the monitors (`tools/simulate_logs.py --check`), recorded in section 5. Fill in the validation record there as you confirm each step.
>
> *Note.* Independent evaluation, 21 October 2026 (P 3.1.0.0, .NET SDK 8.0.426): `p compile` succeeds with no warnings; `tcCellNaive` fails S1 on schedule 2 as intended; `tcCellTwoPhase`: no bug in 5,370 schedules within a 30-second run (not the 100,000-schedule acceptance run); `p compile --mode pobserve` generates the Java classes; Java build, JUnit and PObserve replay not yet run. Evidence: [`reviews/evaluation-2026-10-21`](https://github.com/perkusic/P-Language/tree/main/reviews/evaluation-2026-10-21).

Grid cell (Yan et al., COINE 2025): **organization-centric + environment-centric, centralized**. One `ResourceGuard` (the cell controller) admits agents, one `AdaptationCoordinator` changes the norm set, and one `ObligationManager` handles jobs and sanctions. With a single guard, the two-phase adaptation reduces to "block, drain, commit" at one place.

You will do two things. They share most monitors but not all:

| Monitor | Design time (`p check`) | Run time (PObserve) |
|---|---|---|
| `RegimentationSafety`, `NoStaleAdmission`, `NoDoubleOutcome`, `LockoutBeforeEntry` | yes | yes, the same P code |
| `EveryObligationResolved`, `AdaptationCompletes`, `AdaptationTerminates` (liveness, hot states) | yes | no: a finite log cannot show that something *never* happens |
| `ObligationDeadlineRespected`, `AdaptationBoundedTime` (bounded response, section 3.9) | no: they read `eTick`, which the model announces before the obligation manager acts on it, so they would raise false alarms | yes, replacing the two liveness monitors |

1. **Design time.** Model-check the regulation design with the P checker (part 2).
2. **Run time.** Check logs from a running cell with PObserve (part 3).

```
ManufacturingCell/
├── ManufacturingCell.pproj        # checker project (model + monitors)
├── PSrc/CellAgent.p               # CellAgent + ManufacturingSystem (wiring)
├── PTst/TestScript.p              # tcCellTwoPhase, tcCellNaive
└── pobserve/                      # PObserve package (monitors + log parser)
    ├── build.gradle.kts, settings.gradle.kts
    ├── run_pobserve.sh            # CLI runner, loops over the monitors
    └── src/
        ├── main/CellRegulation.pproj                 # monitors only, Java target
        ├── main/java/regulation/cell/parser/CellRegulationParser.java
        ├── test/java/regulation/cell/CellSafetyTest.java
        └── test/resources/cell_twophase.log, cell_naive.log
```

Shared files live in `../Common/`:
- `MonitorEvents.p`: what the monitors observe
- `Specs.p`: monitors shared by checker and PObserve
- `RuntimeSpecs.p`: bounded-response monitors used at run time
- the model machines

---

## 1. Prerequisites

| Tool | Needed for | Install |
|---|---|---|
| .NET SDK 8.0 | P compiler and checker | https://dotnet.microsoft.com/download/dotnet/8.0 |
| P | `p compile`, `p check` | `dotnet tool install --global P` |
| Java 17+ | PObserve | e.g. `sudo apt install openjdk-17-jdk` |
| Gradle 8.x | building the PObserve package and CLI | `sdk install gradle 8.10.2` (SDKMAN) |
| Python 3 | generating more test logs (optional) | — |

Alternatively, P publishes a Docker image with .NET, JDK, Maven and the `p` CLI. Mount the project folder:
```bash
docker run --rm -it -v "$PWD":/workspace ghcr.io/p-org/p:latest bash
```

In PowerShell, write the mount as `-v "${PWD}:/workspace"`.

Check the installation: `p --version`, `java -version`, `gradle --version`.

### 1.1 Pin versions

The guide has not been validated against a specific toolchain. When you validate it, install pinned versions and record them in section 5:

| Component | Pin to | How to check |
|---|---|---|
| P | the version you validate with; the latest release tag at the time of writing is `p-3.1.0` | `p --version`; install a given version with `dotnet tool install --global P --version <x>` |
| PObserve CLI | a commit of `p-org/P`; `260da92` (master, 2026-08-03) builds `PObserve-1.0.0.jar` | `git -C P rev-parse --short HEAD` |
| `pobserve-commons`, `pobserve-java-unit-test` | `1.0.0` (set in `pobserve/build.gradle.kts`) | — |
| Java, Gradle, Python | Java 17, Gradle 8.10.2, Python 3.10+ | `java -version`, `gradle --version`, `python3 --version` |

### 1.2 Windows

- `p compile` and `p check` run in PowerShell.
- `run_pobserve.sh` is a Bash script. Run it from **Git Bash** or **WSL**, or call the raw `java -jar ...` command from section 3.5 once per monitor in PowerShell.
- Use `.\gradlew.bat` instead of `./gradlew` in PowerShell. `gradle wrapper` needs Gradle installed once.
- Use `python` or `py` if `python3` is not on your `PATH`.

---

## 2. Design time: model checking

### 2.1 Compile

```bash
cd ManufacturingCell
p compile
```

These drafts have not been compiled yet, so the first run may report small syntax issues. The P error points to file and line. Typical ones are a missing `ignore`/`defer` for an event arriving in a state that does not handle it, or tuple field names.

### 2.2 Run the two tests

```bash
p check -tc tcCellTwoPhase -s 10000     # two-phase adaptation (prepare, drain, commit)
p check -tc tcCellNaive    -s 10000     # naive adaptation (commit first, install later)
```

`-s` sets the number of schedules explored. A larger count gives more confidence on the passing test, but the count must be justified, not just raised (specification section 5.9): run `tcCellNaive` with increasing `-s` (or several seeds) and record the count at which the known bug is first found; then check `tcCellTwoPhase` with a clear margin over that count. With `--sch-pct` the checker uses the PCT strategy, whose probabilistic bound is discussed in the same section.

### 2.3 Read the results

Expected results (hypotheses, not yet run):

| Test | Expected | Meaning |
|---|---|---|
| `tcCellTwoPhase` | no bug found | The regulation design is safe under every explored interleaving |
| `tcCellNaive` | bug found in `RegimentationSafety` or `NoStaleAdmission` | The technician is admitted while the arm is still in the envelope, or the controller admits an agent to a resource that the committed norm set closes |

`NoStaleAdmission` (S2) is a closure property, not a check of strict version equality: an admission recorded under an older version is accepted if the committed norm set does not close that resource (confirmed by the probe `tcStaleOpenZone` of the independent evaluation, [`probe-stale.txt`](https://github.com/perkusic/P-Language/blob/main/reviews/evaluation-2026-10-21/probe-stale.txt)). Requiring every admission to carry the committed version would be a separate, stronger property that needs its own justification in the protocol.

When a bug is found, the checker writes a trace under `PCheckerOutput/BugFinding/`. To read it:
1. Open the `.txt` log. Its last lines name the failing monitor and its message (e.g. *human entered resource 0 while agents were inside*).
2. Read it bottom-up. Find the `eNormCommitted` announcement, then the `eHumanEntered`, then the agent's `eResourceEntered`/`eResourceLeft`. The interleaving between them is the counterexample.
3. Re-run with `--seed <n>` (printed in the log) to reproduce the same schedule while you fix the model.

"No bug found" means only that the explored schedules (`-s`) showed none. Record the count you used.

### 2.4 Experiments worth running

The ids refer to the experiment table in section 7.3 of the specification, which also gives each experiment's hypothesis and acceptance criterion. Write the prediction down before running.

| Id | Change | Where | What to look for |
|---|---|---|---|
| E3 | Agents never release the envelope (remove the `send guard, eRelease` in `Working`) | `PSrc/CellAgent.p` | `AdaptationCompletes` (L2) fails: the lock-out can never drain. This argues for a physical e-stop below the MAS |
| E5 | Shorter deadlines (`due = 2`) | `ManufacturingSystem` | More sanctions; `EveryObligationResolved` (L1) must still hold |
| E4 | Two technicians (a challenge, not a check of existing behavior) | add a second `HumanRequester` | See 2.5 |

E6–E8 (specification section 7.3) are further options. In E8 (cancelling a prepare), announce `eAdaptationAborted` with the aborted version and judge liveness by `AdaptationTerminates` (L3: every started adaptation eventually commits or is explicitly aborted, under the same version); `AdaptationCompletes` (L2) fails by design for an aborted change. The starter kit never aborts, so L3 holds there as L2 does.

### 2.5 Challenge: two technicians

The coordinator defers a new trigger while an adaptation is in progress, so adaptations run one at a time. That alone does not make two technicians safe. Expected trace (not yet run):

1. Technician A requests a lock-out. v1 closes resource 0; A enters.
2. Technician B requests a lock-out. v2 closes resource 0 again (no change); B enters.
3. A leaves and requests reopening. v3 opens resource 0, although B is still inside.
4. The controller admits the arm: `RegimentationSafety` should fail.

Serialization orders the norm-set changes, but nothing tracks who is still inside. To fix it:
- **Track human presence.** The coordinator keeps the set of technicians who hold a lock-out on each resource, and reopens only when the last one leaves.
- **Verify it.** Add a monitor for property S4 of the specification, "no committed norm set opens a resource while a human is inside" (observe `eHumanEntered`, `eHumanLeft`, `eNormCommitted`), and check that it fails before your fix and holds after. Also run it against a mutant (specification section 5.11) to show it is not vacuous.

---

## 3. Run time: PObserve

The commands in this part have not been run against this package yet (see the status note at the top).

PObserve replays structured logs of a running system through the shared P monitors, plus the bounded-response ones in `RuntimeSpecs.p`. The monitors are compiled to Java (`p compile --mode pobserve`), and a log parser turns each log line into a P event.

### 3.1 The log contract

Every component that takes part in regulation writes **one line per event**:

```
2026-10-19 08:00:03.004000 [cell-A] INFO Regulation - : Site=cell-A, Event=HUMAN_ENTER, Res=0
└── UTC timestamp, microseconds ──┘ └ free text ending in " - : " ┘ └ comma-separated Key=Value ┘
```

| Event | Fields | Emitted by | P event |
|---|---|---|---|
| `CONFIG` | `Capacity=0:1` | regulation engine at start-up (**required first**) | `eMonitorConfig` |
| `TICK` | `Now` | organization clock | `eTick` |
| `OBLIGATION` | `Id, Agent, Task, Due` | organization (job assigned) | `eObligationCreated` |
| `FULFILLED` | `Id, Agent` | organization (job reported) | `eObligationFulfilled` |
| `SANCTION` | `Id, Agent` | organization (deadline missed) | `eSanctionApplied` |
| `ENTER` / `LEAVE` | `Agent, Res, Ver` / `Agent, Res` | cell controller (PLC) | `eResourceEntered` / `eResourceLeft` |
| `ADAPT_START` | `Ver` | adaptation engine (detect) | `eAdaptationStarted` |
| `COMMIT` | `Ver, Closed=0` (`-` if none) | adaptation engine (execute) | `eNormCommitted` |
| `HUMAN_ENTER` / `HUMAN_LEAVE` | `Res` | door switch / light curtain | `eHumanEntered` / `eHumanLeft` |

Rules:
- Ids are integers.
- Timestamps must **increase within a site**.
- `Site` is the PObserve partition key, so one log file may contain several cells.

### 3.2 Build the PObserve CLI (once)

```bash
git clone https://github.com/p-org/P.git
cd P/Src/PObserve/PObserve
gradle wrapper
./gradlew build
export POBSERVE_JAR="$PWD/build/libs/PObserve-1.0.0.jar"
```

### 3.3 Build this example's package

```bash
cd ManufacturingCell/pobserve
gradle wrapper
./gradlew build
```

`./gradlew build` does three things:
1. Runs `p compile --mode pobserve` in `src/main`, generating `PEvents`, `PTypes` and `PMachines` under `src/main/java/regulation/cell/spec/`.
2. Compiles the parser.
3. Runs the JUnit tests (3.4).

If the parser does not compile, open the generated `PTypes.java` and check the tuple class names against those listed at the top of `Common/MonitorEvents.p`.

### 3.4 Option A: JUnit (CI-friendly)

`CellSafetyTest` runs six monitors over the sample logs:
- `RegimentationSafety`
- `NoStaleAdmission`
- `NoDoubleOutcome`
- `ObligationDeadlineRespected`
- `AdaptationBoundedTime`
- `LockoutBeforeEntry`

```bash
./gradlew test
```

| Test | Log | Expected |
|---|---|---|
| `twoPhaseAdaptationIsSafe` | `cell_twophase.log` | passes, no violation |
| `naiveAdaptationViolatesRegulation` | `cell_naive.log` | passes, because the test *expects* a `PAssertionFailureException` (human and arm in resource 0 at tick 3) |

To check your own logs, put them in `src/test/resources/` and copy one of the test methods.

### 3.5 Option B: CLI

```bash
./gradlew uberjar                                     # -> build/libs/CellRegulation-1.0.0-uber.jar
./run_pobserve.sh                                     # sample naive log, all monitors
./run_pobserve.sh src/test/resources/cell_twophase.log
./run_pobserve.sh /var/log/cell-A/regulation.log RegimentationSafety LockoutBeforeEntry
```

One spec is checked per run, so the script loops over them. Each run prints a summary (events read and verified, spec and parser errors). On a violation it writes `replayEvents_*.log` under `pobserve-out/<Spec>/`. That file holds the events leading to the failure: the run-time counterpart of the checker's counterexample.

The equivalent raw command for one spec:
```bash
java -jar "$POBSERVE_JAR" --jars build/libs/CellRegulation-1.0.0-uber.jar \
     --spec NoStaleAdmission -l src/test/resources/cell_naive.log -o pobserve-out/NoStaleAdmission
```

### 3.6 Expected run-time results on the sample logs (Python mirror, not PObserve)

| Monitor | `cell_twophase.log` | `cell_naive.log` |
|---|---|---|
| RegimentationSafety | ok | **violation**: human entered resource 0 while agents were inside (tick 3) |
| NoStaleAdmission | ok | **violation**: agent 2 admitted to resource 0, closed by v1, guard on v0 (tick 3) |
| NoDoubleOutcome | ok | ok |
| ObligationDeadlineRespected | ok | ok |
| AdaptationBoundedTime | ok | ok |
| LockoutBeforeEntry | ok | ok |

These come from the Python mirror of the monitors (commands in section 5), not from a PObserve run. PObserve is expected to report the same first violations, stopping at the first violation per spec and key; confirm and record it.

### 3.7 More logs

```bash
python3 ../../tools/simulate_logs.py --scenario cell --policy naive --seed 7 --ticks 200 \
        --out src/test/resources/cell_naive_long.log --check
```

### 3.8 Instrument a real cell

- **JaCaMo.** Copy `../../tools/instrumentation/RegulationLog.java` into the project. Call it from:
  - the CArtAgO artifact that admits agents (`enter`/`leave`)
  - the NPL/Moise obligation lifecycle (`obligation`/`fulfilled`/`sanction`, plus `tick` on the organization clock)
  - the regulation adaptation engine (`adaptStart`/`commit`)
  - the safety interlock (`humanEnter`/`humanLeave`)
  
  Route the output to a file, keeping the ` - : ` separator.
- **PLC / OPC UA.** Emit the same lines from the gateway that logs door switches and envelope occupancy.
- Log `CONFIG` once at start-up. `RegimentationSafety` starts by reading the capacities.

### 3.9 Log assumptions and limitations

The run-time results are only as good as the log. The monitors assume:

**A tick is one step of the organization's logical clock**, logged as a `TICK` by the obligation engine before it checks deadlines. Deadlines (`Due`) are in ticks. The simulator maps one tick to one second of log time; on a real cell, choose the tick period (e.g. 1 s) and log it consistently.

**The two bounds:**
- `ObligationDeadlineRespected` uses a grace of **1 tick**. The obligation engine sanctions at the first tick where `now > Due`, and logs the `SANCTION` *after* that `TICK` line. So an obligation due at tick *d* is resolved by tick *d+1* at the latest, and the monitor complains at tick *d+2*. One tick is the smallest grace that does not raise false alarms; in 500 simulated runs every sanction came exactly one tick after its due time. Raise it if your engine checks deadlines less often than every tick.
- `AdaptationBoundedTime` allows **5 ticks** from `ADAPT_START` to `COMMIT`. This is a design choice, not derived from the model: draining the envelope takes as long as the agent inside stays there. **The simulator already exceeds it**: in 500 simulated two-phase cell runs, 9 of 5,180 adaptations took 6 to 8 ticks, so longer two-phase logs can fail this monitor although the design is safe. The property (R2 in the specification) holds only if the bound is at least the maximum observed start-to-commit duration. Calibrate it by measuring, for each completed adaptation, the time from `ADAPT_START` to `COMMIT` (protocol delay included), not the drain time alone, and record why the chosen bound suffices (e.g., maximum job time in the envelope plus the controller's reaction time). An observed maximum is empirical, not a bound for all executions: the independent evaluation found 9 of 5,180 completed adaptations above 5 ticks, with a maximum of 8 ([`python-verification.json`](https://github.com/perkusic/P-Language/blob/main/reviews/evaluation-2026-10-21/python-verification.json)).

**Bounded monitors need later ticks.** Both bounded monitors check only when a `TICK` arrives. If the log ends before tick *d+2* (or 5 ticks after `ADAPT_START`), an unresolved obligation or adaptation is simply not reported. A clean result on a log that stops early does not show that work completed.

**Restarts.** `CONFIG` must come first for each site. `RegimentationSafety` handles `CONFIG` only in its initial state, so a second `CONFIG` after a restart is an event the monitor does not handle. P treats that as an error. Monitor state (occupancy, committed norm set, open obligations) is also not reset. Split logs at restarts and check each segment separately.

**Missing and duplicate events** are *log defects*: the log misrepresents what the system did. They differ from *system faults*, where the system misbehaves and the log records it faithfully (e.g., a `COMMIT` before the envelope has drained); a monitor should report a system fault, whereas a log defect produces false results, in both directions:

| Problem | Effect |
|---|---|
| missing `LEAVE` | occupancy never drops: a later `ENTER` is reported as a capacity violation, a later `HUMAN_ENTER` as an unsafe entry |
| missing `ENTER` (e.g. the log starts while the arm is in the envelope) | occupancy goes negative and hides real capacity violations |
| missing `COMMIT` | the next `COMMIT` fails the version-order check; `LockoutBeforeEntry` may report a bypass that did not happen |
| missing `TICK` | bounded monitors cannot fire for that period |
| duplicate `ENTER` | false capacity violation |
| duplicate `FULFILLED` / `SANCTION` | false `NoDoubleOutcome` violation |
| duplicate `COMMIT` | false version-order violation |
| deleted `SANCTION` (log mutant: an existing line removed in post-processing) | `ObligationDeadlineRespected` (R1) may report an overdue obligation, although the system did sanction it |

**A system fault and a log defect can look alike.** Suppressing the sanction in the simulator or model, while ticks and all other events are still recorded faithfully, is a system fault, and R1 must report it. Deleting an existing `SANCTION` line from a correct log is a log defect: R1 may report the same overdue obligation, but the ground truth differs. Keep both the original and the modified logs, and explain the different causes despite their identical observable prefixes.

**Equal timestamps.** PObserve orders events by timestamp within a site. These guides do not establish how it orders events with equal timestamps, so do not rely on it: make timestamps strictly increasing within a site (the simulator adds 1 ms per event).

---

## 4. What the two layers give you

| | P checker (design time) | PObserve (run time) |
|---|---|---|
| Input | the P model | logs of the real cell |
| Coverage | the schedules explored (`-s`), not all interleavings | the executions that actually happened, as far as they were logged |
| Liveness | hot-state monitors (`EveryObligationResolved`, `AdaptationCompletes`) | restated as bounded response (`ObligationDeadlineRespected`, 1-tick grace; `AdaptationBoundedTime`, 5 ticks; see 3.9) |
| Typical finding | a design flaw (naive adaptation) | an implementation that deviates from the verified design, or a procedure bypass (`LockoutBeforeEntry`) |

---

## 5. Validation record

Fill this in as you confirm each step. Until a row has a command, versions and actual output, treat its result as expected, not verified.

**Done so far: Python mirror only** (Python 3.13, 2026-10-20). Run from `ManufacturingCell/pobserve`:

```text
$ python3 ../../tools/simulate_logs.py --scenario cell --policy twophase --seed 1 --ticks 60 --out src/test/resources/cell_twophase.log --check
wrote 180 lines to src/test/resources/cell_twophase.log
  ok    RegimentationSafety
  ok    NoStaleAdmission
  ok    NoDoubleOutcome
  ok    ObligationDeadlineRespected
  ok    AdaptationBoundedTime
  ok    LockoutBeforeEntry

$ python3 ../../tools/simulate_logs.py --scenario cell --policy naive --seed 2 --ticks 60 --out src/test/resources/cell_naive.log --check
wrote 200 lines to src/test/resources/cell_naive.log
  FAIL  RegimentationSafety: human entered resource 0 while agents were inside (tick 3)
  FAIL  NoStaleAdmission: agent 2 admitted to resource 0 closed by v1, guard on v0 (tick 3)
  ok    NoDoubleOutcome
  ok    ObligationDeadlineRespected
  ok    AdaptationBoundedTime
  ok    LockoutBeforeEntry
```

The simulator is deterministic for a given seed, so these commands reproduce the committed sample logs byte for byte.

**Still to do:**

| Step | Command | Tool versions | Seed / schedules | Actual result |
|---|---|---|---|---|
| Compile the model | `p compile` | P 3.1.0.0, .NET SDK 8.0.426 (independent evaluation, 2026-10-21) | — | succeeds, no warnings |
| Two-phase design | `p check -tc tcCellTwoPhase -s 10000` | same (independent evaluation) | 30-second run | no bug in 5,370 schedules; not the 100,000-schedule acceptance run |
| Naive design | `p check -tc tcCellNaive -s 10000` | same (independent evaluation) | schedule 2 | fails S1 (`RegimentationSafety`), as intended |
| Generate the Java classes | `p compile --mode pobserve` | same (independent evaluation) | — | Java classes generated |
| PObserve package build and JUnit | `./gradlew build` | | — | not yet run: the independent evaluation found Gradle and Maven absent and no committed wrapper |
| PObserve CLI on both sample logs | `./run_pobserve.sh <log>` | | — | not yet run |

Rows marked "independent evaluation" come from the evaluation of 21 October 2026, not from your own runs; evidence in [`reviews/evaluation-2026-10-21`](https://github.com/perkusic/P-Language/tree/main/reviews/evaluation-2026-10-21). Repeat them on your machine and record your own versions.

For each failing check, keep the trace (`.txt` and `.schedule`) from `PCheckerOutput/BugFinding/` and note the seed that reproduces it.
