package regulation.instrumentation;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Collection;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * Emits regulation events in the log format read by the PObserve parsers.
 * Drop it into a JaCaMo project and call it from the places listed below.
 *
 *   ResourceGuard role  (CArtAgO artifact operation that admits/releases agents)
 *       RegulationLog.enter(site, agentId, resourceId, normSetVersion);
 *       RegulationLog.leave(site, agentId, resourceId);
 *   Organization role   (NPL/Moise obligation lifecycle, e.g. a norm-event listener)
 *       RegulationLog.obligation(site, id, agentId, taskId, due);
 *       RegulationLog.fulfilled(site, id, agentId);   RegulationLog.sanction(site, id, agentId);
 *       RegulationLog.tick(site, now);                 // the organization's clock
 *   Adaptation role     (detect / design / execute, e.g. the SAI/NPL(s) adaptation engine)
 *       RegulationLog.adaptStart(site, newVersion);
 *       RegulationLog.commit(site, version, closedResourceIds);
 *   Safety equipment    (light curtain, door switch, badge reader)
 *       RegulationLog.humanEnter(site, resourceId);    RegulationLog.humanLeave(site, resourceId);
 *   At start-up, once:
 *       RegulationLog.config(site, Map.of(0L, 1L));    // resource -> capacity
 *
 * Integer ids are required: monitors compare agents and resources by number.
 * Map JaCaMo agent names to stable numbers (e.g. a registry artifact).
 */
public final class RegulationLog {
    private static final DateTimeFormatter TS = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss.SSSSSS");

    private RegulationLog() { }

    public static void config(String site, Map<Long, Long> capacity) {
        emit(site, "CONFIG", "Capacity=" + capacity.entrySet().stream()
                .map(e -> e.getKey() + ":" + e.getValue()).collect(Collectors.joining(";")));
    }
    public static void tick(String site, long now) { emit(site, "TICK", "Now=" + now); }
    public static void obligation(String site, long id, long agent, long task, long due) {
        emit(site, "OBLIGATION", "Id=" + id, "Agent=" + agent, "Task=" + task, "Due=" + due);
    }
    public static void fulfilled(String site, long id, long agent) { emit(site, "FULFILLED", "Id=" + id, "Agent=" + agent); }
    public static void sanction(String site, long id, long agent) { emit(site, "SANCTION", "Id=" + id, "Agent=" + agent); }
    public static void enter(String site, long agent, long res, long ver) {
        emit(site, "ENTER", "Agent=" + agent, "Res=" + res, "Ver=" + ver);
    }
    public static void leave(String site, long agent, long res) { emit(site, "LEAVE", "Agent=" + agent, "Res=" + res); }
    public static void adaptStart(String site, long ver) { emit(site, "ADAPT_START", "Ver=" + ver); }
    public static void commit(String site, long ver, Collection<Long> closed) {
        String c = closed.isEmpty() ? "-" : closed.stream().sorted().map(String::valueOf).collect(Collectors.joining(";"));
        emit(site, "COMMIT", "Ver=" + ver, "Closed=" + c);
    }
    public static void humanEnter(String site, long res) { emit(site, "HUMAN_ENTER", "Res=" + res); }
    public static void humanLeave(String site, long res) { emit(site, "HUMAN_LEAVE", "Res=" + res); }
    public static void abandon(String site, long id, long agent, long where) { emit(site, "ABANDON", "Id=" + id, "Agent=" + agent, "Where=" + where); }

    /** One line per event. Replace System.out with your logger (keep the " - : " separator). */
    private static void emit(String site, String event, String... fields) {
        StringBuilder b = new StringBuilder()
                .append(LocalDateTime.now(ZoneOffset.UTC).format(TS))
                .append(" [").append(site).append("] INFO Regulation - : ")
                .append("Site=").append(site).append(", Event=").append(event);
        for (String f : fields) {
            b.append(", ").append(f);
        }
        synchronized (RegulationLog.class) {
            System.out.println(b);
        }
    }
}
