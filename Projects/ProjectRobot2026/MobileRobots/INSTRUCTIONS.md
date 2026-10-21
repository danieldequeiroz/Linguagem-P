# Mobile autonomous robots: instructions

Two robots deliver through a narrow corridor in opposite directions:

```
   [zone 0] ── [zone 1] ── [zone 2]       each zone: capacity 1, its own zone controller
   robot 1:  0 → 1 → 2                    robot 2:  2 → 1 → 0
```

A human picker needs zone 1, which must first be **closed to robots** (adaptation). A robot keeps its zone until the next one is granted. After 3 denials it parks in a side bay and abandons the delivery, and the organization then sanctions it.

> **Verification status.** The independent evaluation of 21 October 2026 (`reviews/evaluation-2026-10-21`) compiled the P files and ran the first schedules of the three test cases (section 5). The Java parser has not been built and PObserve has not been run. Every other "expected" result below is a hypothesis. The only results actually produced so far come from the Python mirror of the monitors (`tools/simulate_logs.py --check`), recorded in section 5. Fill in the validation record there as you confirm each step.

Grid cell (Yan et al., COINE 2025): **hybrid (environment + organization + agent)**, with responsibilities split as follows:

| Responsibility | Machine | Where it runs |
|---|---|---|
| Admission to a zone (regimentation) | `ResourceGuard`, one per zone | **Distributed.** Each zone controller decides alone, from its own occupancy and its installed norm set |
| Changing the norm set (adaptation) | `AdaptationCoordinator`, one for the fleet | **Centralized.** One coordinator runs prepare and commit with every zone controller |
| Obligations, deadlines, sanctions | `ObligationManager`, one for the fleet | **Centralized** |
| Logical time | `Clock`, one | **Centralized.** Only the obligation manager subscribes to it |

So "distributed" describes regimentation only. The coordinator and the obligation manager are single points of coordination (and of failure, which the model does not explore). Compared with the manufacturing cell, the extra difficulty is that the coordinator must collect acks from three independent controllers, and unaffected controllers keep admitting robots while zone 1 drains.

The workflow has two parts. They share most monitors but not all:

| Monitor | Design time (`p check`) | Run time (PObserve) |
|---|---|---|
| `RegimentationSafety`, `NoStaleAdmission`, `NoDoubleOutcome`, `LockoutBeforeEntry`, `SanctionsReflectMisconduct` | yes | yes, the same P code |
| `EveryObligationResolved`, `AdaptationCompletes` (liveness, hot states) | yes | no: a finite log cannot show that something *never* happens |
| `ObligationDeadlineRespected`, `AdaptationBoundedTime` (bounded response, section 3.6) | no: they read `eTick`, which the model announces before the obligation manager acts on it, so they would raise false alarms | yes, replacing the two liveness monitors |

1. Model-check the design (part 2).
2. Check real logs with PObserve (part 3).

This example adds a fleet-specific monitor, `SanctionsReflectMisconduct`, which flags candidate unfair sanctions (see 2.2).

```
MobileRobots/
├── MobileRobots.pproj             # checker project (model + monitors)
├── PSrc/Robot.p                   # Robot + FleetSystem (wiring)
├── PSpec/FleetSpecs.p             # eTaskAbandoned + SanctionsReflectMisconduct
├── PTst/TestScript.p              # tcFleetTwoPhase, tcFleetNaive, tcFleetSanctionFairness
└── pobserve/
    ├── build.gradle.kts, settings.gradle.kts, run_pobserve.sh
    └── src/
        ├── main/FleetRegulation.pproj
        ├── main/java/regulation/fleet/parser/FleetRegulationParser.java
        ├── test/java/regulation/fleet/FleetSafetyTest.java, FleetFairnessTest.java
        └── test/resources/fleet_twophase.log, fleet_naive.log
```

---

## 1. Prerequisites

| Tool | Needed for | Install |
|---|---|---|
| .NET SDK 8.0 | P compiler and checker | https://dotnet.microsoft.com/download/dotnet/8.0 |
| P | `p compile`, `p check` | `dotnet tool install --global P` |
| Java 17+ | PObserve | e.g. `sudo apt install openjdk-17-jdk` |
| Gradle 8.x | building the PObserve package and CLI | `sdk install gradle 8.10.2` (SDKMAN) |
| Python 3 | generating test logs, ROS 2 instrumentation (optional) | — |

Alternatively, use the P Docker image, which bundles .NET, a JDK and the `p` CLI:
```bash
docker run --rm -it -v "$PWD":/workspace ghcr.io/p-org/p:latest bash
```
In PowerShell, write the mount as `-v "${PWD}:/workspace"`.

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
- `run_pobserve.sh` is a Bash script. Run it from **Git Bash** or **WSL**, or run PObserve once per monitor in PowerShell:
  ```powershell
  java -jar $env:POBSERVE_JAR --jars build/libs/FleetRegulation-1.0.0-uber.jar `
       --spec NoStaleAdmission -l src/test/resources/fleet_naive.log -o pobserve-out/NoStaleAdmission
  ```
- Use `.\gradlew.bat` instead of `./gradlew` in PowerShell. `gradle wrapper` needs Gradle installed once.
- Use `python` or `py` if `python3` is not on your `PATH`.

---

## 2. Design time: model checking

### 2.1 Run the tests

```bash
cd MobileRobots
p compile
p check -tc tcFleetTwoPhase         -s 100000   # E1; -s 10000 for exploratory runs
p check -tc tcFleetNaive            -s 10000
p check -tc tcFleetSanctionFairness -s 10000
```

Expected results (hypotheses, not yet run):

| Test | Expected | Meaning |
|---|---|---|
| `tcFleetTwoPhase` | no bug found | Closing zone 1 drains it before the picker is admitted. Only the affected zone controller blocks; zones 0 and 2 keep serving |
| `tcFleetNaive` | bug in `RegimentationSafety` or `NoStaleAdmission` | Zone 1's controller is still on the old norm set and admits a robot after the closure was committed, or the picker enters while a robot is in zone 1 |
| `tcFleetSanctionFairness` | bug in `SanctionsReflectMisconduct` (**intended**) | A robot gives up a delivery after repeated denials, and that same obligation is later sanctioned |

When a bug is found, the checker writes a trace under `PCheckerOutput/BugFinding/`. Its last lines name the failing monitor and its message; read it bottom-up to find the interleaving, and re-run with the printed seed to reproduce it. For the fairness trace, look for `eTaskAbandoned` followed later by `eSanctionApplied` with the same obligation id. A "no bug found" result means only that the explored schedules (`-s`) showed none; record the count you used.

### 2.2 What the fairness monitor can and cannot tell you

`SanctionsReflectMisconduct` flags a sanction when the robot earlier abandoned **that same obligation** after 3 access denials. It does not establish:
- **why** access was denied. A zone closed for the picker (regulation) and a zone held by the other robot (traffic) produce the same `ABANDON` event.
- **that the denials caused** the missed deadline. Giving up after 3 denials is the robot's own policy; a robot that waited longer might have made it.

So a violation is a *candidate* unfair sanction. To attribute it, log the denial cause (add a `Cause` field, or log closures and occupancy at each denial) and extend the monitor. Until then, report counts of flagged sanctions, not "how often regulation causes unfair sanctions".

### 2.3 Experiments worth running

The experiment ids match section 7.3 of the specification, which also defines E0 (one mutant per monitor, to show that every monitor can fail; run it before trusting any "no bug found") and E9 (prepare timeout and abort). For E9, the coordinator announces an abort with `eAdaptationAborted` (log `ADAPT_ABORT, Ver`); the monitor `AdaptationTerminates` (L3) accepts a commit or an abort, while `AdaptationCompletes` (L2) fails by design for an aborted change. Acceptance cases: a timeout followed by an abort satisfies L3; a prepare neither committed nor aborted violates L3; an aborted prepare never admits the picker and leaves no controller blocked. Write your prediction before each run.

| # | Change | Where | What to look for |
|---|---|---|---|
| E4 | Block **all** zone controllers during prepare (drop the "unaffected guard acks at once" branch) | `Common/ResourceGuard.p`, `Open.eNormPrepare` | Drain now depends on parking. A robot in zone 1 cannot advance to a blocked zone 2. Remove parking as well and `AdaptationCompletes` should fail |
| E5 | Remove parking (retry forever) | `PSrc/Robot.p`, `eAccessDenied` | Head-on hold-and-wait: robots in zones 1 and 2 wait for each other forever. Expect `AdaptationCompletes` to fail when zone 1 must drain |
| E6 | Add a traffic norm: one direction per corridor (e.g. a `DirectionGuard` granting the corridor to one direction at a time) | new machine | If head-on denials disappear, any remaining `SanctionsReflectMisconduct` failure must follow a closure. Check this in the trace; the monitor itself still does not record the cause |
| E7 | Suspend deadlines while the regulation blocks an agent | `ObligationManager` | Expected: `SanctionsReflectMisconduct` still fails, because an abandoned obligation is still sanctioned when it falls due; it holds for regulation-caused cases only if abandoned obligations are also excused. To be confirmed with `p check` |

---

## 3. Run time: PObserve

### 3.1 Log contract

Every component that takes part in regulation writes one line per event:

```
2026-10-19 08:00:03.004000 [fleet-A] INFO Regulation - : Site=fleet-A, Event=HUMAN_ENTER, Res=1
└── UTC timestamp, microseconds ──┘ └ free text ending in " - : " ┘ └ comma-separated Key=Value ┘
```

| Event | Fields | P event |
|---|---|---|
| `CONFIG` | `Capacity=0:1;1:1;2:1` (**required first**) | `eMonitorConfig` |
| `TICK` | `Now` | `eTick` |
| `OBLIGATION` | `Id, Agent, Task, Due` | `eObligationCreated` |
| `FULFILLED` / `SANCTION` | `Id, Agent` | `eObligationFulfilled` / `eSanctionApplied` |
| `ENTER` / `LEAVE` | `Agent, Res, Ver` / `Agent, Res` | `eResourceEntered` / `eResourceLeft` |
| `ADAPT_START` | `Ver` | `eAdaptationStarted` |
| `ADAPT_ABORT` | `Ver` (E9 only; extend the parser) | `eAdaptationAborted` |
| `COMMIT` | `Ver, Closed=1` (`-` if none) | `eNormCommitted` |
| `HUMAN_ENTER` / `HUMAN_LEAVE` | `Res` | `eHumanEntered` / `eHumanLeft` |

plus one fleet-specific event:

| Event | Fields | Emitted by | P event |
|---|---|---|---|
| `ABANDON` | `Id, Agent, Where` (`Id` = the abandoned obligation; `Where=-1` = still at the entrance) | robot node, when it gives up | `eTaskAbandoned` |

Fleet-specific details:
- `CONFIG` lists every zone: `Capacity=0:1;1:1;2:1`.
- `COMMIT` lists the closed zones: `Closed=1`, or `Closed=-` when none are closed.
- `Site` is the partition key (one fleet or warehouse per site).
- Zone controllers, fleet manager and regulation coordinator may run on different machines, but their lines must share a clock source (NTP/PTP). By default PObserve sorts the events of each site (partition) by timestamp before monitoring; with `--assumeInputsAreSorted` it merges the files as given and reports an out-of-order event as an error (`PObserveEventOutOfOrderException`). In both modes, clock skew between nodes can reorder events and change a verdict (specification, section 5.12).

### 3.2 Build and run

The commands below have not been run against this package yet (see the status note at the top).

```bash
# once: build the PObserve CLI
git clone https://github.com/p-org/P.git
(cd P/Src/PObserve/PObserve && gradle wrapper && ./gradlew build)
export POBSERVE_JAR=/path/to/P/Src/PObserve/PObserve/build/libs/PObserve-1.0.0.jar

cd MobileRobots/pobserve
gradle wrapper
./gradlew build                 # p compile --mode pobserve, parser, JUnit tests
./gradlew uberjar               # build/libs/FleetRegulation-1.0.0-uber.jar
./run_pobserve.sh               # sample naive log, all 7 monitors
./run_pobserve.sh src/test/resources/fleet_twophase.log
./run_pobserve.sh src/test/resources/fleet_twophase.log SanctionsReflectMisconduct
```

### 3.3 JUnit tests

| Class / test | Log | Expected |
|---|---|---|
| `FleetSafetyTest.twoPhaseAdaptationIsSafe` | `fleet_twophase.log` | no violation of the 6 safety monitors |
| `FleetSafetyTest.naiveAdaptationViolatesRegulation` | `fleet_naive.log` | `PAssertionFailureException` mentioning resource 1 |
| `FleetFairnessTest.blockedRobotsAreSanctionedEvenUnderSafeAdaptation` | `fleet_twophase.log` | `PAssertionFailureException` from `SanctionsReflectMisconduct` |

### 3.4 Expected run-time results on the sample logs (Python mirror, not PObserve)

| Monitor | `fleet_twophase.log` | `fleet_naive.log` |
|---|---|---|
| RegimentationSafety | ok | **violation**: robot 1 admitted to zone 1 with a human inside (tick 3) |
| NoStaleAdmission | ok | **violation**: robot 1 admitted to zone 1, closed by v1, guard on v0 (tick 3) |
| NoDoubleOutcome | ok | ok |
| ObligationDeadlineRespected | ok | ok |
| AdaptationBoundedTime | ok | ok |
| LockoutBeforeEntry | ok | ok |
| SanctionsReflectMisconduct | **violation**: obligation 0 of robot 2 sanctioned after it was abandoned (tick 8) | **violation**: same (tick 8) |

These come from the Python mirror of the monitors (`tools/simulate_logs.py --check`, commands in section 5), not from a PObserve run. PObserve is expected to report the same first violations; confirm and record it.

The fairness violation in the *safe* log is the run-time counterpart of the counterexample we **expect** from `tcFleetSanctionFairness`; neither has been confirmed with P tools yet. In a real warehouse, the monitor gives a measurable count of sanctions on obligations abandoned after repeated denials. It does not, by itself, measure how many were caused by regulation (see 2.2).

### 3.5 More logs and real instrumentation

```bash
python3 ../../tools/simulate_logs.py --scenario fleet --policy twophase --seed 11 --ticks 300 \
        --out src/test/resources/fleet_long.log --check
```

**ROS 2.** Use `../../tools/instrumentation/regulation_log.py`. Call it from:
- each zone-controller node (`enter`/`leave`)
- the fleet manager (`obligation`/`fulfilled`/`sanction`/`tick`)
- the regulation coordinator (`adapt_start`/`commit`)
- the safety system that detects people in a zone (`human_enter`/`human_leave`)
- the robot node when it gives up (`abandon`)

Write to a dedicated file rather than through the ROS logger: rclpy adds its own prefix, which the parser does not expect.

Map robot names to stable integer ids.

### 3.6 Log assumptions and limitations

The run-time results are only as good as the log. The monitors assume:

**A tick is one step of the organization's logical clock**, logged as a `TICK` by the obligation manager before it checks deadlines. Deadlines (`Due`) are in ticks. The simulator maps one tick to one second of log time; in a real fleet, choose the tick period (e.g. 1 s) and log it consistently.

**The two bounds:**
- `ObligationDeadlineRespected` uses a grace of **1 tick**. The obligation manager sanctions at the first tick where `now > Due`, and logs the `SANCTION` *after* that `TICK` line. So an obligation due at tick *d* is resolved by tick *d+1* at the latest, and the monitor complains at tick *d+2*. One tick is the smallest grace that does not raise false alarms; in 500 simulated runs every sanction came exactly one tick after its due time. Raise it if your engine checks deadlines less often than every tick.
- `AdaptationBoundedTime` allows **5 ticks** from `ADAPT_START` to `COMMIT`. This is a design choice, not derived from the model: draining zone 1 takes as long as a robot stays in it, and a blocked robot gives up after 3 denials. In 500 simulated two-phase fleet runs, the longest adaptation, measured from `ADAPT_START` to `COMMIT` and so including protocol delay, took 3 ticks; this is an empirical value, not a bound. Set it from your domain (maximum dwell time in a zone plus the controllers' reaction time) and record why.

**Bounded monitors need later ticks.** Both bounded monitors check only when a `TICK` arrives. If the log ends before tick *d+2* (or 5 ticks after `ADAPT_START`), an unresolved obligation or adaptation is simply not reported. A clean result on a log that stops early does not show that work completed.

**Restarts.** `CONFIG` must come first for each site. `RegimentationSafety` handles `CONFIG` only in its initial state, so a second `CONFIG` after a restart is an event the monitor does not handle. P treats that as an error. Monitor state (occupancy, committed norm set, open obligations) is also not reset. Split logs at restarts and check each segment separately.

**Missing and duplicate events** produce false results, in both directions:

| Problem | Effect |
|---|---|
| missing `LEAVE` | occupancy never drops: a later `ENTER` is reported as a capacity violation, a later `HUMAN_ENTER` as an unsafe entry |
| missing `ENTER` (e.g. the log starts while a robot is in a zone) | occupancy goes negative and hides real capacity violations |
| missing `COMMIT` | the next `COMMIT` fails the version-order check; `LockoutBeforeEntry` may report a bypass that did not happen |
| missing `TICK` | bounded monitors cannot fire for that period |
| duplicate `ENTER` | false capacity violation |
| duplicate `FULFILLED` / `SANCTION` | false `NoDoubleOutcome` violation |
| duplicate `COMMIT` | false version-order violation |

**Equal timestamps.** By default PObserve sorts events by timestamp within a site; with `--assumeInputsAreSorted` it does not sort and reports out-of-order lines as errors. These guides do not establish how it orders events with equal timestamps, so do not rely on it: make timestamps strictly increasing within a site (the simulator adds 1 ms per event) and use a shared clock source (NTP/PTP) across nodes.

---

## 4. What the two layers give you

| | P checker (design time) | PObserve (run time) |
|---|---|---|
| Input | the P model | logs of the real fleet |
| Coverage | the schedules explored (`-s`), not all interleavings | the executions that actually happened, as far as they were logged |
| Liveness | hot-state monitors (`EveryObligationResolved`, `AdaptationCompletes`) | restated as bounded response (`ObligationDeadlineRespected`, 1-tick grace; `AdaptationBoundedTime`, 5 ticks) |
| Typical finding | a design flaw (naive adaptation), a candidate unfair sanction | an implementation that deviates from the design, a procedure bypass (`LockoutBeforeEntry`), flagged sanctions to investigate |

---

## 5. Validation record

Fill this in as you confirm each step. Until a row has a command, versions and actual output, treat its result as expected, not verified.

**Done so far: Python mirror only** (Python 3.13, 2026-10-20). Run from `MobileRobots/pobserve`:

```text
$ python3 ../../tools/simulate_logs.py --scenario fleet --policy twophase --seed 1 --ticks 60 --out src/test/resources/fleet_twophase.log --check
wrote 197 lines to src/test/resources/fleet_twophase.log
  ok    RegimentationSafety
  ok    NoStaleAdmission
  ok    NoDoubleOutcome
  ok    ObligationDeadlineRespected
  ok    AdaptationBoundedTime
  ok    LockoutBeforeEntry
  FAIL  SanctionsReflectMisconduct: obligation 0 of robot 2 sanctioned after it was abandoned (tick 8)

$ python3 ../../tools/simulate_logs.py --scenario fleet --policy naive --seed 2 --ticks 60 --out src/test/resources/fleet_naive.log --check
wrote 215 lines to src/test/resources/fleet_naive.log
  FAIL  RegimentationSafety: agent 1 admitted to resource 1 with a human inside (tick 3)
  FAIL  NoStaleAdmission: agent 1 admitted to resource 1 closed by v1, guard on v0 (tick 3)
  ok    NoDoubleOutcome
  ok    ObligationDeadlineRespected
  ok    AdaptationBoundedTime
  ok    LockoutBeforeEntry
  FAIL  SanctionsReflectMisconduct: obligation 0 of robot 2 sanctioned after it was abandoned (tick 8)
```

The simulator is deterministic for a given seed, so these commands reproduce the committed sample logs byte for byte.

Across 500 simulated two-phase runs (seeds 0–499, 60 ticks), there were 4,479 sanctions. An earlier version of the fairness monitor, which flagged any sanction against a robot that had *ever* abandoned a task, flagged 4,255 of them. The current monitor, which matches the obligation id, flags 3,468. The 787 difference were sanctions on later obligations unrelated to the abandoned task. F1 was violated in all 500 runs. These are counts of candidates flagged by an order-sensitive monitor, not counts of all unfair sanctions: a sanction recorded before the abandonment is not flagged (probes `probe-abandon-first.txt` and `probe-sanction-first.txt` in `reviews/evaluation-2026-10-21`; a refined monitor must flag both).

**P and PObserve steps** (rows marked "independent evaluation" were run by the reviewer, not by the students; repeat them and add your own versions and results):

| Step | Command | Tool versions | Seed / schedules | Actual result |
|---|---|---|---|---|
| Compile the model | `p compile` | P 3.1.0.0, .NET SDK 8.0.426 | — | succeeds, no warnings (independent evaluation, 2026-10-21; before L3 was added) |
| Compile for PObserve | `p compile --mode pobserve` | P 3.1.0.0 | — | Java classes generated (independent evaluation, 2026-10-21) |
| Two-phase design (E1) | `p check -tc tcFleetTwoPhase -s 100000` | P 3.1.0.0 | 30-second run, 3,442 schedules | no bug (independent evaluation, 2026-10-21); the 100,000-schedule run is still to do |
| Naive design (E2) | `p check -tc tcFleetNaive -s 10000` | P 3.1.0.0 | schedule 1 | S2 fails: robot 2 admitted under v0 to zone 1, closed by v1 (independent evaluation, 2026-10-21) |
| Fairness (E3) | `p check -tc tcFleetSanctionFairness -s 10000` | P 3.1.0.0 | schedule 1 | F1 fails, as intended (independent evaluation, 2026-10-21) |
| PObserve package build and JUnit | `./gradlew build` (pinned wrapper) | OpenJDK 17.0.20.8 | — | not run: Gradle and Maven absent, no wrapper committed |
| PObserve CLI on both sample logs | `./run_pobserve.sh <log>` | | — | |

For each failing check, keep the trace (`.txt` and `.schedule`) from `PCheckerOutput/BugFinding/` and note the seed that reproduces it.
