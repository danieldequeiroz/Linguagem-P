machine TestFleetTwoPhase {
  start state Init { entry { new FleetSystem(true); } }
}

machine TestFleetNaive {
  start state Init { entry { new FleetSystem(false); } }
}

// Expected (hypothesis): all monitors hold.
test tcFleetTwoPhase [main=TestFleetTwoPhase]:
  assert RegimentationSafety, NoStaleAdmission, NoDoubleOutcome,
         EveryObligationResolved, AdaptationCompletes, AdaptationTerminates,
         LockoutBeforeEntry in
  { TestFleetTwoPhase, FleetSystem, Robot, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };

// Expected (hypothesis): counterexample. Zone 1's controller admits a robot
// after the closure was committed, or the picker enters while a robot is
// still in zone 1.
test tcFleetNaive [main=TestFleetNaive]:
  assert RegimentationSafety, NoStaleAdmission, NoDoubleOutcome,
         EveryObligationResolved, AdaptationCompletes, AdaptationTerminates,
         LockoutBeforeEntry in
  { TestFleetNaive, FleetSystem, Robot, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };

// Expected (hypothesis): counterexample. A robot is sanctioned because of a
// corridor conflict or a zone closure, not misconduct.
test tcFleetSanctionFairness [main=TestFleetTwoPhase]:
  assert SanctionsReflectMisconduct in
  { TestFleetTwoPhase, FleetSystem, Robot, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };
