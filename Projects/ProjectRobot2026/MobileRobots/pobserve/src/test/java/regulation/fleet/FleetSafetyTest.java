package regulation.fleet;

import org.junit.jupiter.api.Test;
import pobserve.junit.PObserveJUnitSpecConfig;
import pobserve.junit.PObserveLogFileBaseTest;
import pobserve.runtime.exceptions.PAssertionFailureException;
import regulation.fleet.parser.FleetRegulationParser;
import regulation.fleet.spec.PMachines;

import java.io.InputStream;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Runs the regulation SAFETY monitors over logs of the fleet example.
 *   fleet_twophase.log : prepare -> drain -> commit      => no violation expected
 *   fleet_naive.log    : commit first, install later     => violation expected
 * Regenerate the logs with tools/simulate_logs.py, or point the tests at real logs.
 */
@PObserveJUnitSpecConfig(
        parser = FleetRegulationParser.class,
        monitors = {
                PMachines.RegimentationSafety.Supplier.class,
                PMachines.NoStaleAdmission.Supplier.class,
                PMachines.NoDoubleOutcome.Supplier.class,
                PMachines.ObligationDeadlineRespected.Supplier.class,
                PMachines.AdaptationBoundedTime.Supplier.class,
                PMachines.LockoutBeforeEntry.Supplier.class
        }
)
public class FleetSafetyTest extends PObserveLogFileBaseTest {

    @Test
    public void twoPhaseAdaptationIsSafe() {
        assertDoesNotThrow(() -> runPObserveOnLogFile(log("fleet_twophase.log")));
    }

    @Test
    public void naiveAdaptationViolatesRegulation() {
        Exception e = assertThrows(PAssertionFailureException.class,
                () -> runPObserveOnLogFile(log("fleet_naive.log")));
        // first failure in log order: a human and an agent in resource 1 at once
        assertTrue(e.getMessage().contains("resource 1"), e.getMessage());
    }

    private InputStream log(String name) {
        return FleetSafetyTest.class.getClassLoader().getResourceAsStream(name);
    }
}
