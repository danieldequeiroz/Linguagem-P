// Fleet-specific monitor vocabulary and property.
// Compiled both with the model (checker) and alone for PObserve.
//   tAbandon (agent, where) -> PTypes.PTuple_agent_where

// A robot announces when the environment, not its own choice, stops it.
// where = zone it was blocked in, or -1 if blocked at the corridor entrance.
type tAbandon = (agent: int, where: int);
event eTaskAbandoned: tAbandon;

// F1 SanctionsReflectMisconduct: an agent is sanctioned only for its own
//    non-compliance (finished but did not report), never because regulation
//    or traffic blocked it.
//
//    We EXPECT this to fail in the checker, and the counterexample is the
//    point. It shows a robot sanctioned after (a) a head-on conflict in the
//    corridor or (b) being denied a zone closed for a human. Both are
//    organizational design gaps. Remedies to evaluate next:
//      - a regimented traffic norm ("one direction per corridor")
//      - an adaptation rule that suspends or extends the obligation's deadline
//        when the regulation itself blocks the agent
//    At runtime (PObserve) this monitor flags every such case in the logs.
spec SanctionsReflectMisconduct observes eTaskAbandoned, eSanctionApplied {
  var blocked: set[int];

  start state Watching {
    on eTaskAbandoned do (a: tAbandon) { blocked += (a.agent); }
    on eSanctionApplied do (o: tOutcome) {
      assert !(o.agent in blocked),
        format("robot {0} sanctioned although it was blocked by regulation or traffic, not by its own choice", o.agent);
    }
  }
}
