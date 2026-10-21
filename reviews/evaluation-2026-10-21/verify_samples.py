"""Read-only evaluation of sample reproducibility and simulated monitor results."""
import json
import pathlib
import runpy

repo = pathlib.Path(__file__).resolve().parents[2]
results = {}
for project, sub, scenario in [
    ('ProjectRobot2026', 'MobileRobots', 'fleet'),
    ('ProjectManufacturingCell2026', 'ManufacturingCell', 'cell'),
]:
    root = repo / 'Projects' / project
    mod = runpy.run_path(str(root / 'tools/simulate_logs.py'))
    samples = []
    for policy, seed in [('twophase', 1), ('naive', 2)]:
        log = mod['simulate'](scenario, policy, seed, 60)
        committed = root / sub / 'pobserve/src/test/resources' / f'{scenario}_{policy}.log'
        samples.append(dict(policy=policy, seed=seed, ticks=60, lines=len(log.lines),
                            matches_after_newline_normalization=committed.read_text() == '\n'.join(log.lines) + '\n',
                            verdicts=mod['check'](log, scenario)))
    failures = {}
    sanctions = legacy_flags = current_flags = 0
    durations = []
    examples = {}
    for seed in range(500):
        log = mod['simulate'](scenario, 'twophase', seed, 60)
        for monitor, error in mod['check'](log, scenario).items():
            if error:
                failures[monitor] = failures.get(monitor, 0) + 1
                examples.setdefault(monitor, dict(seed=seed, message=error))
        now = 0
        start = None
        blocked_agents = set()
        abandoned_ids = set()
        for event, f in log.events:
            if event == 'TICK':
                now = f['Now']
            elif event == 'ADAPT_START':
                start = now
            elif event == 'COMMIT' and start is not None:
                durations.append(now - start)
                start = None
            elif event == 'ABANDON':
                blocked_agents.add(f['Agent'])
                abandoned_ids.add(f['Id'])
            elif event == 'SANCTION':
                sanctions += 1
                legacy_flags += f['Agent'] in blocked_agents
                current_flags += f['Id'] in abandoned_ids
    results[scenario] = dict(samples=samples, two_phase_500_seeds=dict(
        ticks=60, seeds='0..499', failing_runs=failures, first_examples=examples,
        completed_adaptations=len(durations), maximum_adaptation_ticks=max(durations),
        adaptations_over_5_ticks=sum(d > 5 for d in durations), sanctions=sanctions,
        flags_with_legacy_agent_matching=legacy_flags, flags_with_obligation_matching=current_flags))

out = pathlib.Path(__file__).with_name('python-verification.json')
out.write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print(json.dumps(results, indent=2))
