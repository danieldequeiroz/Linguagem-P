package regulation.cell;

import org.junit.jupiter.api.Test;
import pobserve.junit.PObserveJUnitSpecConfig;
import pobserve.junit.PObserveLogFileBaseTest;
import pobserve.runtime.exceptions.PAssertionFailureException;
import regulation.cell.parser.CellRegulationParser;
import regulation.cell.spec.PMachines;

import java.io.InputStream;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Runs the regulation SAFETY monitors over logs of the cell example.
 *   cell_twophase.log : prepare -> drain -> commit      => no violation expected
 *   cell_naive.log    : commit first, install later     => violation expected
 * Regenerate the logs with tools/simulate_logs.py, or point the tests at real logs.
 */
@PObserveJUnitSpecConfig(
        parser = CellRegulationParser.class,
        monitors = {
                PMachines.RegimentationSafety.Supplier.class,
                PMachines.NoStaleAdmission.Supplier.class,
                PMachines.NoDoubleOutcome.Supplier.class,
                PMachines.ObligationDeadlineRespected.Supplier.class,
                PMachines.AdaptationBoundedTime.Supplier.class,
                PMachines.LockoutBeforeEntry.Supplier.class
        }
)
public class CellSafetyTest extends PObserveLogFileBaseTest {

    @Test
    public void twoPhaseAdaptationIsSafe() {
        assertDoesNotThrow(() -> runPObserveOnLogFile(log("cell_twophase.log")));
    }

    @Test
    public void naiveAdaptationViolatesRegulation() {
        Exception e = assertThrows(PAssertionFailureException.class,
                () -> runPObserveOnLogFile(log("cell_naive.log")));
        // first failure in log order: a human and an agent in resource 0 at once
        assertTrue(e.getMessage().contains("resource 0"), e.getMessage());
    }

    private InputStream log(String name) {
        return CellSafetyTest.class.getClassLoader().getResourceAsStream(name);
    }
}
