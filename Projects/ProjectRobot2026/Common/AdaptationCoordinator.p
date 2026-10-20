// Regulation adaptation (Yan et al., ECAI 2025: detect -> design -> execute).
//   DETECT : an eAdaptationTriggered fact arrives (e.g. a human needs a resource)
//   DESIGN : derive the next norm set (open/close one resource, version + 1)
//   EXECUTE: install it at every environment guard
//
// twoPhase = true : prepare (guards block and drain) -> all acks -> commit
// twoPhase = false: naive broadcast; commit is declared before guards install it
//                   (the "obvious" implementation, which the checker should break)
machine AdaptationCoordinator {
  var guards: seq[machine];
  var current: tNormSet;
  var pending: tNormSet;
  var requester: machine;
  var acks: set[machine];
  var twoPhase: bool;

  start state Init {
    entry (cfg: (guards: seq[machine], twoPhase: bool)) {
      guards = cfg.guards;
      twoPhase = cfg.twoPhase;
      current = (ver = 0, closed = default(set[int]));
      goto Stable;
    }
  }

  state Stable {
    on eAdaptationTriggered do (t: tTrigger) {
      var closed: set[int];
      closed = current.closed;
      if (t.close) {
        closed += (t.resource);
      } else {
        if (t.resource in closed) { closed -= (t.resource); }
      }
      pending = (ver = current.ver + 1, closed = closed);
      requester = t.requester;
      announce eAdaptationStarted, pending.ver;
      if (twoPhase) { goto Preparing; } else { goto Committing; }
    }
    ignore eNormPrepareAck;
  }

  state Preparing {
    entry {
      var i: int;
      acks = default(set[machine]);
      i = 0;
      while (i < sizeof(guards)) {
        send guards[i], eNormPrepare, (normSet = pending, coord = this);
        i = i + 1;
      }
    }
    on eNormPrepareAck do (a: tAck) {
      if (a.version == pending.ver) { acks += (a.guard); }
      if (sizeof(acks) == sizeof(guards)) { goto Committing; }
    }
    defer eAdaptationTriggered;
  }

  state Committing {
    entry {
      var i: int;
      current = pending;
      announce eNormCommitted, current;
      i = 0;
      while (i < sizeof(guards)) {
        send guards[i], eNormCommit, current;
        i = i + 1;
      }
      send requester, eAdaptationDone, current;
      goto Stable;
    }
    defer eAdaptationTriggered;
  }
}
