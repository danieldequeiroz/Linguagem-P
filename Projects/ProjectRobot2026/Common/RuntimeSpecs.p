// =====================================================================
// Runtime-only monitors (PObserve).
//
// A log is finite and PObserve reports assertion failures, so the liveness
// monitors of Specs.p (hot states) are restated here as bounded-response
// SAFETY properties over logged time. They observe eTick, i.e. the
// organization engine must log its clock.
//
// R1 and R2 are NOT used in the checker tests: there eTick is observed when
// the Clock sends it, before the ObligationManager processes it, so they
// would raise false alarms on the model. R3 does not read eTick and is
// checked at design time too.
//
// Bounds: GRACE = 1 tick (the engine sanctions at the first tick past Due
// and logs the sanction after that tick) and MAX = 5 ticks (a design choice;
// set it from the domain). See INSTRUCTIONS.md, "Log assumptions and limitations".
// =====================================================================

// R1 Every obligation is fulfilled or sanctioned within GRACE ticks of its due time.
spec ObligationDeadlineRespected observes eObligationCreated, eObligationFulfilled,
                                          eSanctionApplied, eTick {
  var open: map[int, int];      // obligation id -> due
  var grace: int;

  start state Watching {
    entry { grace = 1; }
    on eObligationCreated do (o: tObligation) { open[o.id] = o.due; }
    on eObligationFulfilled do (o: tOutcome) { if (o.id in open) { open -= (o.id); } }
    on eSanctionApplied do (o: tOutcome) { if (o.id in open) { open -= (o.id); } }
    on eTick do (now: int) {
      var ids: seq[int];
      var i: int;
      ids = keys(open);
      i = 0;
      while (i < sizeof(ids)) {
        assert now <= open[ids[i]] + grace,
          format("obligation {0} is overdue (due {1}, now {2}) but was neither fulfilled nor sanctioned",
                 ids[i], open[ids[i]], now);
        i = i + 1;
      }
    }
  }
}

// R2 Every adaptation commits within MAX ticks (bounded version of L2).
//    A failure points to a resource that could not be drained.
spec AdaptationBoundedTime observes eAdaptationStarted, eNormCommitted, eTick {
  var now: int;
  var startedAt: int;
  var pendingVer: int;
  var maxTicks: int;

  start state Idle {
    entry { maxTicks = 5; }
    on eTick do (t: int) { now = t; }
    on eAdaptationStarted do (v: int) { pendingVer = v; startedAt = now; goto InProgress; }
    ignore eNormCommitted;
  }

  state InProgress {
    on eTick do (t: int) {
      now = t;
      assert now - startedAt <= maxTicks,
        format("adaptation to norm set v{0} started at tick {1} and is still not committed at tick {2}",
               pendingVer, startedAt, now);
    }
    on eNormCommitted do (n: tNormSet) { goto Idle; }
  }
}

// R3 Lock-out before entry: a human enters a resource only while the committed
//    norm set closes it to agents (catches procedure bypass on the shop floor).
spec LockoutBeforeEntry observes eNormCommitted, eHumanEntered {
  var closed: set[int];

  start state Watching {
    on eNormCommitted do (n: tNormSet) { closed = n.closed; }
    on eHumanEntered do (r: int) {
      assert r in closed,
        format("human entered resource {0} without a committed lock-out", r);
    }
  }
}
