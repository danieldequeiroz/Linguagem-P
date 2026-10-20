/*******************************************************************
  Lesson 3 — specifications (spec) and a bug worth finding.

  Two clients compete for a lock. The server below grants the lock
  to ANYONE who asks — the MutualExclusion spec catches it.

  Run:  p compile
        p check -tc tcMutualExclusion -i 100
*******************************************************************/

event eAcquire : machine;
event eRelease : machine;
event eGranted : machine;

machine LockClient {
  var server : machine;

  start state Init {
    entry (s : machine) {
      server = s;
      send server, eAcquire, this;
      goto WaitingForLock;
    }
  }

  state WaitingForLock {
    on eGranted goto InCriticalSection;
  }

  state InCriticalSection {
    entry {
      send server, eRelease, this;
      goto Done;
    }
  }

  state Done { }
}

machine LockServer {
  start state WaitForRequests {
    on eAcquire do (client : machine) {
      send client, eGranted, client;      // BUG: grants without checking
    }
    on eRelease do (client : machine) { }
  }
}

spec MutualExclusion observes eGranted, eRelease {
  var holder : machine;
  var locked : bool;

  start state Init {
    on eGranted do (client : machine) {
      assert !locked,
        format("lock granted to {0} while {1} still holds it", client, holder);
      locked = true;
      holder = client;
    }
    on eRelease do (client : machine) {
      locked = false;
    }
  }
}

machine LockDriver {
  start state Init {
    entry {
      var server : machine;
      server = new LockServer();
      new LockClient(server);
      new LockClient(server);
    }
  }
}

test tcMutualExclusion [main = LockDriver]:
  assert MutualExclusion in { LockDriver, LockClient, LockServer };
