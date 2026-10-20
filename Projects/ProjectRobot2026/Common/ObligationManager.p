// Organization-centric regulation: creates obligations, detects violations
// at the deadline and applies sanctions (enforcement by sanctioning).
// Plays the role of an NPL/Moise organizational engine in JaCaMo.
machine ObligationManager {
  var open: map[int, tObligation];
  var agentRefs: map[int, machine];
  var nextId: int;

  start state Active {
    entry { nextId = 0; }

    on eAssignTask do (req: tTaskReq) {
      var o: tObligation;
      o = (id = nextId, agent = req.agent, task = req.task, due = req.due);
      nextId = nextId + 1;
      open[o.id] = o;
      agentRefs[o.id] = req.agentRef;
      announce eObligationCreated, o;
      send req.agentRef, eObligationNotice, o;
    }

    on eReportFulfilled do (r: tOutcome) {
      // A late report (after the sanction) is ignored: the outcome is final.
      if (r.id in open) {
        open -= (r.id);
        announce eObligationFulfilled, r;
      }
    }

    on eTick do (now: int) {
      var ids: seq[int];
      var i: int;
      var o: tObligation;
      ids = keys(open);
      i = 0;
      while (i < sizeof(ids)) {
        o = open[ids[i]];
        if (now > o.due) {
          open -= (o.id);
          send agentRefs[o.id], eSanction, (id = o.id, agent = o.agent);
          announce eSanctionApplied, (id = o.id, agent = o.agent);
        }
        i = i + 1;
      }
    }
  }
}
