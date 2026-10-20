// =====================================================================
// Internal protocol of the model (checker only; not needed by PObserve).
// After Yan et al., COINE 2025:
//
//  Regulation capabilities          -> P construct
//  ---------------------------------------------------------------
//  representation (norm set)        -> tNormSet (versioned)
//  regimentation (enforcement)      -> ResourceGuard admission check
//  monitoring                       -> spec machines (Specs.p)
//  sanctioning (enforcement)        -> ObligationManager + eSanction
//  adaptation (detect/design/exec)  -> HumanRequester / AdaptationCoordinator
//
//  MAOP dimension                   -> P machine
//  ---------------------------------------------------------------
//  organization                     -> ObligationManager, AdaptationCoordinator
//  environment (artifacts)          -> ResourceGuard (PLC / zone controller)
//  agent                            -> CellAgent, Robot (may not comply)
//  interaction                      -> the event protocol below
// =====================================================================

type tTaskReq = (agent: int, agentRef: machine, task: int, due: int);

// Access protocol between agents and environment artifacts.
type tAccess = (agent: int, agentRef: machine, resource: int);
type tGrant  = (resource: int, version: int);

// Adaptation protocol (detect -> design -> execute).
type tTrigger = (resource: int, close: bool, requester: machine);
type tPrepare = (normSet: tNormSet, coord: machine);
type tAck     = (version: int, guard: machine);

event eContinue;                           // self-scheduling helper

// organization: obligations
event eAssignTask: tTaskReq;
event eObligationNotice: tObligation;
event eReportFulfilled: tOutcome;
event eSanction: tOutcome;

// environment: regimentation
event eAccessRequest: tAccess;
event eAccessGranted: tGrant;
event eAccessDenied: int;
event eRelease: tAccess;

// adaptation
event eAdaptationTriggered: tTrigger;      // DETECT fact
event eAdaptationDone: tNormSet;
event eNormPrepare: tPrepare;              // EXECUTE, phase 1
event eNormPrepareAck: tAck;
event eNormCommit: tNormSet;               // EXECUTE, phase 2

// "Time eventually passes every deadline" (closing fairness assumption).
fun FAR_FUTURE(): int { return 1000000; }
