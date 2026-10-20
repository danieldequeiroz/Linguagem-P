# Mobile autonomous robots: instructions

Two robots deliver through a narrow corridor in opposite directions:

```
   [zone 0] ── [zone 1] ── [zone 2]       each zone: capacity 1, its own zone controller
   robot 1:  0 → 1 → 2                    robot 2:  2 → 1 → 0
```

A human picker needs zone 1, which must first be **closed to robots** (adaptation). A robot keeps its zone until the next one is granted. After 3 denials it parks in a side bay and abandons the delivery, and the organization then sanctions it.

Grid cell (Yan et al., COINE 2025): **hybrid (environment + organization + agent), distributed**. There is one regulator per zone, coordinated only by the adaptation protocol.

The workflow has two parts, using the **same P monitors**:
1. Model-check the design (part 2).
2. Check real logs with PObserve (part 3).

This example adds a third, fleet-specific monitor: **sanction fairness**.

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

---

## 2. Design time: model checking

```bash
cd MobileRobots
p compile
p check -tc tcFleetTwoPhase         -s 10000
p check -tc tcFleetNaive            -s 10000
p check -tc tcFleetSanctionFairness -s 10000
```

| Test | Expected | Meaning |
|---|---|---|
| `tcFleetTwoPhase` | no bug found | Closing zone 1 drains it before the picker is admitted. Only the affected zone controller blocks; zones 0 and 2 keep serving |
| `tcFleetNaive` | bug in `RegimentationSafety` or `NoStaleAdmission` | Zone 1's controller is still on the old norm set and admits a robot after the closure was committed, or the picker enters while a robot is in zone 1 |
| `tcFleetSanctionFairness` | bug in `SanctionsReflectMisconduct` (**intended**) | A robot blocked by the closure or by the head-on conflict is sanctioned for missing its deadline |

When a bug is found, the checker writes a trace under `PCheckerOutput/BugFinding/`. Its last lines name the failing monitor and its message; read it bottom-up to find the interleaving, and re-run with the printed seed to reproduce it. For the fairness trace, look for `eTaskAbandoned` followed later by `eSanctionApplied` for the same agent.

### 2.1 Experiments worth running

| Change | Where | What to look for |
|---|---|---|
| Block **all** zone controllers during prepare (drop the "unaffected guard acks at once" branch) | `Common/ResourceGuard.p`, `Open.eNormPrepare` | Drain now depends on parking. A robot in zone 1 cannot advance to a blocked zone 2. Remove parking as well and `AdaptationCompletes` should fail |
| Remove parking (retry forever) | `PSrc/Robot.p`, `eAccessDenied` | Head-on hold-and-wait: robots in zones 1 and 2 wait for each other forever. Expect `AdaptationCompletes` to fail when zone 1 must drain |
| Add a traffic norm: one direction per corridor (e.g. a `DirectionGuard` granting the corridor to one direction at a time) | new machine | Does `SanctionsReflectMisconduct` then fail only on closures? That isolates the adaptation-induced unfairness |
| Suspend deadlines while the regulation blocks an agent | `ObligationManager` | `SanctionsReflectMisconduct` should hold: the remedy is verified |

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
| `COMMIT` | `Ver, Closed=1` (`-` if none) | `eNormCommitted` |
| `HUMAN_ENTER` / `HUMAN_LEAVE` | `Res` | `eHumanEntered` / `eHumanLeft` |

plus one fleet-specific event:

| Event | Fields | Emitted by | P event |
|---|---|---|---|
| `ABANDON` | `Agent, Where` (`-1` = blocked at the entrance) | robot node, when it gives up | `eTaskAbandoned` |

Fleet-specific details:
- `CONFIG` lists every zone: `Capacity=0:1;1:1;2:1`.
- `COMMIT` lists the closed zones: `Closed=1`, or `Closed=-` when none are closed.
- `Site` is the partition key (one fleet or warehouse per site).
- Zone controllers, fleet manager and regulation coordinator may run on different machines, but their lines must share a clock source (NTP/PTP): PObserve orders events by timestamp within a site.

### 3.2 Build and run

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

### 3.4 Expected run-time results on the sample logs

| Monitor | `fleet_twophase.log` | `fleet_naive.log` |
|---|---|---|
| RegimentationSafety | ok | **violation**: robot 1 admitted to zone 1 with a human inside (tick 3) |
| NoStaleAdmission | ok | **violation**: robot 1 admitted to zone 1, closed by v1, guard on v0 (tick 3) |
| NoDoubleOutcome | ok | ok |
| ObligationDeadlineRespected | ok | ok |
| AdaptationBoundedTime | ok | ok |
| LockoutBeforeEntry | ok | ok |
| SanctionsReflectMisconduct | **violation**: robot 2 sanctioned after being blocked | **violation** |

These come from the Python mirror of the monitors in `tools/simulate_logs.py --check`; PObserve should report the same first violations.

The fairness violation in the *safe* log is the run-time version of the checker finding. In a real warehouse, the monitor turns it into a measurable signal: how often agents are sanctioned for situations the regulation itself created.

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
