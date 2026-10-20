# Verified Regulation Management for a Manufacturing Cell (P + PObserve)

Starter kit for the graduate project. A robot arm and an AGV share one work envelope, and a technician needs a lock-out before entering. Regulation is **centralized**: one cell controller and one organizational engine.

## Layout

```
ProjectManufacturingCell2026/
├── Common/            shared P model machines and monitors
│   ├── MonitorEvents.p    what the monitors observe (shared by checker and PObserve)
│   ├── Specs.p            monitors S1-S3, L1-L2, R3
│   ├── RuntimeSpecs.p     run-time monitors R1-R3
│   └── Types.p, Clock.p, ObligationManager.p, AdaptationCoordinator.p, ResourceGuard.p, HumanRequester.p
├── ManufacturingCell/ the cell model, tests, PObserve package
│   └── INSTRUCTIONS.md    step-by-step commands (start here)
└── tools/
    ├── simulate_logs.py          synthetic logs + a Python preview of the monitor results
    └── instrumentation/          RegulationLog.java (JaCaMo), regulation_log.py (Python)
```

## Quick start

```bash
cd ManufacturingCell
p compile
p check -tc tcCellNaive -s 10000

# preview monitor results on a log without any toolchain
python3 ../tools/simulate_logs.py --scenario cell --policy naive --seed 2 --out cell.log --check
```

## Status

- P files (`.p`): drafts, not yet compiled. Expect small syntax fixes on the first `p compile`.
- Java log parser: compiled against PObserve's interfaces and run on the sample logs.
- Sample logs and expected monitor results: from `tools/simulate_logs.py`.
