// Fleet-specific monitor vocabulary and property.
// Compiled both with the model (checker) and alone for PObserve.
//   tAbandon (id, agent, where) -> PTypes.PTuple_id_agent_where
//   (class name assumed from the naming rule in MonitorEvents.p; confirm it
//    in the generated PTypes.java after the first `p compile --mode pobserve`)

// A robot announces that it gave up the task of obligation `id` after
// repeated access denials, and parked.
// where = zone it was in when it gave up, or -1 if it was still at the corridor entrance.
type tAbandon = (id: int, agent: int, where: int);
event eTaskAbandoned: tAbandon;

// F1 SanctionsReflectMisconduct: no obligation is sanctioned after the robot
//    abandoned that same obligation's task because zone controllers kept
//    denying it access.
//
//    What this monitor does and does not establish:
//      - It correlates by obligation id: a sanction is flagged only if it is
//        for the task the robot abandoned. Sanctions on the robot's later
//        obligations are judged on their own.
//      - It does NOT establish why access was denied. A denial can come from
//        a zone closed for a human (regulation) or from a zone occupied by
//        the other robot (traffic); eTaskAbandoned does not distinguish them.
//      - It does NOT establish that the denials alone caused the missed
//        deadline. Giving up after 3 denials is the robot's own policy.
//    So a violation means "an obligation was sanctioned after access was
//    repeatedly denied", which is a candidate unfair sanction, not a proven one.
//
//    It fails in the checker as intended (first schedule, independent evaluation
//    of 21 October 2026). Remedies to evaluate:
//      - a regimented traffic norm ("one direction per corridor")
//      - an adaptation rule that suspends or extends the obligation's deadline
//        when the regulation itself blocks the agent
spec SanctionsReflectMisconduct observes eTaskAbandoned, eSanctionApplied {
  var abandoned: set[int];     // obligation ids whose task was abandoned after denials

  start state Watching {
    on eTaskAbandoned do (a: tAbandon) { abandoned += (a.id); }
    on eSanctionApplied do (o: tOutcome) {
      assert !(o.id in abandoned),
        format("obligation {0} of robot {1} sanctioned after the robot abandoned it following repeated access denials",
               o.id, o.agent);
    }
  }
}
