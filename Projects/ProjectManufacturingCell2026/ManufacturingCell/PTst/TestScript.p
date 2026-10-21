machine TestCellTwoPhase {
  start state Init { entry { new ManufacturingSystem(true); } }
}

machine TestCellNaive {
  start state Init { entry { new ManufacturingSystem(false); } }
}

// Expected (hypothesis): all monitors hold.
test tcCellTwoPhase [main=TestCellTwoPhase]:
  assert RegimentationSafety, NoStaleAdmission, NoDoubleOutcome,
         EveryObligationResolved, AdaptationCompletes, AdaptationTerminates,
         LockoutBeforeEntry in
  { TestCellTwoPhase, ManufacturingSystem, CellAgent, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };

// Expected (hypothesis): a counterexample for NoStaleAdmission and/or
// RegimentationSafety. The technician enters while the arm is still in the
// envelope, or is admitted on the old norm set.
test tcCellNaive [main=TestCellNaive]:
  assert RegimentationSafety, NoStaleAdmission, NoDoubleOutcome,
         EveryObligationResolved, AdaptationCompletes, AdaptationTerminates,
         LockoutBeforeEntry in
  { TestCellNaive, ManufacturingSystem, CellAgent, ResourceGuard,
    AdaptationCoordinator, ObligationManager, Clock, HumanRequester };
