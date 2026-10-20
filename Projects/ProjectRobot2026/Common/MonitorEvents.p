// =====================================================================
// Monitor vocabulary: the ONLY types and events the monitors observe.
//
// This file is compiled twice:
//   - with the full model, for the P checker   (p check)
//   - alone with the specs, for PObserve        (p compile --mode pobserve)
// so the same monitors judge both the model and the real system's logs.
//
// Field names are kept at <= 5 characters on purpose. The PObserve Java
// backend names tuple classes after abbreviated field names, so short
// names give predictable classes for the log parsers:
//   tNormSet    (ver, closed)          -> PTypes.PTuple_ver_clsd
//   tObligation (id, agent, task, due) -> PTypes.PTuple_id_agent_task_due
//   tOutcome    (id, agent)            -> PTypes.PTuple_id_agent
//   tEnter      (agent, res, ver)      -> PTypes.PTuple_agent_res_ver
//   tLeave      (agent, res)           -> PTypes.PTuple_agent_res
// In Java, P int -> long, set[int] -> LinkedHashSet<Long>,
// map[int,int] -> HashMap<Long, Long>.
// =====================================================================

type tNormSet    = (ver: int, closed: set[int]);
type tObligation = (id: int, agent: int, task: int, due: int);
type tOutcome    = (id: int, agent: int);
type tEnter      = (agent: int, res: int, ver: int);
type tLeave      = (agent: int, res: int);

event eTick: int;                          // logical time (now)
event eMonitorConfig: map[int, int];       // resource -> capacity
event eObligationCreated: tObligation;
event eObligationFulfilled: tOutcome;
event eSanctionApplied: tOutcome;
event eResourceEntered: tEnter;
event eResourceLeft: tLeave;
event eAdaptationStarted: int;             // pending norm-set version
event eNormCommitted: tNormSet;
event eHumanEntered: int;                  // resource id
event eHumanLeft: int;
