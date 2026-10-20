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
 * Runs the sanction-fairness monitor (FleetSpecs.p) over the fleet logs.
 * Even the SAFE two-phase log is expected to violate it: robots blocked by a
 * zone closure or a head-on conflict are later sanctioned for missing their
 * delivery deadline. This is the design gap the monitor exists to expose.
 */
@PObserveJUnitSpecConfig(
        parser = FleetRegulationParser.class,
        monitors = {
                PMachines.SanctionsReflectMisconduct.Supplier.class
        }
)
public class FleetFairnessTest extends PObserveLogFileBaseTest {

    @Test
    public void blockedRobotsAreSanctionedEvenUnderSafeAdaptation() {
        Exception e = assertThrows(PAssertionFailureException.class,
                () -> runPObserveOnLogFile(log("fleet_twophase.log")));
        assertTrue(e.getMessage().contains("blocked by regulation or traffic"), e.getMessage());
    }

    private InputStream log(String name) {
        return FleetFairnessTest.class.getClassLoader().getResourceAsStream(name);
    }
}
