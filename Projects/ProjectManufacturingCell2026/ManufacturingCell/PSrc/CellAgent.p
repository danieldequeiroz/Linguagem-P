// Scenario A: manufacturing cell.
// A robot arm and an AGV share one work envelope (resource CELL, capacity 1).
// Each agent receives a job obligation, asks the cell controller for the
// envelope, works, then releases it. As an open-MAS agent it may also fail
// to report the job (nondeterministic $). The organization then sanctions it.
fun CELL(): int { return 0; }

machine CellAgent {
  var id: int;
  var guard: machine;
  var om: machine;
  var resource: int;
  var job: tObligation;
  var attempts: int;

  start state Init {
    entry (cfg: (id: int, guard: machine, om: machine, resource: int)) {
      id = cfg.id;
      guard = cfg.guard;
      om = cfg.om;
      resource = cfg.resource;
      goto Idle;
    }
  }

  state Idle {
    on eObligationNotice do (o: tObligation) {
      job = o;
      attempts = 0;
      goto Requesting;
    }
    ignore eSanction;
  }

  state Requesting {
    entry {
      attempts = attempts + 1;
      send guard, eAccessRequest, (agent = id, agentRef = this, resource = resource);
    }
    on eAccessGranted do (g: tGrant) { goto Working; }
    on eAccessDenied do (r: int) {
      if (attempts < 3) { goto Requesting; } else { goto Idle; }   // gives up: will be sanctioned
    }
    defer eObligationNotice;
    ignore eSanction;
  }

  // Occupancy window: between the guard's admission and its processing of eRelease.
  state Working {
    entry { send this, eContinue; }
    on eContinue do {
      send guard, eRelease, (agent = id, agentRef = this, resource = resource);
      if ($) { send om, eReportFulfilled, (id = job.id, agent = id); }
      goto Idle;
    }
    defer eObligationNotice;
    ignore eSanction;
  }
}

// Centralized architectural style: a single cell controller (guard) and one
// organizational engine. Grid cell: organization-centric + environment-centric,
// centralized.
machine ManufacturingSystem {
  start state Init {
    entry (twoPhase: bool) {
      var capacity: map[int, int];
      var cell: machine;
      var guards: seq[machine];
      var coord: machine;
      var om: machine;
      var arm: machine;
      var agv: machine;
      var subscribers: seq[machine];

      capacity[CELL()] = 1;
      announce eMonitorConfig, capacity;

      cell = new ResourceGuard((resource = CELL(), capacity = 1));
      guards += (0, cell);
      coord = new AdaptationCoordinator((guards = guards, twoPhase = twoPhase));
      om = new ObligationManager();

      arm = new CellAgent((id = 1, guard = cell, om = om, resource = CELL()));
      agv = new CellAgent((id = 2, guard = cell, om = om, resource = CELL()));

      // Obligations are queued before the clock exists, so no deadline can pass unseen.
      send om, eAssignTask, (agent = 1, agentRef = arm, task = 100, due = 4);
      send om, eAssignTask, (agent = 2, agentRef = agv, task = 200, due = 6);

      subscribers += (0, om);
      new Clock((subscribers = subscribers, maxTicks = 10));

      // A maintenance technician needs to enter the cell at some point.
      new HumanRequester((coord = coord, resource = CELL()));
    }
  }
}
