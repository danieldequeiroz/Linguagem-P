// Environment-centric regimentation: an artifact (cell PLC, zone controller)
// that admits an agent to a physical resource only if the current norm set
// allows it. Agents cannot bypass it, so its norms are regimented.
machine ResourceGuard {
  var resource: int;
  var capacity: int;
  var occupants: set[int];
  var normSet: tNormSet;
  var preparing: tNormSet;
  var coord: machine;

  start state Init {
    entry (cfg: (resource: int, capacity: int)) {
      resource = cfg.resource;
      capacity = cfg.capacity;
      normSet = (ver = 0, closed = default(set[int]));
      goto Open;
    }
  }

  state Open {
    on eAccessRequest do (r: tAccess) {
      if (!(resource in normSet.closed) && sizeof(occupants) < capacity) {
        occupants += (r.agent);
        announce eResourceEntered, (agent = r.agent, res = resource, ver = normSet.ver);
        send r.agentRef, eAccessGranted, (resource = resource, version = normSet.ver);
      } else {
        send r.agentRef, eAccessDenied, resource;
      }
    }
    on eRelease do (r: tAccess) { Leave(r.agent); }

    // Phase 1. A guard whose resource is unaffected acks at once and keeps
    // serving; an affected guard blocks and drains before acking.
    on eNormPrepare do (p: tPrepare) {
      preparing = p.normSet;
      coord = p.coord;
      if ((resource in preparing.closed) == (resource in normSet.closed)) {
        send coord, eNormPrepareAck, (version = preparing.ver, guard = this);
      } else {
        goto Draining;
      }
    }

    // Phase 2 (or the only phase, in naive mode).
    on eNormCommit do (n: tNormSet) { normSet = n; }
  }

  state Draining {
    entry {
      if (!(resource in preparing.closed) || sizeof(occupants) == 0) {
        send coord, eNormPrepareAck, (version = preparing.ver, guard = this);
        goto AwaitCommit;
      }
    }
    on eAccessRequest do (r: tAccess) { send r.agentRef, eAccessDenied, resource; }
    on eRelease do (r: tAccess) { Leave(r.agent); goto Draining; }
  }

  state AwaitCommit {
    on eAccessRequest do (r: tAccess) { send r.agentRef, eAccessDenied, resource; }
    on eRelease do (r: tAccess) { Leave(r.agent); }
    on eNormCommit do (n: tNormSet) { normSet = n; goto Open; }
  }

  fun Leave(a: int) {
    if (a in occupants) {
      occupants -= (a);
      announce eResourceLeft, (agent = a, res = resource);
    }
  }
}
