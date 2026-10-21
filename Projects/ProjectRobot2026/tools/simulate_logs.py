#!/usr/bin/env python3
"""
Synthetic regulation logs for the PObserve examples.

Produces structured logs in the format the PObserve parsers expect, for
  - scenario "cell"  : manufacturing cell (robot arm + AGV, one envelope)
  - scenario "fleet" : mobile robots in a 3-zone corridor
under two adaptation policies:
  - "twophase": prepare -> drain -> commit (expected to satisfy the safety monitors)
  - "naive"   : commit first, guards install later (expected to violate them)

It also re-implements the monitors in a few lines (--check), so you can see
what PObserve should report before building anything in Java. The P monitors
remain the reference; this checker is only a convenience mirror.

Log line format (one event per line):
  2026-10-19 08:00:00.001000 [cell-A] INFO Regulation - : Site=cell-A, Event=ENTER, Agent=1, Res=0, Ver=0

Events and fields:
  CONFIG       Capacity=<res>:<cap>;<res>:<cap>...
  TICK         Now
  OBLIGATION   Id, Agent, Task, Due
  FULFILLED    Id, Agent
  SANCTION     Id, Agent
  ENTER        Agent, Res, Ver
  LEAVE        Agent, Res
  ADAPT_START  Ver
  ADAPT_ABORT  Ver                (only with an abort, experiments E8/E9)
  COMMIT       Ver, Closed=<res>;<res>...  ("-" when empty)
  HUMAN_ENTER  Res
  HUMAN_LEAVE  Res
  ABANDON      Id, Agent, Where   (Id = abandoned obligation; Where=-1 means still at the entrance)

Usage:
  python3 simulate_logs.py --scenario cell  --policy twophase --seed 1 --out cell_twophase.log --check
  python3 simulate_logs.py --scenario fleet --policy naive    --seed 3 --out fleet_naive.log  --check
"""
import argparse
import datetime as dt
import random
import sys


class Log:
    def __init__(self, site):
        self.site = site
        self.lines = []
        self.events = []          # (event, dict) for the built-in checker
        self.t0 = dt.datetime(2026, 10, 19, 8, 0, 0)
        self.micro = 0
        self.now = 0

    def emit(self, event, **fields):
        self.micro += 1
        ts = self.t0 + dt.timedelta(seconds=self.now, microseconds=self.micro * 1000)
        body = ", ".join([f"Site={self.site}", f"Event={event}"] +
                         [f"{k}={v}" for k, v in fields.items()])
        self.lines.append(f"{ts.strftime('%Y-%m-%d %H:%M:%S.%f')} [{self.site}] INFO Regulation - : {body}")
        self.events.append((event, fields))


def fmt_set(s):
    return ";".join(str(x) for x in sorted(s)) if s else "-"


class Guard:
    """Environment artifact regimenting one resource."""

    def __init__(self, res, cap):
        self.res, self.cap = res, cap
        self.occ = set()
        self.ver, self.closed = 0, set()
        self.blocked = False
        self.pending_install = None   # (micro-steps left, ver, closed) in naive mode

    def request(self, log, agent):
        if self.blocked or self.res in self.closed or len(self.occ) >= self.cap:
            return False
        self.occ.add(agent)
        log.emit("ENTER", Agent=agent, Res=self.res, Ver=self.ver)
        return True

    def release(self, log, agent):
        if agent in self.occ:
            self.occ.discard(agent)
            log.emit("LEAVE", Agent=agent, Res=self.res)

    def install(self, ver, closed):
        self.ver, self.closed = ver, set(closed)

    def step_install(self):
        if self.pending_install:
            left, ver, closed = self.pending_install
            if left <= 0:
                self.install(ver, closed)
                self.pending_install = None
            else:
                self.pending_install = (left - 1, ver, closed)


class Organization:
    """Obligations, sanctions and the adaptation coordinator."""

    def __init__(self, log, guards, policy, rng):
        self.log, self.guards, self.policy, self.rng = log, guards, policy, rng
        self.next_id = 0
        self.open = {}               # id -> (agent, due)
        self.ver, self.closed = 0, set()
        self.adapting = None         # (target_ver, target_closed, affected_res)

    def assign(self, agent, task, due):
        oid = self.next_id
        self.next_id += 1
        self.open[oid] = (agent, due)
        self.log.emit("OBLIGATION", Id=oid, Agent=agent, Task=task, Due=due)
        return oid

    def report(self, oid, agent):
        if oid in self.open:
            del self.open[oid]
            self.log.emit("FULFILLED", Id=oid, Agent=agent)

    def on_tick(self, now):
        for oid, (agent, due) in sorted(self.open.items()):
            if now > due:
                del self.open[oid]
                self.log.emit("SANCTION", Id=oid, Agent=agent)

    # ---- adaptation: detect -> design -> execute ----
    def start_adaptation(self, res, close):
        target = set(self.closed)
        if close:
            target.add(res)
        else:
            target.discard(res)
        ver = self.ver + 1
        self.log.emit("ADAPT_START", Ver=ver)
        if self.policy == "naive":
            # declare first, let each guard install whenever its message arrives
            self._commit(ver, target)
            for g in self.guards.values():
                g.pending_install = (self.rng.randint(1, 3), ver, target)
            return True
        # two-phase: block the affected guard and drain it
        g = self.guards[res]
        g.blocked = True
        self.adapting = (ver, target, res)
        return self.try_finish()

    def try_finish(self):
        if not self.adapting:
            return True
        ver, target, res = self.adapting
        g = self.guards[res]
        if res in target and g.occ:
            return False          # still draining
        self._commit(ver, target)
        for gg in self.guards.values():
            gg.install(ver, target)
        g.blocked = False
        self.adapting = None
        return True

    def _commit(self, ver, target):
        self.ver, self.closed = ver, set(target)
        self.log.emit("COMMIT", Ver=ver, Closed=fmt_set(target))


class Human:
    """Requests a lock-out, enters once it is committed, leaves, requests reopening."""

    def __init__(self, res, rng, period):
        self.res, self.rng, self.period = res, rng, period
        self.state, self.timer = "outside", rng.randint(3, period)

    def step(self, log, org):
        if self.state == "outside":
            self.timer -= 1
            if self.timer <= 0:
                org.start_adaptation(self.res, close=True)
                self.state = "waiting"
        if self.state == "waiting" and org.adapting is None and self.res in org.closed:
            log.emit("HUMAN_ENTER", Res=self.res)
            self.state, self.timer = "inside", self.rng.randint(1, 3)
        elif self.state == "inside":
            self.timer -= 1
            if self.timer <= 0:
                log.emit("HUMAN_LEAVE", Res=self.res)
                org.start_adaptation(self.res, close=False)
                self.state, self.timer = "outside", self.rng.randint(4, self.period)


class CellAgent:
    def __init__(self, aid, rng, comply):
        self.id, self.rng, self.comply = aid, rng, comply
        self.job, self.inside, self.denials = None, False, 0

    def step(self, log, org, guard, now):
        if self.job is None:
            if self.rng.random() < 0.5:
                self.job = org.assign(self.id, 100 * self.id + org.next_id, now + 4)
                self.denials = 0
            return
        if not self.inside:
            if guard.request(log, self.id):
                self.inside = True
            else:
                self.denials += 1
                if self.denials >= 3:
                    log.emit("ABANDON", Id=self.job, Agent=self.id, Where=-1)
                    self.job = None
        elif self.rng.random() < 0.6:
            guard.release(log, self.id)
            self.inside = False
            if self.rng.random() < self.comply:
                org.report(self.job, self.id)
            self.job = None


class Robot:
    def __init__(self, rid, path, rng, comply):
        self.id, self.path, self.rng, self.comply = rid, path, rng, comply
        self.job, self.pos, self.denials = None, -1, 0

    def step(self, log, org, guards, now):
        if self.job is None:
            if self.rng.random() < 0.5:
                self.job = org.assign(self.id, 10 * self.id + org.next_id, now + 6)
                self.pos, self.denials = -1, 0
            return
        if self.pos + 1 == len(self.path):
            guards[self.path[self.pos]].release(log, self.id)
            if self.rng.random() < self.comply:
                org.report(self.job, self.id)
            self.job = None
            return
        nxt = self.path[self.pos + 1]
        if guards[nxt].request(log, self.id):
            if self.pos >= 0:
                guards[self.path[self.pos]].release(log, self.id)
            self.pos += 1
            self.denials = 0
        else:
            self.denials += 1
            if self.denials >= 3:
                where = self.path[self.pos] if self.pos >= 0 else -1
                log.emit("ABANDON", Id=self.job, Agent=self.id, Where=where)
                if self.pos >= 0:
                    guards[self.path[self.pos]].release(log, self.id)
                self.job, self.pos = None, -1


def simulate(scenario, policy, seed, ticks):
    rng = random.Random(seed)
    if scenario == "cell":
        log = Log("cell-A")
        guards = {0: Guard(0, 1)}
        actors = [CellAgent(1, rng, 0.9), CellAgent(2, rng, 0.9)]
        human = Human(0, rng, 12)
    else:
        log = Log("fleet-A")
        guards = {z: Guard(z, 1) for z in (0, 1, 2)}
        actors = [Robot(1, [0, 1, 2], rng, 0.9), Robot(2, [2, 1, 0], rng, 0.9)]
        human = Human(1, rng, 12)
    org = Organization(log, guards, policy, rng)
    log.emit("CONFIG", Capacity=";".join(f"{r}:{g.cap}" for r, g in guards.items()))

    for now in range(1, ticks + 1):
        log.now = now
        log.micro = 0
        log.emit("TICK", Now=now)
        org.on_tick(now)
        order = actors + [human]
        rng.shuffle(order)          # interleaving within a tick
        for a in order:
            if a is human:
                human.step(log, org)
            elif scenario == "cell":
                a.step(log, org, guards[0], now)
            else:
                a.step(log, org, guards, now)
            org.try_finish()
            for g in guards.values():
                g.step_install()
    return log


# ---------------------------------------------------------------------
# Mirror of the P monitors (convenience only; the P specs are the reference)
# ---------------------------------------------------------------------
def check(log, scenario):
    errs = {}

    def fail(mon, msg):
        errs.setdefault(mon, msg)

    cap, occ, human_in = {}, {}, {}   # human_in: resource -> people inside
    committed_ver, committed_closed = 0, set()
    resolved, open_due = set(), {}
    now, adapt_start, adapt_ver = 0, None, None
    abandoned = set()           # obligation ids abandoned after repeated denials
    for ev, f in log.events:
        if ev == "CONFIG":
            for pair in f["Capacity"].split(";"):
                r, c = pair.split(":")
                cap[int(r)] = int(c)
                occ.setdefault(int(r), 0)
        elif ev == "TICK":
            now = f["Now"]
            for oid, due in open_due.items():
                if now > due + 1:
                    fail("ObligationDeadlineRespected", f"obligation {oid} overdue at tick {now}")
            if adapt_start is not None and now - adapt_start > 5:
                fail("AdaptationBoundedTime", f"adaptation v{adapt_ver} not committed by tick {now}")
        elif ev == "ENTER":
            r = f["Res"]
            occ[r] = occ.get(r, 0) + 1
            if occ[r] > cap.get(r, 0):
                fail("RegimentationSafety", f"capacity exceeded in resource {r} at tick {now}")
            if human_in.get(r, 0) > 0:
                fail("RegimentationSafety", f"agent {f['Agent']} admitted to resource {r} with a human inside (tick {now})")
            if r in committed_closed:
                fail("NoStaleAdmission", f"agent {f['Agent']} admitted to resource {r} closed by v{committed_ver}, guard on v{f['Ver']} (tick {now})")
        elif ev == "LEAVE":
            occ[f["Res"]] -= 1
        elif ev == "HUMAN_ENTER":
            r = f["Res"]
            human_in[r] = human_in.get(r, 0) + 1
            if occ.get(r, 0) > 0:
                fail("RegimentationSafety", f"human entered resource {r} while agents were inside (tick {now})")
            if r not in committed_closed:
                fail("LockoutBeforeEntry", f"human entered resource {r} without a committed lock-out")
        elif ev == "HUMAN_LEAVE":
            human_in[f["Res"]] = max(0, human_in.get(f["Res"], 0) - 1)
        elif ev == "ADAPT_START":
            adapt_start, adapt_ver = now, f["Ver"]
        elif ev == "ADAPT_ABORT":
            adapt_start = None      # an aborted change ends the adaptation (R2)
        elif ev == "COMMIT":
            if f["Ver"] != committed_ver + 1:
                fail("NoStaleAdmission", "norm sets committed out of order")
            committed_ver = f["Ver"]
            c = f["Closed"]
            committed_closed = set() if c == "-" else {int(x) for x in str(c).split(";")}
            adapt_start = None
        elif ev == "OBLIGATION":
            open_due[f["Id"]] = f["Due"]
        elif ev in ("FULFILLED", "SANCTION"):
            if f["Id"] in resolved:
                fail("NoDoubleOutcome", f"obligation {f['Id']} resolved twice")
            resolved.add(f["Id"])
            open_due.pop(f["Id"], None)
            if ev == "SANCTION" and scenario == "fleet" and f["Id"] in abandoned:
                fail("SanctionsReflectMisconduct",
                     f"obligation {f['Id']} of robot {f['Agent']} sanctioned after it was abandoned (tick {now})")
        elif ev == "ABANDON":
            abandoned.add(f["Id"])

    monitors = ["RegimentationSafety", "NoStaleAdmission", "NoDoubleOutcome",
                "ObligationDeadlineRespected", "AdaptationBoundedTime", "LockoutBeforeEntry"]
    if scenario == "fleet":
        monitors.append("SanctionsReflectMisconduct")
    return {m: errs.get(m) for m in monitors}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", choices=["cell", "fleet"], required=True)
    ap.add_argument("--policy", choices=["twophase", "naive"], required=True)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--ticks", type=int, default=60)
    ap.add_argument("--out", required=True)
    ap.add_argument("--check", action="store_true", help="print what each monitor should report")
    a = ap.parse_args()

    log = simulate(a.scenario, a.policy, a.seed, a.ticks)
    with open(a.out, "w") as fh:
        fh.write("\n".join(log.lines) + "\n")
    print(f"wrote {len(log.lines)} lines to {a.out}")
    if a.check:
        for mon, err in check(log, a.scenario).items():
            print(f"  {'FAIL' if err else 'ok  '}  {mon}" + (f": {err}" if err else ""))


if __name__ == "__main__":
    sys.exit(main())
