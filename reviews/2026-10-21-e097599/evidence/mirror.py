#!/usr/bin/env python3
"""Independent Python transcription of the P monitors at snapshot e097599
(Common/Specs.p, Common/RuntimeSpecs.p, MobileRobots/PSpec/FleetSpecs.p).

Written by the Claude reviewer without reusing tools/simulate_logs.py or
reviews/evaluation-2026-10-21/verify_samples.py. It models P monitor semantics
that matter here: an observed event with no handler in the current state is an
error (UNHANDLED), a missing map key is an error (KEYERR), hot state at end of
trace is reported (not a failure for a finite log). This is a mirror, not P.
"""
import sys

def parse(path):
    evs = []
    for line in open(path):
        if " - : " not in line:
            continue
        body = line.split(" - : ", 1)[1].strip()
        f = dict(p.split("=", 1) for p in body.split(", "))
        evs.append(f)
    return evs

def iset(v):
    return set() if v in (None, "", "-") else {int(x) for x in v.split(";")}

class Fail(Exception):
    pass

def S1(evs):
    st, cap, occ, hum = "Init", {}, {}, set()
    for e in evs:
        k = e["Event"]
        if k not in ("CONFIG", "ENTER", "LEAVE", "HUMAN_ENTER", "HUMAN_LEAVE"):
            continue
        if st == "Init":
            if k != "CONFIG":
                raise Fail(f"UNHANDLED {k} in Init")
            cap = {int(a): int(b) for a, b in (p.split(":") for p in e["Capacity"].split(";"))}
            st = "Watching"; continue
        if k == "CONFIG":
            raise Fail("UNHANDLED CONFIG in Watching")
        if k == "ENTER":
            r = int(e["Res"]); occ[r] = occ.get(r, 0) + 1
            if r not in cap: raise Fail(f"KEYERR capacity[{r}]")
            if occ[r] > cap[r]: raise Fail(f"capacity norm violated in resource {r}")
            if r in hum: raise Fail(f"agent {e['Agent']} admitted to resource {r} while a human is inside (tick {e.get('_t')})")
        elif k == "LEAVE":
            r = int(e["Res"])
            if r not in occ: raise Fail(f"KEYERR occupancy[{r}]")
            occ[r] -= 1
        elif k == "HUMAN_ENTER":
            r = int(e["Res"]); hum.add(r)
            if occ.get(r, 0) != 0: raise Fail(f"human entered resource {r} while agents were inside")
        elif k == "HUMAN_LEAVE":
            hum.discard(int(e["Res"]))
    return "ok"

def S2(evs):
    ver, closed = 0, set()
    for e in evs:
        if e["Event"] == "COMMIT":
            if int(e["Ver"]) != ver + 1: raise Fail("version order")
            ver, closed = int(e["Ver"]), iset(e.get("Closed"))
        elif e["Event"] == "ENTER" and int(e["Res"]) in closed:
            raise Fail(f"agent {e['Agent']} admitted to resource {e['Res']}, closed by v{ver} (guard on v{e['Ver']}) (tick {e.get('_t')})")
    return "ok"

def S3(evs):
    res = set()
    for e in evs:
        if e["Event"] in ("FULFILLED", "SANCTION"):
            i = int(e["Id"])
            if i in res: raise Fail(f"obligation {i} resolved twice")
            res.add(i)
    return "ok"

def L1(evs):
    pend, hot = set(), False
    for e in evs:
        k = e["Event"]
        if k == "OBLIGATION": pend.add(int(e["Id"])); hot = True
        elif k in ("FULFILLED", "SANCTION"):
            if not hot: raise Fail(f"outcome for unknown obligation {e['Id']}")
            pend.discard(int(e["Id"]))
            if not pend: hot = False
    return "ok (hot at end)" if hot else "ok (cold at end)"

def L2(evs):
    st = "Idle"
    for e in evs:
        k = e["Event"]
        if st == "Idle":
            if k == "ADAPT_START": st = "InProgress"
        else:
            if k == "COMMIT": st = "Idle"
            elif k == "ADAPT_START": raise Fail("UNHANDLED eAdaptationStarted in hot InProgress")
    return f"ok ({'hot' if st != 'Idle' else 'cold'} at end)"

def L3(evs):
    st, pv = "Idle", None
    for e in evs:
        k = e["Event"]
        if st == "Idle":
            if k == "ADAPT_START": pv = int(e["Ver"]); st = "InProgress"
        else:
            if k in ("COMMIT", "ADAPT_ABORT"):
                if int(e["Ver"]) != pv: raise Fail(f"{k} v{e['Ver']} while v{pv} pending")
                st = "Idle"
            elif k == "ADAPT_START": raise Fail("UNHANDLED eAdaptationStarted in hot InProgress")
    return f"ok ({'hot' if st != 'Idle' else 'cold'} at end)"

def R1(evs):
    op = {}
    for e in evs:
        k = e["Event"]
        if k == "OBLIGATION": op[int(e["Id"])] = int(e["Due"])
        elif k in ("FULFILLED", "SANCTION"): op.pop(int(e["Id"]), None)
        elif k == "TICK":
            n = int(e["Now"])
            for i, d in op.items():
                if n > d + 1: raise Fail(f"obligation {i} overdue (due {d}, now {n})")
    return "ok"

def R2(evs):
    st, now, t0 = "Idle", 0, 0
    for e in evs:
        k = e["Event"]
        if k == "TICK":
            now = int(e["Now"])
            if st == "InProgress" and now - t0 > 5: raise Fail(f"adaptation started at {t0} not committed at {now}")
        elif k == "ADAPT_START":
            if st == "InProgress": raise Fail("UNHANDLED eAdaptationStarted in InProgress")
            st, t0 = "InProgress", now
        elif k == "COMMIT" and st == "InProgress":
            st = "Idle"
    return "ok"

def R3(evs):
    closed = set()
    for e in evs:
        if e["Event"] == "COMMIT": closed = iset(e.get("Closed"))
        elif e["Event"] == "HUMAN_ENTER" and int(e["Res"]) not in closed:
            raise Fail(f"human entered resource {e['Res']} without a committed lock-out")
    return "ok"

def F1(evs):
    ab = set()
    for e in evs:
        if e["Event"] == "ABANDON": ab.add(int(e["Id"]))
        elif e["Event"] == "SANCTION" and int(e["Id"]) in ab:
            raise Fail(f"obligation {e['Id']} of robot {e['Agent']} sanctioned after abandonment (tick {e.get('_t')})")
    return "ok"

MON = [("RegimentationSafety", S1), ("NoStaleAdmission", S2), ("NoDoubleOutcome", S3),
       ("EveryObligationResolved", L1), ("AdaptationCompletes", L2), ("AdaptationTerminates", L3),
       ("ObligationDeadlineRespected", R1), ("AdaptationBoundedTime", R2),
       ("LockoutBeforeEntry", R3), ("SanctionsReflectMisconduct", F1)]

def run(evs, label):
    t = 0
    for e in evs:
        if e["Event"] == "TICK": t = int(e["Now"])
        e["_t"] = t
    print(f"== {label}")
    for name, m in MON:
        try:
            r = m(evs)
        except Fail as x:
            r = "FAIL  " + str(x)
        print(f"  {name:28s} {r}")

if __name__ == "__main__":
    for p in sys.argv[1:]:
        run(parse(p), p)
