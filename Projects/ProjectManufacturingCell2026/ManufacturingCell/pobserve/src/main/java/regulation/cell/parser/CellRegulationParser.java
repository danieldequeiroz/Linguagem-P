package regulation.cell.parser;

import pobserve.commons.PObserveEvent;
import pobserve.commons.Parser;
import pobserve.runtime.events.PEvent;
import regulation.cell.spec.PEvents;
import regulation.cell.spec.PTypes;

import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.stream.Stream;

/**
 * Turns structured regulation log lines into P monitor events for PObserve.
 *
 * Expected line (one event per line, fields separated by ", "):
 *   2026-10-19 08:00:03.004000 [cell-A] INFO Regulation - : Site=cell-A, Event=HUMAN_ENTER, Res=0
 *
 * Partition key = Site. All events of one cell go to the same monitor
 * instances, so cross-resource properties (stale admission, lock-out) hold
 * per site; several sites can share one log file.
 *
 * Lines that are not regulation events are skipped (Stream.empty()).
 * No static mutable state: PObserve runs parsers on several threads.
 */
public class CellRegulationParser implements Parser<PEvent<?>> {

    private static final String SEPARATOR = " - : ";
    // java.time keeps the microseconds. (SimpleDateFormat would read ".002000"
    // as 2000 ms and silently reorder events.) DateTimeFormatter is immutable,
    // so sharing it across PObserve's threads is safe.
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSSSSS");

    @Override
    public Stream<PObserveEvent<PEvent<?>>> apply(Object obj) {
        String line = (String) obj;
        String[] parts = line.split(SEPARATOR, 2);
        if (parts.length != 2) {
            return Stream.empty();
        }
        Instant time = parseTime(parts[0]);
        Map<String, String> f = parseFields(parts[1]);
        if (time == null || f == null || !f.containsKey("Event")) {
            return Stream.empty();
        }
        PEvent<?> event = toEvent(f);
        if (event == null) {
            return Stream.empty();
        }
        String key = f.getOrDefault("Site", "default");
        return Stream.of(new PObserveEvent<>(key, time, event, line));
    }

    /** Maps one log record to the P event declared in MonitorEvents.p. */
    private PEvent<?> toEvent(Map<String, String> f) {
        switch (f.get("Event")) {
            case "CONFIG":
                return new PEvents.eMonitorConfig(parseCapacity(f.get("Capacity")));
            case "TICK":
                return new PEvents.eTick(num(f, "Now"));
            case "OBLIGATION":
                return new PEvents.eObligationCreated(new PTypes.PTuple_id_agent_task_due(
                        num(f, "Id"), num(f, "Agent"), num(f, "Task"), num(f, "Due")));
            case "FULFILLED":
                return new PEvents.eObligationFulfilled(new PTypes.PTuple_id_agent(num(f, "Id"), num(f, "Agent")));
            case "SANCTION":
                return new PEvents.eSanctionApplied(new PTypes.PTuple_id_agent(num(f, "Id"), num(f, "Agent")));
            case "ENTER":
                return new PEvents.eResourceEntered(new PTypes.PTuple_agent_res_ver(
                        num(f, "Agent"), num(f, "Res"), num(f, "Ver")));
            case "LEAVE":
                return new PEvents.eResourceLeft(new PTypes.PTuple_agent_res(num(f, "Agent"), num(f, "Res")));
            case "ADAPT_START":
                return new PEvents.eAdaptationStarted(num(f, "Ver"));
            case "COMMIT":
                return new PEvents.eNormCommitted(new PTypes.PTuple_ver_clsd(num(f, "Ver"), parseSet(f.get("Closed"))));
            case "HUMAN_ENTER":
                return new PEvents.eHumanEntered(num(f, "Res"));
            case "HUMAN_LEAVE":
                return new PEvents.eHumanLeft(num(f, "Res"));
            default:
                return null;   // unknown or irrelevant record
        }
    }

    // ---------------- helpers ----------------

    /** Timestamps are UTC with microseconds; they must increase per site. */
    private Instant parseTime(String prefix) {
        String[] tokens = prefix.trim().split(" ");
        if (tokens.length < 2) {
            return null;
        }
        try {
            return LocalDateTime.parse(tokens[0] + " " + tokens[1], TS).toInstant(ZoneOffset.UTC);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    private Map<String, String> parseFields(String body) {
        Map<String, String> f = new HashMap<>();
        for (String part : body.trim().split(", ")) {
            String[] kv = part.split("=", 2);
            if (kv.length != 2) {
                return null;
            }
            f.put(kv[0].trim(), kv[1].trim());
        }
        return f;
    }

    private long num(Map<String, String> f, String field) {
        String v = f.get(field);
        if (v == null) {
            throw new IllegalArgumentException("missing field " + field);
        }
        return Long.parseLong(v);
    }

    /** "0;2" -> {0, 2};  "-" or "" -> {} */
    private LinkedHashSet<Long> parseSet(String v) {
        LinkedHashSet<Long> s = new LinkedHashSet<>();
        if (v == null || v.isEmpty() || v.equals("-")) {
            return s;
        }
        for (String x : v.split(";")) {
            s.add(Long.parseLong(x.trim()));
        }
        return s;
    }

    /** "0:1;1:1" -> {0=1, 1=1} */
    private HashMap<Long, Long> parseCapacity(String v) {
        HashMap<Long, Long> m = new HashMap<>();
        if (v == null || v.isEmpty()) {
            return m;
        }
        for (String pair : v.split(";")) {
            String[] rc = pair.split(":");
            m.put(Long.parseLong(rc[0].trim()), Long.parseLong(rc[1].trim()));
        }
        return m;
    }
}
