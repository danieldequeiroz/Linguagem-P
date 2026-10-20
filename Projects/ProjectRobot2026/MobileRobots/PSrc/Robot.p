// Scenario B: mobile autonomous robots in a narrow corridor.
//
//   [zone 0] -- [zone 1] -- [zone 2]      each zone: capacity 1, own controller
//
// Robot 1 delivers 0 -> 1 -> 2 and robot 2 delivers 2 -> 1 -> 0 (head-on).
// A human picker needs zone 1, which must be closed to robots first.
// A robot keeps its current zone until the next one is granted (it cannot
// vanish). After 3 denials it parks in a side bay, releasing its zone, and
// abandons the task. The organization then sanctions it.
fun Z0(): int { return 0; }
fun Z1(): int { return 1; }
fun Z2(): int { return 2; }

machine Robot {
  var id: int;
  var om: machine;
  var guards: map[int, machine];
  var path: seq[int];
  var pos: int;            // index in path; -1 = not yet in the corridor
  var job: tObligation;
  var attempts: int;

  start state Init {
    entry (cfg: (id: int, om: machine, guards: map[int, machine], path: seq[int])) {
      id = cfg.id;
      om = cfg.om;
      guards = cfg.guards;
      path = cfg.path;
      pos = -1;
      goto Idle;
    }
  }

  state Idle {
    on eObligationNotice do (o: tObligation) {
      job = o;
      pos = -1;
      attempts = 0;
      goto Moving;
    }
    ignore eSanction;
  }

  state Moving {
    entry {
      if (pos + 1 == sizeof(path)) {
        // Destination reached: leave the corridor and (maybe) report.
        ReleaseCurrent();
        if ($) { send om, eReportFulfilled, (id = job.id, agent = id); }
        goto Idle;
      } else {
        attempts = attempts + 1;
        send guards[path[pos + 1]], eAccessRequest,
             (agent = id, agentRef = this, resource = path[pos + 1]);
      }
    }
    on eAccessGranted do (g: tGrant) {
      ReleaseCurrent();        // physically moves into the next zone
      pos = pos + 1;
      attempts = 0;
      goto Moving;
    }
    on eAccessDenied do (z: int) {
      if (attempts < 3) {
        goto Moving;
      } else {
        // where = zone the robot was blocked in, or -1 if blocked at the entrance
        if (pos >= 0) {
          announce eTaskAbandoned, (agent = id, where = path[pos]);
        } else {
          announce eTaskAbandoned, (agent = id, where = -1);
        }
        ReleaseCurrent();      // park in a side bay, abandon the task
        goto Idle;
      }
    }
    defer eObligationNotice;
    ignore eSanction;
  }

  fun ReleaseCurrent() {
    if (pos >= 0) {
      send guards[path[pos]], eRelease, (agent = id, agentRef = this, resource = path[pos]);
    }
  }
}

// Distributed architectural style: one controller per zone, coordinated
// only through the adaptation protocol. Grid cell: hybrid
// (environment + organization + agent), distributed.
machine FleetSystem {
  start state Init {
    entry (twoPhase: bool) {
      var capacity: map[int, int];
      var g0: machine;
      var g1: machine;
      var g2: machine;
      var guardMap: map[int, machine];
      var guardSeq: seq[machine];
      var coord: machine;
      var om: machine;
      var r1: machine;
      var r2: machine;
      var p1: seq[int];
      var p2: seq[int];
      var subscribers: seq[machine];

      capacity[Z0()] = 1;
      capacity[Z1()] = 1;
      capacity[Z2()] = 1;
      announce eMonitorConfig, capacity;

      g0 = new ResourceGuard((resource = Z0(), capacity = 1));
      g1 = new ResourceGuard((resource = Z1(), capacity = 1));
      g2 = new ResourceGuard((resource = Z2(), capacity = 1));
      guardMap[Z0()] = g0;
      guardMap[Z1()] = g1;
      guardMap[Z2()] = g2;
      guardSeq += (0, g0);
      guardSeq += (1, g1);
      guardSeq += (2, g2);

      coord = new AdaptationCoordinator((guards = guardSeq, twoPhase = twoPhase));
      om = new ObligationManager();

      p1 += (0, Z0()); p1 += (1, Z1()); p1 += (2, Z2());
      p2 += (0, Z2()); p2 += (1, Z1()); p2 += (2, Z0());
      r1 = new Robot((id = 1, om = om, guards = guardMap, path = p1));
      r2 = new Robot((id = 2, om = om, guards = guardMap, path = p2));

      send om, eAssignTask, (agent = 1, agentRef = r1, task = 10, due = 5);
      send om, eAssignTask, (agent = 2, agentRef = r2, task = 20, due = 5);

      subscribers += (0, om);
      new Clock((subscribers = subscribers, maxTicks = 12));

      new HumanRequester((coord = coord, resource = Z1()));
    }
  }
}
