// =====================================================================
// Regulation properties, written as P monitors (the monitoring capability)
// =====================================================================

// S1 Physical safety of regimented norms (CPS level).
//    (a) occupancy never exceeds capacity (no collision in the envelope / aisle)
//    (b) no agent is ever in a resource at the same time as a human
spec RegimentationSafety observes eMonitorConfig, eResourceEntered, eResourceLeft,
                                  eHumanEntered, eHumanLeft {
  var capacity: map[int, int];
  var occupancy: map[int, int];
  var humanIn: set[int];

  start state Init {
    on eMonitorConfig do (c: map[int, int]) { capacity = c; goto Watching; }
  }

  state Watching {
    on eResourceEntered do (e: tEnter) {
      if (!(e.res in occupancy)) { occupancy[e.res] = 0; }
      occupancy[e.res] = occupancy[e.res] + 1;
      assert occupancy[e.res] <= capacity[e.res],
        format("capacity norm violated in resource {0}", e.res);
      assert !(e.res in humanIn),
        format("agent {0} admitted to resource {1} while a human is inside", e.agent, e.res);
    }
    on eResourceLeft do (l: tLeave) {
      occupancy[l.res] = occupancy[l.res] - 1;
    }
    on eHumanEntered do (r: int) {
      humanIn += (r);
      assert !(r in occupancy) || occupancy[r] == 0,
        format("human entered resource {0} while agents were inside", r);
    }
    on eHumanLeft do (r: int) {
      if (r in humanIn) { humanIn -= (r); }
    }
  }
}

// S2 No stale admission (organization level). Once a norm set is committed,
//    no guard admits an agent to a resource that norm set closes. Versions
//    are committed in order.
spec NoStaleAdmission observes eNormCommitted, eResourceEntered {
  var committed: tNormSet;

  start state Watching {
    entry { committed = (ver = 0, closed = default(set[int])); }
    on eNormCommitted do (n: tNormSet) {
      assert n.ver == committed.ver + 1, "norm sets must be committed in version order";
      committed = n;
    }
    on eResourceEntered do (e: tEnter) {
      assert !(e.res in committed.closed),
        format("agent {0} admitted to resource {1}, closed by committed norm set v{2} (guard still on v{3})",
               e.agent, e.res, committed.ver, e.ver);
    }
  }
}

// S3 An obligation is never both fulfilled and sanctioned.
spec NoDoubleOutcome observes eObligationFulfilled, eSanctionApplied {
  var resolved: set[int];

  start state Watching {
    on eObligationFulfilled do (o: tOutcome) { Resolve(o.id); }
    on eSanctionApplied do (o: tOutcome) { Resolve(o.id); }
  }

  fun Resolve(id: int) {
    assert !(id in resolved), format("obligation {0} resolved twice", id);
    resolved += (id);
  }
}

// L1 Every obligation is eventually fulfilled or sanctioned (liveness, hot state).
spec EveryObligationResolved observes eObligationCreated, eObligationFulfilled, eSanctionApplied {
  var pending: set[int];

  start cold state NoneOpen {
    on eObligationCreated do (o: tObligation) { pending += (o.id); goto SomeOpen; }
    on eObligationFulfilled, eSanctionApplied do (o: tOutcome) {
      assert false, format("outcome for unknown obligation {0}", o.id);
    }
  }

  hot state SomeOpen {
    on eObligationCreated do (o: tObligation) { pending += (o.id); }
    on eObligationFulfilled, eSanctionApplied do (o: tOutcome) {
      if (o.id in pending) { pending -= (o.id); }
      if (sizeof(pending) == 0) { goto NoneOpen; }
    }
  }
}

// L2 Every adaptation that starts is eventually committed.
//    Breaks if a guard can never drain (an agent that never leaves).
spec AdaptationCompletes observes eAdaptationStarted, eNormCommitted {
  start cold state Idle {
    on eAdaptationStarted goto InProgress;
    ignore eNormCommitted;
  }
  hot state InProgress {
    on eNormCommitted goto Idle;
  }
}
