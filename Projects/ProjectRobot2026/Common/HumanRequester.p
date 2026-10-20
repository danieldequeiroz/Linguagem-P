// A human (maintenance technician / warehouse picker) who needs a resource.
// The human is the source of the DETECT fact, and enters only once the
// regulation reports the resource closed to agents. The human trusts the
// committed norm set; whether that trust is justified is what we check.
machine HumanRequester {
  var coord: machine;
  var resource: int;

  start state Init {
    entry (cfg: (coord: machine, resource: int)) {
      coord = cfg.coord;
      resource = cfg.resource;
      send this, eContinue;
      goto Outside;
    }
  }

  state Outside {
    on eContinue do {
      send coord, eAdaptationTriggered, (resource = resource, close = true, requester = this);
      goto WaitingForLock;
    }
  }

  state WaitingForLock {
    on eAdaptationDone do (n: tNormSet) {
      announce eHumanEntered, resource;
      send this, eContinue;
      goto Inside;
    }
  }

  state Inside {
    on eContinue do {
      announce eHumanLeft, resource;
      send coord, eAdaptationTriggered, (resource = resource, close = false, requester = this);
      goto WaitingForUnlock;
    }
  }

  state WaitingForUnlock {
    on eAdaptationDone do (n: tNormSet) { goto Done; }
  }

  state Done { }
}
