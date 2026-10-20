"""
Emit regulation events in the log format read by the PObserve parsers,
from a ROS 2 (rclpy) system. Works with any Python process too.

Where to call it in a robot fleet:
  zone controller node   (admits/denies robots to a zone)  -> enter / leave
  fleet manager node     (task allocation, deadlines)       -> obligation / fulfilled / sanction / tick
  regulation coordinator (closes/opens zones)               -> adapt_start / commit
  safety PLC / badge     (human presence in a zone)         -> human_enter / human_leave
  robot node             (gives up after repeated denials)  -> abandon
  once at start-up                                          -> config({0: 1, 1: 1, 2: 1})

Example inside a node:
    from regulation_log import RegulationLog
    self.reg = RegulationLog("fleet-A", sink=self.get_logger().info)
    self.reg.enter(agent=robot_id, res=zone_id, ver=self.norm_version)

Note: rclpy prefixes its own "[INFO] [time] [node]:" header. Either write to a
dedicated file (default sink) or adapt the parser's time/prefix handling.
"""
import datetime as _dt
import threading


class RegulationLog:
    def __init__(self, site, sink=None, path=None):
        self.site = site
        self._lock = threading.Lock()
        self._fh = open(path, "a", buffering=1) if path else None
        self._sink = sink

    def _emit(self, event, **fields):
        ts = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f")
        body = ", ".join([f"Site={self.site}", f"Event={event}"] + [f"{k}={v}" for k, v in fields.items()])
        line = f"{ts} [{self.site}] INFO Regulation - : {body}"
        with self._lock:
            if self._fh:
                self._fh.write(line + "\n")
            elif self._sink:
                self._sink(line)
            else:
                print(line, flush=True)

    def config(self, capacity):
        self._emit("CONFIG", Capacity=";".join(f"{r}:{c}" for r, c in capacity.items()))

    def tick(self, now): self._emit("TICK", Now=now)
    def obligation(self, id, agent, task, due): self._emit("OBLIGATION", Id=id, Agent=agent, Task=task, Due=due)
    def fulfilled(self, id, agent): self._emit("FULFILLED", Id=id, Agent=agent)
    def sanction(self, id, agent): self._emit("SANCTION", Id=id, Agent=agent)
    def enter(self, agent, res, ver): self._emit("ENTER", Agent=agent, Res=res, Ver=ver)
    def leave(self, agent, res): self._emit("LEAVE", Agent=agent, Res=res)
    def adapt_start(self, ver): self._emit("ADAPT_START", Ver=ver)

    def commit(self, ver, closed):
        self._emit("COMMIT", Ver=ver, Closed=";".join(str(x) for x in sorted(closed)) or "-")

    def human_enter(self, res): self._emit("HUMAN_ENTER", Res=res)
    def human_leave(self, res): self._emit("HUMAN_LEAVE", Res=res)
    def abandon(self, id, agent, where): self._emit("ABANDON", Id=id, Agent=agent, Where=where)
