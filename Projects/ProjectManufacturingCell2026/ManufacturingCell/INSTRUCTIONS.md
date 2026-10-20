# Manufacturing cell: instructions

A robot arm and an AGV share one work envelope (resource `0`, capacity 1). A single cell controller regiments access to it, and one organizational engine manages job obligations. A maintenance technician triggers a **lock-out adaptation** before entering the cell.

Grid cell (Yan et al., COINE 2025): **organization-centric + environment-centric, centralized**.

You will do two things with the **same P monitors**:

1. **Design time.** Model-check the regulation design with the P checker (part 2).
2. **Run time.** Check logs from a running cell against those monitors with PObserve (part 3).

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

Check the installation: `p --version`, `java -version`, `gradle --version`.

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

`-s` sets the number of schedules explored. Raise it (100000) for more confidence on the passing test.

### 2.3 Read the results

| Test | Expected | Meaning |
|---|---|---|
| `tcCellTwoPhase` | no bug found | The regulation design is safe under every explored interleaving |
| `tcCellNaive` | bug found in `RegimentationSafety` or `NoStaleAdmission` | The technician is admitted while the arm is still in the envelope, or the controller admits an agent on the old norm set |

When a bug is found, the checker writes a trace under `PCheckerOutput/BugFinding/`. To read it:
1. Open the `.txt` log. Its last lines name the failing monitor and its message (e.g. *human entered resource 0 while agents were inside*).
2. Read it bottom-up. Find the `eNormCommitted` announcement, then the `eHumanEntered`, then the agent's `eResourceEntered`/`eResourceLeft`. The interleaving between them is the counterexample.
3. Re-run with `--seed <n>` (printed in the log) to reproduce the same schedule while you fix the model.

### 2.4 Experiments worth running

| Change | Where | What to look for |
|---|---|---|
| Agents never release the envelope (remove the `send guard, eRelease` in `Working`) | `PSrc/CellAgent.p` | `AdaptationCompletes` fails: the lock-out can never drain. This argues for a physical e-stop below the MAS |
| Shorter deadlines (`due = 2`) | `ManufacturingSystem` | More sanctions; `EveryObligationResolved` must still hold |
| Two technicians | add a second `HumanRequester` | Overlapping adaptations are serialized by `defer` in the coordinator |

---

## 3. Run time: PObserve

PObserve replays structured logs of a running system through the same P monitors. The monitors are compiled to Java (`p compile --mode pobserve`), and a log parser turns each log line into a P event.

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

### 3.6 Expected run-time results on the sample logs

| Monitor | `cell_twophase.log` | `cell_naive.log` |
|---|---|---|
| RegimentationSafety | ok | **violation**: human entered resource 0 while agents were inside (tick 3) |
| NoStaleAdmission | ok | **violation**: agent 2 admitted to resource 0, closed by v1, guard on v0 (tick 3) |
| NoDoubleOutcome | ok | ok |
| ObligationDeadlineRespected | ok | ok |
| AdaptationBoundedTime | ok | ok |
| LockoutBeforeEntry | ok | ok |

These come from the Python mirror of the monitors (`python3 ../tools/simulate_logs.py ... --check`), not from a PObserve run. PObserve stops at the first violation per spec and key.

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

---

## 4. What the two layers give you

| | P checker (design time) | PObserve (run time) |
|---|---|---|
| Input | the P model | logs of the real cell |
| Coverage | many interleavings of the model | the executions that actually happened |
| Liveness | hot-state monitors (`EveryObligationResolved`, `AdaptationCompletes`) | restated as bounded response (`ObligationDeadlineRespected`, `AdaptationBoundedTime`) |
| Typical finding | a design flaw (naive adaptation) | an implementation that deviates from the verified design, or a procedure bypass (`LockoutBeforeEntry`) |
