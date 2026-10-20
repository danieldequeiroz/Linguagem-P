# Verified Regulation Management for a Mobile Robot Fleet (P + PObserve)

Starter kit for the graduate project. Two robots cross a three-zone corridor head-on, and a human picker needs zone 1 closed. Regulation is **distributed**: one controller per zone, coordinated only by messages.

## Layout

```
ProjectRobot2026/
├── Common/            shared P model machines and monitors
│   ├── MonitorEvents.p    what the monitors observe (shared by checker and PObserve)
│   ├── Specs.p            monitors S1-S3, L1-L2, R3
│   ├── RuntimeSpecs.p     run-time monitors R1-R3
│   └── Types.p, Clock.p, ObligationManager.p, AdaptationCoordinator.p, ResourceGuard.p, HumanRequester.p
├── MobileRobots/      the fleet model, fairness monitor, tests, PObserve package
│   └── INSTRUCTIONS.md    step-by-step commands (start here)
└── tools/
    ├── simulate_logs.py          synthetic logs + a Python preview of the monitor results
    └── instrumentation/          regulation_log.py (ROS 2 / Python), RegulationLog.java (JaCaMo)
```

## Quick start

```bash
cd MobileRobots
p compile
p check -tc tcFleetNaive -s 10000
p check -tc tcFleetSanctionFairness -s 10000

# preview monitor results on a log without any toolchain
python3 ../tools/simulate_logs.py --scenario fleet --policy naive --seed 2 --out fleet.log --check
```

## Status

- P files (`.p`): drafts, not yet compiled. Expect small syntax fixes on the first `p compile`.
- Java log parser: compiled against PObserve's interfaces and run on the sample logs.
- Sample logs and expected monitor results: from `tools/simulate_logs.py`.
