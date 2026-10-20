// Discrete logical clock. P is untimed, so deadlines are expressed in ticks.
// After maxTicks it emits one FAR_FUTURE tick, which closes every open
// obligation. That keeps liveness checks meaningful in bounded runs.
machine Clock {
  var subscribers: seq[machine];
  var now: int;
  var maxTicks: int;

  start state Init {
    entry (cfg: (subscribers: seq[machine], maxTicks: int)) {
      subscribers = cfg.subscribers;
      maxTicks = cfg.maxTicks;
      now = 0;
      goto Ticking;
    }
  }

  state Ticking {
    entry {
      if (now < maxTicks) {
        now = now + 1;
        Broadcast(now);
        send this, eContinue;
      } else {
        Broadcast(FAR_FUTURE());
        goto Stopped;
      }
    }
    on eContinue goto Ticking;
  }

  state Stopped {
    ignore eContinue;
  }

  fun Broadcast(t: int) {
    var i: int;
    i = 0;
    while (i < sizeof(subscribers)) {
      send subscribers[i], eTick, t;
      i = i + 1;
    }
  }
}
