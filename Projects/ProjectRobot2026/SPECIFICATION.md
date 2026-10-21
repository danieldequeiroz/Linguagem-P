# Verified Regulation Management for a Mobile Robot Fleet (P + PObserve)

Graduate project specification · Oct 20, 2026 · Angelo

## Repository and access

All project material is available in the GitHub repository [perkusic/P-Language](https://github.com/perkusic/P-Language):

- **Project folder:** [`Projects/ProjectRobot2026`](https://github.com/perkusic/P-Language/tree/main/Projects/ProjectRobot2026). It contains the starter kit, the instructions and this specification.
- **P tutorial:** [`P-Tutorial`](https://github.com/perkusic/P-Language/tree/main/P-Tutorial). It covers installation, a first P program, specifications and the model checker, and is intended for days 1–7.

**The repository is public; no account or authorization is required.** It can be browsed on GitHub, cloned (`git clone https://github.com/perkusic/P-Language.git`) or downloaded as a ZIP archive (**Code** button → **Download ZIP**). A GitHub account is required only to fork the repository or to propose changes.

**Working without a GitHub account.** No GitHub account is needed at any stage of the project; an account is useful only for forking the repository or proposing changes to it.

1. **Reading.** The repository and this specification can be browsed on GitHub without signing in. After downloading, `Projects/ProjectRobot2026/SPECIFICATION.html` opens in any web browser, without network access.
2. **Obtaining the files.** Either download the archive from the repository page (**Code** → **Download ZIP**) and extract it, or, with Git installed, run `git clone https://github.com/perkusic/P-Language.git`; cloning a public repository requires no account.
3. **Updating.** A clone is updated with `git pull`. A ZIP archive is not updated: download it again and copy the team's own files into the new copy, or switch to a clone.
4. **Version control.** The checkpoints of [Section 8](#8-work-plan-and-deliverables) require tagged commits, which work in a local repository: in an extracted ZIP archive, run `git init`, then `git add -A` and `git commit` at each step, and `git tag d1` (and so on) at each checkpoint.
5. **Sharing within a team.** Without a hosting service, a team can exchange its repository with `git bundle create team.bundle --all`, a single file from which the other members clone or pull, or keep the repository in a shared folder.
6. **Submitting.** Unless the instructor specifies another channel, a deliverable is submitted as a ZIP archive of the team's working copy that includes the `.git` folder, so that the tagged checkpoint commits can be verified.

None of the tools used in the project (P, the .NET SDK, Java, Gradle and PObserve) requires a GitHub account.

## 1. Introduction

The objective in this project is to build and verify the regulation layer of a small fleet of mobile robots that share a narrow corridor with people. The work proceeds in two steps:

1. The regulation layer is modeled in the P language and model-checked.
2. Fleet logs, either simulated or recorded from a ROS 2 system, are checked against the same P monitors with PObserve.

**Why a multi-agent system.** The corridor could in principle be controlled by a single centralized program, but several features of the problem favor a multi-agent design. First, each robot plans its own route, pursues its own deliveries and decides locally how to react to a denial, which corresponds to the notion of an autonomous agent; in practice, robots of a warehouse fleet are often supplied by different vendors and governed by their own software ([Section 2](#2-background-multi-agent-systems), [Section 2.5](#25-multi-robot-coordination)). Second, the system is open: robots may be added, replaced or upgraded, and a picker enters the corridor as a further participant with goals of their own, so the system cannot be designed as a closed program whose components are all known in advance. Third, admission is inherently distributed: each zone has its own controller, which decides on local information, while deliveries, deadlines and closures are commitments that span the whole corridor; organizations and norms are the abstractions that a multi-agent system provides for expressing such coordination ([Section 2.4](#24-organization-moise), [Section 3](#3-background-norms-and-normative-mas)). Fourth, a multi-agent architecture separates concerns: the robots decide what to do, the environment enforces physical constraints through artifacts such as the zone controllers ([Section 2.2](#22-environment-artifacts)), and the fleet manager states obligations and sanctions their violation, so that each part can be modified without rewriting the others. The price of this autonomy is that compliance cannot be assumed, which is the reason why the regulation layer described below is required.

[Figure 1](#figure-1) shows the corridor and the regulation layer that controls access to it; [Figure 3](#figure-3) shows the four stages in which zone 1 is closed safely, and [Figure 4](#figure-4) contrasts this sequence with a naive adaptation, in which the picker and a robot can occupy zone 1 together. Two robots traverse a one-lane corridor of three zones, each admitting at most one robot, in opposite directions, so that their paths meet head-on; a human picker occasionally requires access to zone 1. Each zone is regulated by its own zone controller, which admits or denies robots according to the version of the norm set that it currently holds, while an adaptation coordinator closes zone 1 by distributing a new norm set. Because the controllers receive the new version at different times, there is a transition window in which they disagree on the norms in force; in addition, a robot that is repeatedly denied access abandons its delivery, parks in a side bay, and is subsequently sanctioned by the fleet manager for the missed deadline. Three questions must be answered: whether a person and a robot can ever occupy zone 1 together while the norms change (safety), whether every obligation and every closure is eventually resolved (liveness), and whether robots are sanctioned for delays caused by the regulation or by traffic rather than by their own conduct (sanction fairness).

<a id="figure-1"></a>

![Figure 1 · the robot fleet and its regulation layer](figures/figure1.svg)

*Figure 1 · the robot fleet and its regulation layer*

**Reading Figure 1.** The left panel shows the physical system: a one-lane corridor of three zones (0, 1 and 2), each with capacity 1 and its own zone controller. Robot R1 travels 0 → 1 → 2 and robot R2 travels 2 → 1 → 0, so their paths meet head-on in zone 1, which the picker also needs to enter. The right panel shows the regulation layer: a single adaptation coordinator, which changes the norm set when the picker requests the closure of zone 1, and a single fleet manager, which assigns deliveries with deadlines and sanctions missed ones. Admission is therefore distributed, whereas adaptation and sanctioning are centralized. Each element corresponds to a machine of the starter kit ([Section 7.1](#71-model-components)): the robots to `Robot`, each zone controller to one `ResourceGuard`, the coordinator to `AdaptationCoordinator`, the fleet manager to `ObligationManager`, and the picker to `HumanRequester`. The note at the bottom states the requirement that the regulation must guarantee: the picker enters zone 1 only after a committed closure and only when the zone is empty. Physical faults, such as a failed light curtain or a robot that ignores its controller, lie outside the model.

The following must be done with respect to Figure 1:

- map each element to its P machine and to the events that the machine announces ([Section 7.1](#71-model-components)), and include the mapping in deliverable D1;
- place the fleet in the unified-view grid ([Figure 15](#figure-15)) and justify which responsibilities are distributed and which are centralized;
- classify each norm as regimented or enforced by sanctions ([Section 3.8](#38-choosing-an-enforcement-mechanism)), and restate the requirement in the note as the safety properties S1 and S2 ([Section 7.2](#72-property-catalog)).

**The regulation layer.** In a normative multi-agent system, the agents are autonomous: each decides its own actions and may, deliberately or through a fault, fail to comply with the rules of the corridor. The *regulation layer* is the part of the system that states these rules and makes them effective without controlling the agents' decisions ([Figure 2](#figure-2)). It comprises four capabilities ([Section 4.1](#41-the-capabilities-in-detail)): it *represents* the norms in force as a versioned norm set; it *monitors* entries, departures, delivery reports and deadlines in order to detect violations; it *enforces* the norms, either by regimentation, when an environment artifact such as a zone controller prevents a prohibited action, or by sanctioning, when the fleet manager reacts after a violation ([Section 3.8](#38-choosing-an-enforcement-mechanism)); and it *adapts* the norm set while the fleet is running, as in the closure of zone 1 before the picker enters ([Section 4](#4-background-regulation-management-in-mas)).

**Why the regulation layer is needed.** Four properties of the corridor make an explicit and verified regulation layer necessary. First, the robots cannot be assumed to comply, so safety cannot rest on the correctness of each robot; it must rest on rules that the system itself enforces. Second, the robots share a physical space with people, so a single erroneous admission can injure the picker. Third, the rules change during operation, and because each zone controller receives the new norm set at a different time, the controllers may temporarily disagree on the rules in force. Fourth, the regulation itself can cause a robot to miss a deadline, by closing a zone or by leaving two robots blocked head-on, so sanctions must be checked for fairness ([Section 3.9](#39-conditions-for-a-fair-sanction)). The regulation layer is therefore the object of design and verification in this project, and its properties must hold for every behavior of the robots that the model admits, under its stated assumptions; in the running fleet, PObserve can check only the executions that are logged.

<a id="figure-2"></a>

![Figure 2 · the regulation layer between the robots and the corridor](figures/figure2.svg)

*Figure 2 · the regulation layer between the robots and the corridor*

**What the P model represents.** The domain agents are the robots R1 and R2. Each has its own deliveries and its own controller. P represents their externally visible behavior with state machines and abstracts some of their choices with nondeterminism (`$`); it implements neither a BDI interpreter nor planning or learning. The other P machines model the environment and the organization and are not agents: a P machine is a modeling construct, not automatically an agent. Jason, Moise, CArtAgO, NPL and ROS 2 appear in this specification as background and as possible deployment platforms; they do not run inside the P model. The tests use a fixed configuration of two agents, so openness motivates the architecture but is not verified by the baseline. A multi-agent system may contain centralized services: *multi-agent*, *distributed*, *open* and *norm-aware* are different properties.

| Domain entity | Goal or decision | P machine | Omitted in the model |
| --- | --- | --- | --- |
| Robots R1, R2 (agents) | deliver along a fixed path; request the next zone; park after three denials | `Robot` | route planning, BDI reasoning, learning |
| Zone controllers 0–2 (environment) | admit or deny entry to one zone | `ResourceGuard`, one per zone | sensors, physical faults |
| Fleet manager (organization) | assign deliveries with deadlines; sanction missed ones | `ObligationManager` | concrete penalties, role negotiation |
| Adaptation coordinator | close or reopen zone 1 by prepare, drain and commit | `AdaptationCoordinator` | role checks on requests |
| Picker (person) | request the closure; enter after the commit | `HumanRequester` | identity and presence sensing |
| Clock (infrastructure) | advance logical time | `Clock` | real time |

**From a norm to a monitor: a worked example.** One norm of the fleet can be followed through every layer of the project:

| Step | Closure example |
| --- | --- |
| Norm | an agent must not enter resource r while the committed norm set closes r |
| Instance | r = zone 1 |
| Representation | `tNormSet.ver` and `tNormSet.closed` |
| Enforcement | `ResourceGuard` refuses the access request (regimentation) |
| Adaptation | `AdaptationCoordinator` runs prepare, drain and commit |
| Observable evidence | the events `eNormCommitted` and `eResourceEntered` |
| Verification | the monitor `NoStaleAdmission` (S2) rejects an entry to a committed-closed resource |
| Limit | robots use the admission interface; physical motion that bypasses it is excluded |

The guard prevents the action; the monitor checks the behavior. A monitor neither admits nor refuses anything, and it does not make the physical system safe by itself. For deadlines, the agent's obligation to report on time is distinct from the organization's resolution of the record: a sanction resolves the record, which satisfies L1, but it does not make the delivery successful or turn a violation into compliance.

**Implemented and conceptual features.** Several mechanisms described in the background sections are not implemented by the starter kit:

- Sanctions are abstract events (`eSanctionApplied`); the agents ignore them, and the model implements no fines, priority reductions or learning from penalties. The effects listed in [Section 3.7](#37-sanctions) are possible implementations.
- The coordinator changes only which resources are closed, and increments the version; it does not revise deadlines, sanctions or other norms.
- The coordinator does not check who requests a closure; role-based authorization ([Section 4.4](#44-adaptation-as-a-control-loop)) is a conceptual extension.
- The inactivation of an obligation ([Figure 9](#figure-9)) is an extension: no event or handler implements it.
- Count-as rules ([Section 3.6](#36-constitutive-rules-situated-artificial-institutions)), such as a badge swipe counting as entry, are modeling choices; a presence event in a log requires evidence that a person is actually inside.
- P specification monitors observe and assert; they enforce nothing in a deployed system. The JaCaMo components of [Figure 5](#figure-5) are a deployment illustration.

<a id="figure-3"></a>

![Figure 3 · closing zone 1 in four stages](figures/figure3.svg)

*Figure 3 · closing zone 1 in four stages*

**Reading Figure 3.** The four panels show the prepare–drain–commit protocol for the closure of zone 1. (1) The picker asks the coordinator to close zone 1; the coordinator derives the next norm set (version v + 1) and announces `eAdaptationStarted`. (2) The coordinator sends `eNormPrepare` to all three zone controllers. The controller of zone 1, which is affected by the change, enters the state `Draining` and denies every new request, although a robot may still be inside; the controllers of zones 0 and 2, which are unaffected, acknowledge at once and continue to admit robots. (3) The robot in zone 1 leaves when the controller of its next zone admits it, or parks in a side bay after three denials; the controller of zone 1 then acknowledges with `eNormPrepareAck` and waits in `AwaitCommit`, where it still denies requests. (4) Once all three controllers have acknowledged, the coordinator announces `eNormCommitted`, sends the new norm set to all three controllers with `eNormCommit`, and notifies the picker with `eAdaptationDone`; only then does the picker enter. The notification may reach the picker before the controller of zone 1 has processed the commit message and installed the norm set; this is safe, because that controller denies every request until it does. The essential invariant is that zone 1 is closed to new admissions from stage 2 onward, so that it is empty when the closure is committed. Stage 3 depends on the robot being able to leave: if its next zone is held by the other robot, which in turn waits for zone 1, draining relies on parking, and without parking the corridor deadlocks (experiments E4 and E5).

The following must be done with respect to Figure 3:

- locate each stage in `AdaptationCoordinator.p` and `ResourceGuard.p`, using the state machines of [Figure 22](#figure-22), and name the event that causes each transition;
- run `p check -tc tcFleetTwoPhase` (experiment E1, [Section 7.3](#73-experiments-priorities-in-75)), confirm that S1–S3, L1–L3 and R3 hold, justify the number of schedules explored ([Section 5.9](#59-what-n-schedules-guarantee)), and verify in a trace that zones 0 and 2 continue to admit robots during the closure;
- run experiments E4 and E5 and explain whether L2 fails and why ([Section 5.10](#510-what-a-hot-state-violation-means)).

<a id="figure-4"></a>

![Figure 4 · naive adaptation versus prepare–drain–commit](figures/figure4.svg)

*Figure 4 · naive adaptation versus prepare–drain–commit*

**Reading Figure 4.** The left column shows the naive policy (`twoPhase = false`): the coordinator declares the closure, announcing `eNormCommitted`, and notifies the picker, possibly before the controller of zone 1 has processed the commit message and installed the new norm set. In the interval between the two, that controller still applies the previous version and may admit a robot to zone 1; the picker, who relies on the committed norm set, may then share the zone with that robot. The right column shows the sequence of [Figure 3](#figure-3), in which admission is stopped and emptiness is established before the commit. The unsafe execution is possible but not necessary: it arises only for particular orders of the messages ([Figure 19](#figure-19)), within the inconsistency window described in [Section 4.6](#46-the-inconsistency-window), which is why it must be found by systematic exploration of interleavings rather than by testing. [Figure 21](#figure-21) shows both executions as message sequences. The note at the bottom concerns a separate question: under either protocol, a robot that is repeatedly denied access may abandon its delivery and be sanctioned; property F1 flags such sanctions as candidates for unfairness, but establishing their cause requires additional evidence ([Section 3.9](#39-conditions-for-a-fair-sanction)).

The following must be done with respect to Figure 4:

- run `p check -tc tcFleetNaive` (experiment E2) until the first violation, identify the failing monitor (S1 or S2), and explain the counterexample with the template of [Section 7.8](#78-reporting-a-counterexample), naming the step at which the coordinator and the controller of zone 1 hold different norm sets;
- compare the counterexample with the result of E1 and state which step of the right column excludes the violating interleaving;
- run `p check -tc tcFleetSanctionFairness` (experiment E3) and attribute each flagged sanction to its cause, a closure or a head-on conflict.

The project instantiates one cell of the conceptual grid proposed by [Yan, Nardin, Boissier & Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) (*A Unified View on Regulation Management in Multi-Agent Systems*, COINE 2025) as a system whose properties can be verified. The grid combines three perspectives: regulation capabilities, programming dimensions and architectural style. The cell considered here is **hybrid (environment + organization + agent), with distributed regimentation and centralized adaptation and sanctioning**: each corridor zone has its own controller, which admits or denies robots on the basis of local information only, whereas a single coordinator changes the norm set and a single fleet manager tracks obligations and applies sanctions ([Section 4.3](#43-architectural-styles)).

**Research questions:**

1. Does a regulation layer with distributed regimentation preserve its safety guarantees while a zone is closed for a person, and which adaptation protocol is required to ensure this?
2. When regulation and physical traffic block robots, which sanctions are applied to obligations that robots abandoned after repeated denials, can each such sanction be attributed to a regulation-caused or a traffic-caused denial (by means of the refined, cause-aware monitor required in phase 3), and which organizational remedy removes the regulation-caused cases without weakening safety?
3. (Stretch goal) Does the distributed design refine a centralized regulator with respect to the observable events (admissions, releases, commits and human entries and exits)? Refinement in the sense of trace inclusion preserves safety properties but not liveness properties, which require a separate argument.

**Expected results:**

- **Safety.** A naive adaptation, in which the closure is declared first and each zone controller installs it upon receipt, is expected to admit a robot into a zone that is already closed and may contain a person. A prepare–drain–commit adaptation is expected to prevent this.
- **Sanction fairness.** In the starter kit, a robot that abandons its delivery after three denials remains obliged, and nothing excuses the abandoned obligation; the final far-future tick of the clock therefore guarantees that the obligation is eventually sanctioned. The fairness monitor F1 is consequently expected to fail by construction of the kit's policy, under both protocols. The substantive results of the project concern the causes of the flagged sanctions (regulation-caused or traffic-caused denials) and the effect of a remedy on each cause.

**Learning outcomes.** On completion of the project, the student is able to:

- **LO1** explain multi-agent systems, normative multi-agent systems and regulation management, and position the fleet in the unified-view grid, distinguishing distributed regimentation from centralized adaptation and sanctioning;
- **LO2** formalize distributed regulation, obligations, sanctions and adaptation as communicating state machines in P, and state the modeling assumptions on which the results depend;
- **LO3** express safety, liveness, bounded-response and sanction-fairness requirements as P monitors, classify them, and interpret the resulting counterexamples;
- **LO4** justify what a given number of explored schedules establishes, and demonstrate with mutants that each monitor can fail;
- **LO5** attribute flagged sanctions to their causes (regulation or traffic), and design, model and verify a remedy;
- **LO6** compile the monitors for PObserve, adapt and extend the provided log parser, check fleet logs, and state what a finite log can and cannot establish;
- **LO7** analyze how physical constraints (for example, that a robot cannot leave a zone instantaneously) interact with norms, and state the threats to the validity of the results.

[Section 8](#8-work-plan-and-deliverables) relates each outcome to the deliverables and to the assessment criteria.

**Property overview.** The properties below are referred to by their identifiers throughout the document. They are defined in [Section 7.2](#72-property-catalog) and traced to norms, events and tests in [Section 7.7](#77-traceability).

| Id | Property (informal) | Class |
| --- | --- | --- |
| S1 | never two robots in a zone; never a robot and a person in the same zone | safety |
| S2 | no admission to a zone that the committed norm set closes; norm sets installed in version order | safety |
| S3 | no delivery both fulfilled and sanctioned | safety (organizational integrity) |
| L1 | every obligation is eventually fulfilled or sanctioned | liveness |
| L2 | every adaptation eventually commits | liveness |
| L3 | every adaptation is eventually committed or explicitly aborted | liveness |
| R1 | every obligation is resolved by tick Due + 1 | bounded response (run time) |
| R2 | every adaptation commits within 5 ticks | bounded response (run time) |
| R3 | a person enters only a zone that the committed norm set closes | safety (procedure) |
| F1 | no obligation is sanctioned after the robot abandoned it following repeated denials | safety (approximation of sanction fairness) |

**How to read this document.** [Sections 2](#2-background-multi-agent-systems) to 5 provide background, and [Section 6](#6-the-system-robots-in-a-shared-corridor) onward specifies the project. [Appendix A](#appendix-a-glossary-and-reading-map) contains a glossary and a reading map that marks each background subsection as essential or as enrichment and indicates the phase in which it is needed. Each background section ends with self-check questions.

## 2. Background: multi-agent systems

A multi-agent system (MAS) is a set of autonomous agents that share an environment and interact to achieve individual or collective goals. Because each agent decides autonomously, the global behavior of the system is not programmed directly; it emerges from the agents' decisions and interactions. This is the fundamental reason why a MAS requires regulation.

**Agents.** Following [Wooldridge](#references), an agent is a software or physical entity with four properties:

- **autonomy**: it acts without direct external intervention;
- **reactivity**: it responds to changes in its environment;
- **pro-activeness**: it pursues its own goals;
- **social ability**: it communicates with other agents.

Most MAS platforms adopt the belief–desire–intention (BDI) model, in which agents reason over *beliefs*, *desires* (goals) and *intentions* (plans to which they have committed). Jason, an interpreter for the AgentSpeak language, is a representative example.

**Multi-Agent Oriented Programming (MAOP).** [Boissier et al.](#references) decompose a MAS into four programming dimensions, each with its own first-class abstractions. JaCaMo integrates one technology per dimension. In a robot fleet, these dimensions correspond to established robotics components ([Figure 5](#figure-5)):

| Dimension | First-class abstractions | JaCaMo technology | Role in this project | Typical robotics counterpart |
| --- | --- | --- | --- | --- |
| Agent | beliefs, goals, plans | Jason | each mobile robot's task logic | robot task node |
| Environment | artifacts with operations and observable properties | CArtAgO | one controller per corridor zone, admitting robots | zone / traffic controller node |
| Interaction | protocols, messages | Jason speech acts | request / grant / deny / release; prepare / ack / commit | ROS 2 topics and services |
| Organization | roles, groups, missions, norms | Moise + NPL | delivery obligations, deadlines, sanctions, zone closures | fleet manager |

<a id="figure-5"></a>

![Figure 5 · MAOP dimensions and JaCaMo technologies, with the fleet's components](figures/figure5.svg)

*Figure 5 · MAOP dimensions and JaCaMo technologies, with the fleet's components*

The physical layer lies outside the MAS. The environment dimension is the interface between the two, which is why regimented safety norms are placed there.

**Open systems.** In an open MAS, the designer does not control the internal code of the agents. Robots may be supplied by different vendors, execute learned policies or be teleoperated. Consequently, correctness cannot rely on agent compliance: the regulation layer must maintain its guarantees under *any* agent behavior. The model of [Section 7](#7-technical-specification) approximates this requirement with nondeterministic agents that may, for example, fail to report. These agents nevertheless follow the interaction protocol: they request access before entering and never enter without a grant. The guarantees are therefore established for any behavior within the protocol, not for arbitrary behavior; [Section 7.6](#76-modeling-assumptions-and-threats-to-validity) lists this and the other modeling assumptions.

**Robot fleets as MAS.** Warehouses, hospitals and factories operate fleets of autonomous mobile robots in spaces shared with people. Traffic is typically managed per zone, because a narrow aisle can accommodate only one robot, and zones are closed while people work in them. Each zone controller decides locally, and messages between controllers incur delays. The fleet therefore poses a *distributed* regulation problem: two controllers may temporarily disagree on which zones are closed.

### 2.1 Agent architectures and the BDI cycle

Agent architectures fall into three families:

- **Reactive** agents map percepts directly to actions. Brooks' subsumption architecture for robots is the classical example. Such agents respond quickly but do not plan.
- **Deliberative** agents maintain a symbolic model of the world and reason about goals before acting.
- **Hybrid** agents combine a reactive layer (e.g., obstacle avoidance) with a deliberative layer above it (e.g., route and task selection).

Most mobile robots follow a hybrid architecture, whereas JaCaMo agents are deliberative at the task level.

A BDI agent repeats a **reasoning cycle** ([Figure 6](#figure-6)):

1. **Perceive.** Read percepts (sensors, artifact properties) and messages, and update the *belief base*.
2. **Deliberate.** Choose which goals to pursue; the chosen ones become *intentions*.
3. **Select a plan.** From the plan library, pick a plan whose trigger matches the goal and whose context condition holds in the current beliefs.
4. **Act.** Execute one step of one intention: an action, a message, or a sub-goal. Then go back to 1.

<a id="figure-6"></a>

![Figure 6 · the BDI reasoning cycle](figures/figure6.svg)

*Figure 6 · the BDI reasoning cycle*

A delivery robot in Jason (AgentSpeak), simplified:

```
// plan: <trigger> : <context> <- <body>.
+!deliver(Path) : not done(Path)
   <- !enter_next_zone(Path);
      !deliver(Path).

+!enter_next_zone(Path) : next_zone(Path, Z)
   <- requestAccess(Z).          // operation on the zone artifact; fails if denied

// failure handling: after 3 denials, park and give up the task
-!enter_next_zone(Path) : denials(N) & N >= 3
   <- park; .drop_intention(deliver(Path)).
-!enter_next_zone(Path)
   <- .wait(500); !enter_next_zone(Path).
```

The agent *chooses* whether to retry, park or report; this choice is the locus of its autonomy. The regulation layer can constrain only the outcomes of the agent's reasoning, not the reasoning itself.

### 2.2 Environment: artifacts

In CArtAgO, the environment is composed of **artifacts**: objects that agents use as tools. An artifact provides:

- **operations**: actions that agents can perform on the artifact;
- **observable properties**: state that agents perceive as beliefs;
- **signals**: transient events.

An operation can refuse to execute. That makes artifacts the natural place for *regimentation*: a prohibited action fails.

```java
// A zone controller as a CArtAgO artifact (sketch)
public class ZoneController extends Artifact {
  private int capacity;

  void init(int zone, int capacity) {
    this.capacity = capacity;
    defineObsProperty("occupancy", 0);
    defineObsProperty("closed", false);       // set by the norm set in force
  }

  @OPERATION void requestAccess() {
    ObsProperty occ = getObsProperty("occupancy");
    if (getObsProperty("closed").booleanValue() || occ.intValue() >= capacity) {
      failed("access denied");                  // regimentation: the action fails
    } else {
      occ.updateValue(occ.intValue() + 1);
    }
  }

  @OPERATION void release() {
    ObsProperty occ = getObsProperty("occupancy");
    occ.updateValue(occ.intValue() - 1);
  }
}
```

In a deployed fleet, the artifact would wrap a ROS 2 zone-controller node or a traffic server. The `ResourceGuard` machine described in [Section 7](#7-technical-specification) is its P model.

### 2.3 Interaction

Agents communicate with an agent communication language (KQML, FIPA ACL). Each message carries a **performative** stating its intent: *inform*, *request*, *propose*, *accept*, *refuse*. In Jason, `.send(r2, tell, at(zone1))` informs and `.send(r2, achieve, wait)` asks for a goal.

Recurring exchanges are standardized as **protocols**. The **Contract Net** protocol is the classical protocol for task allocation: a manager announces a task, robots submit bids (e.g., based on their distance to the pickup point), and the manager awards the task. Approaches based on social commitments (Singh) assign a normative meaning to protocol steps; for instance, *"having accepted the task, the robot is committed to delivering it"*. This connects interaction to the norms discussed in [Section 3](#3-background-norms-and-normative-mas).

### 2.4 Organization: Moise

Moise describes an organization with three linked specifications:

| Specification | Describes | Fleet example |
| --- | --- | --- |
| Structural | roles, groups, links between roles, cardinalities | group `corridor_A` with role `courier` (max 2) and role `fleet_manager` (1) |
| Functional | global goals decomposed into **schemes** and **missions** | scheme `delivery`: goals `pick`, `traverse`, `drop`, `report`; mission `m_deliver` covers them |
| Normative | obligations and permissions linking roles to missions, with deadlines | *a `courier` is obliged to commit to `m_deliver` and achieve it within 5 ticks* |

A simplified normative specification:

```xml
<normative-specification>
  <norm id="n_deliver" type="obligation" role="courier"
        mission="m_deliver" time-constraint="5 minutes"/>
</normative-specification>
```

In this project, time is measured in logical ticks of the organization's clock. Moise and NPL express deadlines in physical time units; the examples in this section and in [Section 3.5](#35-normative-programming-in-jacamo-npl) use minutes only for illustration, and the mapping from ticks to physical time is a deployment decision (`MobileRobots/INSTRUCTIONS.md`, section 3.6).

At run time, the organization is itself represented as an artifact. Agents adopt roles and commit to missions, and the normative engine of the organization (NPL, [Section 3](#3-background-norms-and-normative-mas)) creates and tracks the resulting obligations.

### 2.5 Multi-robot coordination

Robot fleets face three classical coordination problems, each of which gives rise to norms:

- **Task allocation**, i.e., the assignment of deliveries to robots. Gerkey and Matarić (IJRR 2004) classify task-allocation problems by robot type (single- or multi-task), task type (single- or multi-robot) and timing (instantaneous or time-extended).
- **Path planning and traffic management.** Multi-agent path finding computes collision-free routes. Industrial fleets frequently rely on the simpler **zone reservation** scheme, in which a robot may enter a zone only while it holds a reservation for that zone. This scheme is adopted in this project.
- **Deadlock.** Two robots facing each other in a one-lane corridor, each holding its own zone and waiting for the other's, form a cyclic wait. Standard remedies include one-way lanes, priorities, timeouts with back-off (in this project, parking after three denials) and reservation of the entire corridor. [Section 6](#6-the-system-robots-in-a-shared-corridor) analyzes this deadlock in terms of the four necessary conditions identified by Coffman, Elphick and Shoshani.

Each remedy can be expressed as a norm: "one direction at a time" is a prohibition, and "yield to the robot with priority" is an obligation. Whether such norms interact safely with sanctions and zone closures must be examined.

**Self-check questions ([Section 2](#2-background-multi-agent-systems)).**

1. Which responsibilities of the fleet's regulation are distributed and which are centralized, and what does each choice imply for the consistency of the norm set during a change?
2. Why is the environment dimension the natural place for regimentation, and which norm of the fleet cannot be regimented there?
3. In the Jason plan of [Section 2.1](#21-agent-architectures-and-the-bdi-cycle), which decision belongs to the robot's autonomy, and through which event can the regulation layer observe its outcome?

## 3. Background: norms and normative MAS

Norms allow a MAS to regulate the behavior of autonomous agents without prescribing their internal decision-making. They state what *ought* to happen and specify the consequences when it does not. A **normative MAS** is a MAS whose behavior is constrained by explicitly represented norms, about which agents can reason and which the system can monitor and enforce ([Boella, van der Torre and Verhagen](#references)).

**Deontic modalities.** A regulative norm usually takes one of the following forms:

- **Obligation** O(φ): the agent is required to bring about φ, typically before a deadline. *"The robot assigned delivery d must report it before tick 5."*
- **Prohibition** F(φ): the agent is required not to bring about φ. *"No robot may be in a zone while a person is inside."*
- **Permission** P(φ): φ is allowed, often as an exception to a prohibition.

Norms are usually *conditional*: they comprise an activation condition, a deontic content, a deadline or expiration condition, and a sanction. Their lifecycle proceeds from inactive to active, and then either to fulfilled or to violated and subsequently sanctioned.

**Regulative and constitutive norms.** Regulative norms constrain behavior ("must", "must not"). Constitutive norms define what *counts as* what within the institution, e.g., *"a person detected by the zone 1 light curtain counts as a human in zone 1"*. The adaptation model adopted in this project relies on both kinds ([Section 4](#4-background-regulation-management-in-mas)).

**Enforcement mechanisms.** Two mechanisms are distinguished:

| Mechanism | Principle | Guarantee | Cost | In this project |
| --- | --- | --- | --- | --- |
| Regimentation | the violation is made impossible: the environment refuses the action | the norm holds invariantly | removes autonomy; applicable only to actions controlled by the environment | each zone controller refuses entry to a closed or occupied zone |
| Sanctioning | the violation remains operationally possible, although the action stays forbidden, and is detected and followed by a sanction | the norm holds only to the extent that sanctions deter violations | requires monitoring and a fair sanction policy | a missed delivery deadline results in a sanction |

Safety-critical norms (people and robots in the same zone) should be regimented, whereas performance norms (deadlines) are normally sanctioned. [Alechina, Bulling, Dastani and Logan (AAMAS 2015)](https://nottingham-repository.worktribe.com/output/752739) show that not every norm can be enforced by a guard, which is why the distinction is significant.

**Fairness of sanctions.** A sanction is justified only if the agent could have complied; this is an instance of the principle *ought implies can*. In a fleet, regimentation itself can render compliance impossible: a robot denied entry to a closed zone, or obstructed by another robot in a one-lane corridor, misses its deadline through no fault of its own. Sanctioning such a robot penalizes side effects of the regulation itself and distorts any reputation or incentive scheme built on sanctions.

Sanction fairness is formulated here as a property to be verified: *an agent is sanctioned only for its own non-compliance, never for being blocked*. [Dell'Anna, Dastani and Dalpiaz](https://webspace.science.uu.nl/~dalpi001/papers/dell-dast-dalp-20-jaamas.pdf) study the run-time revision of sanctions that prove ineffective. A different question is addressed here: the detection of unfairness that is inherent in the design. The monitor F1 approximates this property conservatively: it flags a sanction on an obligation whose task the robot abandoned after repeated access denials, but it establishes neither the cause of the denials (regulation or traffic) nor that the denials caused the missed deadline. A violation of F1 therefore identifies a candidate unfair sanction rather than a proven one.

**Norms in JaCaMo.** Moise organizations are compiled into programs of the Normative Programming Language (NPL). An NPL engine creates obligations when agents adopt roles and commit to missions, tracks their deadlines and reports violations to the organization.

**Verification of norms.** Previous work has applied model checking to norms, for example:

- ORWELL + MCAPL ([Dennis et al.](https://personalpages.manchester.ac.uk/staff/louise.dennis/pubs/climaX.pdf))
- CÒIR in Maude ([Gasparini et al.](https://abdn.elsevierpure.com/en/publications/c%C3%B2ir-verifying-normative-specifications-of-complex-systems))
- norm enforcement as supervisory control ([Dastani, Sardina and Yazdanpanah](https://research.utwente.nl/en/publications/norm-enforcement-as-supervisory-control/))

These approaches predominantly verify a normative *specification*. The present project instead verifies the *regulation machinery*: the concurrent components that monitor, enforce and modify the norms.

### 3.1 Anatomy of a norm

A conditional norm can be represented as a tuple of six components. The following table decomposes the delivery obligation of this project accordingly:

| Part | Meaning | Fleet example |
| --- | --- | --- |
| Addressee | who the norm binds (an agent or a role) | the robot playing `courier` for delivery d |
| Activation | when an instance of the norm starts | the fleet manager assigns d |
| Modality | obligation, prohibition or permission | obligation |
| Content | the state or action concerned | d is reported as delivered |
| Deadline | when the content must hold | tick of assignment + 5 |
| Sanction | what follows a violation (or reward for compliance) | a penalty recorded against the robot (in the baseline model, an abstract sanction event) |

The norm is a template: each assignment creates a new **norm instance** with its own deadline. The `ObligationManager` described in [Section 7](#7-technical-specification) maintains one record per instance.

### 3.2 Deontic logic in brief

Standard deontic logic (SDL) is a modal logic with the operators O (obligatory), P (permitted) and F (forbidden). The operators are interdefinable, and axiom D states that an obligation implies a permission, equivalently, ¬O⊥: nothing *logically* impossible is obligatory:

```latex
P(\varphi) \equiv \neg O(\neg\varphi) \qquad F(\varphi) \equiv O(\neg\varphi) \qquad O(\varphi) \rightarrow P(\varphi)
```

SDL has well-documented limitations. The most prominent concerns **contrary-to-duty** reasoning, i.e., reasoning about what is obligatory *after* a violation. An example is *"a robot must not enter a closed zone; if it does, it must stop and report"*. Chisholm's paradox demonstrates that SDL cannot represent such norms adequately.

For this reason, normative MAS usually treat norms *operationally*, as objects with a lifecycle ([Section 3.3](#33-lifecycle-of-a-norm-instance)) that are evaluated against the observed behavior of the system. P models norms in the same manner.

#### Deontic logic seen from temporal logic

For readers familiar with temporal logics such as LTL and CTL, the semantics of deontic logic follows a similar intuition. All three are *normal modal logics*: each has a box operator, its dual diamond operator, and a semantics given by Kripke structures. In each, the box distributes over implication (axiom K), and every theorem may be prefixed with a box (the necessitation rule). The logics differ in the interpretation of the accessibility relation ([Figure 7](#figure-7)). In temporal logic, the relation links a point of a run to its successors; in deontic logic, it links a world to its *ideal alternatives*, i.e., the worlds in which every norm is respected.

<a id="figure-7"></a>

![Figure 7 · the box of temporal logic and the box of deontic logic](figures/figure7.svg)

*Figure 7 · the box of temporal logic and the box of deontic logic*

|  | Temporal logic (LTL / CTL) | Deontic logic (SDL) |
| --- | --- | --- |
| Box | G φ: φ at every future point (AG: on every run) | O φ: φ in every ideal world |
| Diamond | F φ = ¬G¬φ: φ at some future point | P φ = ¬O¬φ: φ in some ideal world |
| Box of a negation | G ¬φ: φ never happens | Forb φ = O ¬φ: φ is forbidden |
| Accessibility | "later than", along a run | "ideal alternative of" |
| Characteristic axiom | T (reflexivity): G φ → φ | D (seriality): O φ → P φ |
| What ¬φ in the current state means | G φ is false: a counterexample | nothing wrong with the logic: O φ ∧ ¬φ is consistent |

A note on notation: the symbol F denotes *eventually* in temporal logic and *forbidden* in deontic logic. To avoid ambiguity, this document writes Forb for the deontic operator.

The last two rows of the table express the essential difference. The temporal operator G is reflexive: if φ holds at every point, it holds at the current one, so a single state satisfying ¬φ refutes G φ. The deontic operator O is *not* reflexive: the set of ideal worlds need not contain the actual world, so the statements "the parcel ought to be delivered" and "the parcel was not delivered" are jointly consistent. This property is essential for a normative system, in which a violation is neither a contradiction nor an error but a state that the system must be able to represent and to which it must respond. Axiom D requires only that every world have at least one ideal alternative; it thereby excludes logically conflicting obligations (O φ ∧ O ¬φ) and obligations to bring about a contradiction (O⊥). Axiom D concerns logical consistency only. It does not express the principle *ought implies can*, according to which an agent can be obliged only to do what it is practically able to do: a robot whose route has been closed is subject to an obligation that is logically consistent but practically impossible to fulfill. SDL does not represent ability and therefore cannot distinguish the two cases; the fairness monitor F1 ([Section 3.9](#39-conditions-for-a-fair-sanction)) approximates the principle at run time. Conflicting obligations are a practical concern in a fleet, for instance when a delivery deadline can be met only through a zone that has recently been closed.

#### The Andersonian reduction

[Anderson (1958)](https://doi.org/10.1093/mind/LXVII.265.100) showed that deontic logic can be reduced to an ordinary (alethic) modal logic plus one propositional constant V, read "a violation has occurred":

```latex
O\varphi \equiv \Box(\neg\varphi \rightarrow V) \qquad
P\varphi \equiv \Diamond(\varphi \wedge \neg V) \qquad
\mathit{Forb}\,\varphi \equiv \Box(\varphi \rightarrow V)
```

[Meyer (1988)](https://doi.org/10.1305/ndjfl/1093637776) applied the same idea to actions within the framework of dynamic logic: an action α is forbidden if every execution of α leads to a violation, \[α\]V, and permitted if some execution of α does not, ⟨α⟩¬V. Entering a closed zone is a forbidden action in this sense.

This reduction underlies the approach of the project. If violations are made observable events and the box is interpreted temporally, every norm becomes an ordinary temporal property *about violations*. The monitors of [Section 3.4](#34-norms-as-temporal-properties) are constructed in this way: none of them uses a deontic operator, and each refers to fulfillment, violation or sanction events.

#### Deontic and temporal readings of a trace

The reduction also clarifies *whose* behavior a given property specifies ([Figure 8](#figure-8)).

<a id="figure-8"></a>

![Figure 8 · one trace read deontically (robots) and temporally (regulator)](figures/figure8.svg)

*Figure 8 · one trace read deontically (robots) and temporally (regulator)*

- **For the robots, norms are deontic.** A robot may miss a deadline. The specification must therefore not reject such a trace; instead, it must determine the consequences. Requiring G ¬V would be inappropriate, because it would convert every norm into a regimented constraint and eliminate the autonomy that characterizes an open MAS.
- **For the regulator, properties are temporal.** The regulator must sanction every violation exactly once, must never admit a robot to a zone that the committed norm set closes, and must complete every adaptation. These are G and F properties that must hold on every run; a run that violates them reveals a defect.

Accordingly, the P monitors never assert that robots behave correctly. They assert that the *regulation* behaves correctly for every robot behavior that the model admits: S1 and S2 address regimented norms, which the regulator enforces by blocking; S3 concerns the integrity of the organization's records; R3 addresses a procedural norm that can only be monitored; L1 and R1 address sanctioned norms, to which the regulator must respond; L2, L3 and R2 address the adaptation itself, which must terminate by a commit or an explicit abort (L3) and, unless aborted, be installed (L2) within a bound (R2); and F1 addresses the sanction fairness of the responses. Table 7.2 states the enforcement mechanism of each property.

#### Kinds of norms as temporal patterns

Once violations are represented as events, each kind of norm corresponds to a characteristic temporal pattern. The following table illustrates these patterns with the norms of the fleet.

| Kind of norm | Example in the fleet | Violation V occurs when | What the regulator must guarantee |
| --- | --- | --- | --- |
| Achievement obligation with a deadline | deliver the parcel by tick Due | tick Due passes without delivery | G(created → F(fulfilled ∨ sanctioned)), L1; at run time G(created → F≤(Due+1) resolved), R1 |
| Maintenance obligation | keep zone 1 free of robots while it is closed | a robot is admitted while it is closed | regimented: G(closed → ¬admitted), S2 |
| Prohibition | no robot in a zone with the picker | both are in the zone | regimented: G ¬(robot in zone ∧ picker in zone), S1 |
| Contrary-to-duty obligation | if a robot is in a zone with the picker, it must stop | the prohibition above is violated | G(V → F≤k protective stop), a bounded response on the *reaction*; not modeled in the starter kit |
| Permission | a robot may enter an open, free zone | never: a permission cannot be violated | operational availability associated with the permission, not the permission itself: AG(request ∧ open ∧ free → EF granted), a branching property; entry may be permitted while another robot occupies the zone |

Two rows of the table require further discussion.

- **Contrary-to-duty norms become straightforward to express.** Chisholm's paradox arises in SDL because SDL represents neither time nor violations explicitly. When V is an event, the secondary obligation is triggered by that event. Temporal deontic logics with deadlines avoid the paradox by the same means. The reaction is stated as a bounded response F≤k rather than with the next-step operator X: in an asynchronous model, the event that immediately follows a violation may belong to an unrelated machine, so that X would impose an ordering that no implementation can guarantee.
- **The availability associated with a permission is not a trace property.** A permission states that the norms allow an action; whether the action can also be executed is a separate question. The operational availability associated with "a robot *may* enter" asserts that some admissible continuation allows the robot to enter. A single run in which the robot did not enter provides no evidence against it, since another robot may have occupied the zone first. In CTL, this availability corresponds to an EF property quantified over all possible futures; consequently, neither a single-trace monitor nor PObserve can check it. The P checker can only check the stronger liveness property AG(request ∧ open ∧ free → AF granted), i.e., that every such request is eventually granted, under the fairness assumptions of [Section 5.10](#510-what-a-hot-state-violation-means). Because this property is stronger than the availability, its failure does not refute the availability, and it never refutes the permission itself: it exhibits a run in which a robot was not granted entry, for example the corridor deadlock of [Section 6](#6-the-system-robots-in-a-shared-corridor), although no norm forbids entry. The report should state which of the fleet's norms become safety, liveness or branching properties.

#### Two further paradoxes

- **Ross's paradox.** From O(deliver the parcel), SDL derives O(deliver the parcel ∨ drop it in the corridor), because the box operator is closed under logical consequence. In LTL, the analogous inference G φ → G(φ ∨ ψ) is unproblematic; for obligations, however, it is counterintuitive, since dropping the parcel would appear to discharge the obligation.
- **Free-choice permission.** The statement "a robot may take corridor A or corridor B" should entail "a robot may take corridor A", yet P(φ ∨ ψ) → P φ is not valid in SDL.

These paradoxes motivate the decision of this project to specify norms *operationally*, as machines that create, fulfill and violate norm instances, and to verify them with temporal monitors rather than by reasoning in SDL. The [Stanford Encyclopedia entry on deontic logic](https://plato.stanford.edu/entries/logic-deontic/) gives a broader survey.

### 3.3 Lifecycle of a norm instance

Each norm instance evolves according to a small state machine. The monitors of [Section 7](#7-technical-specification) observe its transitions through the P events indicated under each state.

<a id="figure-9"></a>

![Figure 9 · lifecycle of an obligation instance, with the P events that mark each state](figures/figure9.svg)

*Figure 9 · lifecycle of an obligation instance, with the P events that mark each state*

An instance that remains **Active** indefinitely constitutes the failure detected by the liveness property L1. A transition from **Violated** to **Sanctioned** on an obligation whose task the robot abandoned after repeated access denials is the event flagged by the fairness monitor F1; it indicates a potentially unfair sanction, since F1 does not establish that the robot could not have complied.

**Excused obligations.** [Figure 9](#figure-9) draws, as a dashed extension, one transition that NPL provides but the starter kit lacks ([Section 3.5](#35-normative-programming-in-jacamo-npl)): from **Active** to **Inactive**, taken when the activation condition ceases to hold, for example when the organization excuses an obligation whose task was abandoned because of the regulation. Without this transition, an abandoned obligation remains active until its deadline passes, and the final far-future tick of the clock ([Section 7.1](#71-model-components)) guarantees that it is sanctioned. Consequently, a remedy for unfair sanctions must determine what happens to an abandoned obligation, not only how its deadline is computed: suspending or extending the deadline alone merely postpones the sanction (experiment E7). The fairness monitor F1 additionally depends on the order in which abandonment and sanction occur ([Section 3.9](#39-conditions-for-a-fair-sanction)).

### 3.4 Norms as temporal properties

For verification with a model checker, each kind of norm is expressed as a temporal-logic property (G = always, F = eventually). The class of the property determines how it is checked in P:

| Norm kind | Temporal property | Property class | P construct | Checked at run time? |
| --- | --- | --- | --- | --- |
| Prohibition: *never two robots in a zone* | G ¬(occupancy > 1) | safety | `assert` in a spec | yes (PObserve) |
| Obligation, deadline abstracted: *every delivery is eventually resolved* | G(assigned → F resolved) | liveness | `hot` state in a spec | no: on a finite log the verdict is always *inconclusive* |
| Obligation with deadline Due | G(assigned → F≤(Due+1) resolved) | bounded response, i.e., a safety property over time | `assert` when the clock passes Due + 1 | yes (PObserve) |
| Permission | AG(request → EF granted), the operational availability associated with the permission | branching, not a trace property | not expressible as a monitor; approximated by the stronger liveness property AG(request → AF granted) with a `hot` state | no |

In an open system, the regulation cannot guarantee that every obligation is *fulfilled*; it can guarantee only that every obligation is *resolved*, either by fulfillment or by sanction. The property checked is therefore:

```latex
\mathbf{G}\big(\mathit{assigned}(r,o) \rightarrow \mathbf{F}_{\le \mathit{Due}(o)+1}\,(\mathit{reported}(r,o) \lor \mathit{sanctioned}(r,o))\big)
```

Here Due(o) is the tick of assignment plus five. The additional tick of **grace** results from the order of events within a tick ([Figure 10](#figure-10)): the fleet manager sanctions at the first tick at which now > Due and records the sanction after that tick, so that an obligation due at tick d is resolved by tick d + 1 at the latest. The run-time monitor R1 therefore reports a violation at tick d + 2 if the obligation is still open.

<a id="figure-10"></a>

![Figure 10 · deadline, grace tick and the bounded-response monitor R1](figures/figure10.svg)

*Figure 10 · deadline, grace tick and the bounded-response monitor R1*

**Worked example: from a norm to a monitor.** The construction of L1 illustrates the general procedure.

1. *Norm.* Every delivery that is assigned is eventually either reported or sanctioned.
2. *Temporal property.* For every obligation o: G(created(o) → F(fulfilled(o) ∨ sanctioned(o))). The propositions denote events rather than states: a P trace is a sequence of events, and created(o) holds at the position at which `eObligationCreated` with identifier o occurs.
3. *Automaton.* The property is checked by a deterministic monitor with two states ([Figure 11](#figure-11)). Because the monitor stores the set of open obligations in a variable, a single automaton covers all obligations. The state in which some obligation is open is *hot*: an execution must not end, or remain forever, in it.
4. *P code.* The automaton becomes a `spec` machine, and the hot state carries the liveness requirement.

<a id="figure-11"></a>

![Figure 11 · the monitor of L1 as an automaton with a cold and a hot state](figures/figure11.svg)

*Figure 11 · the monitor of L1 as an automaton with a cold and a hot state*

```
spec EveryObligationResolved observes eObligationCreated, eObligationFulfilled, eSanctionApplied {
  var pending: set[int];
  start cold state NoneOpen {
    on eObligationCreated do (o: tObligation) { pending += (o.id); goto SomeOpen; }
  }
  hot state SomeOpen {
    on eObligationCreated do (o: tObligation) { pending += (o.id); }
    on eObligationFulfilled, eSanctionApplied do (o: tOutcome) {
      if (o.id in pending) { pending -= (o.id); }
      if (sizeof(pending) == 0) { goto NoneOpen; }
    }
  }
}
```

The version in `Common/Specs.p` additionally rejects outcomes for unknown obligations. The same procedure applies to the other classes. Safety properties (G ¬bad) translate into monitors without hot states, in which an `assert` fails on the first bad event; bounded-response properties translate into monitors that assert on each clock tick, as R1 does; unbounded liveness properties (G(p → F q)) require hot states. Properties that compare several runs, such as permissions or the counterfactual reading of sanction fairness ([Section 3.9](#39-conditions-for-a-fair-sanction)), cannot be expressed as monitors.

**Finite traces and three-valued verdicts.** A monitor that reads a finite log can reach only three verdicts ([Bauer, Leucker and Schallhart](https://doi.org/10.1145/2000799.2000800)): *violated*, when no extension of the prefix read so far satisfies the property; *satisfied*, when every extension satisfies it; and *inconclusive* otherwise. A property is *monitorable* if every prefix has an extension with a definite verdict. Safety properties, including bounded response, can be violated on a finite prefix. Liveness properties such as L1 can never be violated on a finite prefix and therefore always yield *inconclusive* on a log. A clean PObserve run on a log that stops early is likewise inconclusive with respect to R1 and R2 for every obligation or adaptation still open at its end; it does not confirm that they hold.

### 3.5 Normative programming in JaCaMo: NPL

The Normative Programming Language (NPL) of Hübner, Boissier and Bordini expresses norms as rules, each consisting of a condition and a deontic consequence with a deadline. A simplified NPL-style rule for the delivery obligation is shown below:

```
norm n_deliver:
     play(R, courier, corridor_A) & assigned(R, D)
  -> obligation(R, n_deliver, delivered(D), `now` + `5 minutes`).
```

The NPL engine maintains each obligation instance in one of four states:

- **active**: the condition holds and the deadline has not been reached;
- **fulfilled**: the content was achieved before the deadline;
- **unfulfilled**: the deadline passed without the content being achieved, i.e., the obligation was violated;
- **inactive**: the condition ceased to hold.

The organization responds to unfulfilled obligations, typically by applying a sanction. [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) extend NPL(s) and the SAI engine to support the adaptation of regulations ([Section 4](#4-background-regulation-management-in-mas)).

### 3.6 Constitutive rules: Situated Artificial Institutions

Norms refer to *institutional* facts ("a person is in zone 1", "robot 2 entered zone 1"), whereas the system observes *physical* facts ("light curtain 1 is interrupted", "robot 2 crossed marker M7"). **Constitutive rules** relate the two. In Situated Artificial Institutions (SAI; de Brito, Hübner and Boissier), they take the form *X count-as Y when C*:

- *light curtain 1 interrupted* **count-as** *a person in zone 1*
- *a message `close(zone1)` from an agent playing `picker`* **count-as** *a detect-fact for closing zone 1*

This layer is relevant to verification: if a count-as rule is incorrect, the regulation acts on incorrect facts even when every other component is correct. In this project, the count-as layer appears at two points:

- in the model, where the `announce` statements determine which events constitute institutional facts;
- at run time, in the PObserve **log parser**, which translates log lines into those facts.

The parser is therefore part of the system that must be validated.

### 3.7 Sanctions

Sanctions may be of the following types:

- **material**: a fine or the loss of a reward;
- **reputational**: a reduction of a trust score;
- **access-based**: a lower priority in task allocation or zone reservation.

Sanctions may be applied by the organization, by peers or by the environment. Sanction policies should be *proportional* and *fair*, i.e., they should penalize only behavior that the agent could have avoided ([Section 3](#3-background-norms-and-normative-mas), fairness of sanctions). In a fleet, access-based sanctions in turn affect traffic: a robot whose priority has been lowered waits longer and is therefore more likely to miss its next deadline, so that an unfair sanction can induce further sanctions.

### 3.8 Choosing an enforcement mechanism

The appropriate enforcement mechanism for a norm depends on two factors: the cost of a single violation, and whether the environment can physically prevent the forbidden action. [Figure 12](#figure-12) positions the norms of the fleet along these two dimensions.

<a id="figure-12"></a>

![Figure 12 · the norms of the fleet placed by cost and controllability](figures/figure12.svg)

*Figure 12 · the norms of the fleet placed by cost and controllability*

- **High cost, preventable: regimentation.** A zone controller can refuse entry to a robot, and a collision, or an encounter between a robot and the picker, is unacceptable. Zone capacity and zone closures are therefore regimented.
- **High cost, not preventable: monitoring complemented by a safety layer.** The MAS cannot prevent a person from walking into a zone. The norm "the picker enters only a closed zone" can therefore only be monitored (property R3), and the actual guarantee must be provided by a layer below the MAS, such as a badge gate, a light curtain, or the robots' safety-rated speed and separation monitoring.
- **Low cost, not preventable: sanctioning.** A late delivery affects throughput, not safety. The robots' autonomy to reroute or reorder tasks outweighs the benefit of strict control.
- **Low cost, preventable: a design decision.** Parking after three denials may either be enforced by the zone controller or left to the robot and sanctioned when disregarded.

The figure also indicates where verification is most critical. A regimented norm must hold in every interleaving, which is precisely the space the P checker explores. A sanctioned norm need only be resolved, by fulfillment or sanction; this is a liveness requirement and, in the fleet, also a sanction-fairness requirement.

### 3.9 Conditions for a fair sanction

A sanction is intended to influence behavior by signaling to the agent that its choice was incorrect. This function presupposes that the agent could have chosen otherwise. A robot that missed its deadline because the regulator closed its route, or because another robot occupied the next zone, did not act wrongly. Sanctioning such a robot penalizes side effects of the regulation itself, and a learning robot may infer an inappropriate policy, for example avoiding all tasks that traverse zone 1.

<a id="figure-13"></a>

![Figure 13 · a proposed sanction policy for a missed deadline](figures/figure13.svg)

*Figure 13 · a proposed sanction policy for a missed deadline*

[Figure 13](#figure-13) formalizes this principle as a decision rule. Before applying a sanction, the organization determines whether the delay was caused by a regulator or by traffic. Only if neither is the case is the delay attributed to the robot.

Two observations indicate that this is more than a matter of policy detail:

- **The required information resides in another dimension.** Denials are known to the zone controllers (environment), whereas deadlines and sanctions belong to the organization. A fair sanction requires both kinds of information; sanction fairness is therefore a cross-dimension property, of the kind that the unified view classifies but does not verify.
- **Safety and sanction fairness are independent.** The prepare–drain–commit protocol renders the closure safe, yet the starter kit is expected to sanction robots that abandon their tasks after repeated denials, so that F1 is expected to fail under both protocols. This failure follows from the kit's policy rather than from a subtle interaction: nothing in the kit excuses an abandoned obligation ([Section 3.3](#33-lifecycle-of-a-norm-instance)). A remedy lies within the organization and must determine the status of abandoned obligations, for instance by excusing those whose denials were caused by the regulation; suspending deadlines alone is not sufficient.

**The property class of sanction fairness.** The intended property, *a robot is sanctioned only if it could have complied*, is counterfactual: it compares the actual run with alternative runs in which the robot might have acted differently. Such properties relate several traces (they are hyperproperty-like, or causal) and cannot be decided by observing a single trace. F1 is a safety property over single traces that approximates the intended one: it flags a sanction on an obligation whose task the robot abandoned after repeated denials. Every flagged case is a candidate for an unfair sanction, but the approximation is incomplete in two respects. First, it establishes neither that the robot could not have complied nor whether the denials were caused by the regulation or by traffic; the refined, cause-aware monitor of phase 3 narrows this gap by recording the cause of each denial. Second, it depends on the order of events, as described next. In the terms of [Section 3.2](#32-deontic-logic-in-brief), F1 is a run-time check of an approximation of *ought implies can*.

**Order sensitivity of F1.** F1 flags a sanction only if the abandonment of the same obligation was observed earlier. If the deadline passes while the robot is still retrying, the sanction precedes the abandonment and F1 remains silent, although the situation is essentially the same ([Figure 14](#figure-14)). At run time, the two events are recorded by different nodes (the robot and the fleet manager) with different clocks, so that clock skew can reverse their order in the merged log and change the verdict ([Section 5.12](#512-clock-skew-and-causal-order)). Students either refine the monitor so that it correlates abandonment and sanction on the obligation identifier regardless of their order, or report the resulting false negatives as a threat to validity. A refined monitor is accepted only if it flags both orders on the two probe traces of the independent evaluation (abandonment before sanction, and sanction before abandonment; reviews/evaluation-2026-10-21). Counts of flagged sanctions are counts of candidates under the chosen monitor, not counts of all unfair sanctions: in 500 simulator runs, F1 was violated in every run, and 3,468 of 4,479 sanctions were flagged when abandonment and sanction are correlated on the obligation identifier, against 4,255 with the earlier correlation on the agent.

<a id="figure-14"></a>

![Figure 14 · F1 in the two possible orders of abandonment and sanction](figures/figure14.svg)

*Figure 14 · F1 in the two possible orders of abandonment and sanction*

**Self-check questions ([Section 3](#3-background-norms-and-normative-mas)).**

1. Why would requiring G ¬V of the robots be a modeling error, and which property of the regulator replaces it?
2. Why does axiom D not capture the situation of a robot whose route has been closed?
3. Why can L1 never be violated on a finite log, whereas R1 can?
4. Which two limitations prevent a violation of F1 from proving that a sanction was unfair?

## 4. Background: regulation management in MAS

Regulation management balances the autonomy of the agents against control over the system as a whole. It encompasses how regulations are represented, monitored, enforced and modified at run time. [Yan, Nardin, Boissier and Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) propose a **unified view** that characterizes any design along three perspectives, and they use the resulting grid to classify existing MAS frameworks. [Figure 15](#figure-15) places the fleet in this grid.

| Perspective | Options | This project (fleet) |
| --- | --- | --- |
| Regulation capabilities | what the regulation layer can do; operationalized here as *represent, monitor, enforce (regiment or sanction), adapt* | all four |
| MAOP dimension | agent-, environment-, interaction-, organization-centric, or hybrid (several at once) | **hybrid**: environment (zone controllers) + organization (fleet manager, closures); the robots are regulated agents, and their decision to park is compliance behavior, not regulation management |
| Architectural style | centralized vs. decentralized / distributed regulators | **distributed regimentation**: one controller per zone deciding locally; adaptation (one coordinator) and sanctioning (one fleet manager) are **centralized** |

<a id="figure-15"></a>

![Figure 15 · the fleet placed in the unified-view grid](figures/figure15.svg)

*Figure 15 · the fleet placed in the unified-view grid*

The COINE 2025 paper is openly available from the [workshop website](https://coin-workshop.github.io/coine-2025-detroit/papers/paper_6.pdf). It defines three run-time capabilities: regiment, enforce (comprising monitoring, deliberation about regulated behavior, and sanctioning) and adapt; the creation of regulations lies outside its scope, and an agent's deliberation to comply with or violate a regulation is explicitly not a capability. Its unified view classifies systems as organization-centric, agent-centric or hybrid-centric (organization and agent combined), and as fully centralized, semi-(de)centralized or fully decentralized; environment- and interaction-centric approaches are discussed only briefly. The four capabilities used in this specification (represent, monitor, enforce, adapt) and the grid with environment- and interaction-centric rows are a teaching adaptation of that classification; where the two differ, the paper is authoritative.

**Regulation adaptation.** Regulations change at run time, for example when a picker requires an aisle, a zone is flooded or a robot breaks down in a lane. [Yan et al. (ECAI 2025)](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) propose a general adaptation model with three capabilities, each of which produces a fact:

1. **Detect**: recognize a change that requires new regulation (producing a *detect-fact*).
2. **Design**: determine the new regulation (producing a *design-fact*).
3. **Execute**: install the new regulation in the running system (producing an *execute-fact*).

Constitutive and regulative norms determine who may perform each step and under which conditions. The authors implement the model by extending the SAI and NPL(s) normative engines within JaCaMo.

**Challenges of the distributed style.** With a single regulator, executing an adaptation amounts to one local update. With one regulator per zone, the update must reach every controller. Messages arrive in an arbitrary order, and agents continue to act while messages are in transit. During this interval, controllers may disagree, and a robot may be admitted under the superseded rules. A protocol modeled on two-phase commit from distributed databases removes this interval:

- **Prepare.** The affected controllers stop admitting robots and drain the zone.
- **Commit.** The new norm set takes effect only after every controller has acknowledged.

The protocol, however, introduces a new risk: draining presupposes that robots are *able* to leave, and in a one-lane corridor they may obstruct one another.

**Research gap addressed.** The unified view is a *classification*: it describes where regulation resides, not whether a given design is correct. Interactions among distributed regulators, physical constraints and sanctions can be identified only by exploring message interleavings, which is the subject of [Section 5](#5-background-the-p-language-and-pobserve).

### 4.1 The capabilities in detail

Each capability corresponds to a design question, and different designs may realize the same capability in substantially different ways.

| Capability | Question it answers | Design options | In this fleet |
| --- | --- | --- | --- |
| Represent | Where and how are the norms written down? | implicit in agent or controller code; explicit declarative norms (NPL); versioned norm sets | a versioned norm set: the set of closed zones, plus delivery obligations in the fleet manager |
| Monitor | Who observes what, and is it enough to detect a violation? | agents monitor themselves; artifacts observe actions on them; the organization collects reports | zone controllers observe entries and exits; the fleet manager observes reports and the clock |
| Enforce | What happens to a violation? | regimentation (it cannot happen) or sanctioning (it is detected and punished) | regimented zone capacity and closures; sanctioned deadlines |
| Adapt | How do the norms change at run time, and who may change them? | detect, design and execute steps, each run by an agent, an artifact or the organization | the picker detects; the coordinator designs and executes; the zone controllers install |

**Observability.** A norm can be monitored only if its content is observable. The norm *"no robot in a zone with a person"* requires both robot positions and person detection. If the light curtain of zone 1 fails, the regulation cannot detect the person and ceases to protect them without any indication. Run-time monitoring with PObserve evaluates what the logs record and therefore is subject to the same observability limitations.

### 4.2 The MAOP views, with examples

The unified view locates regulation along the four MAOP dimensions. The examples below are representative systems for each view; they reflect the interpretation adopted in this specification rather than the classification of the paper, which is summarized in the paragraph on the COINE 2025 paper above.

| View | Regulation is represented and managed by… | Typical mechanism | Strength | Weakness |
| --- | --- | --- | --- | --- |
| Agent-centric | the agents themselves | agents that themselves monitor norms or propose norm changes, e.g. agents that report violations by others (an agent that decides whether to comply is regulated, not managing regulation) | full autonomy; no central component | relies on agents being honest and correct |
| Environment-centric | artifacts in the environment | CArtAgO artifacts or smart controllers that refuse forbidden actions | strong guarantees (regimentation) | only for actions that pass through an artifact |
| Interaction-centric | the protocols agents use to communicate | electronic institutions whose governors filter messages; commitment protocols | detects violations in communication | blind to physical actions |
| Organization-centric | an organizational infrastructure | Moise roles and missions with an NPL engine | explicit, inspectable norms | needs reliable reports from agents and environment |
| Hybrid | several of the above together | e.g. organization for obligations + environment for safety | each norm enforced where it is cheapest and strongest | the parts must stay consistent with each other |

The fleet follows the hybrid view. Safety norms reside in the environment (zone controllers), performance norms in the organization (fleet manager); the robots are regulated agents, and their decision to abandon a task is compliance behavior, not regulation management. The consistency among these parts is the subject of this project.

### 4.3 Architectural styles

| Style | Structure | Advantages | Risks |
| --- | --- | --- | --- |
| Centralized | one regulator for the whole system | one consistent view; simple to verify | bottleneck and single point of failure; does not scale to large sites |
| Hierarchical | regulators per area under a supervisor | local decisions with global oversight | the supervisor still observes changes with a delay |
| Distributed | several peer regulators, each owning part of the system | scales; local, fast decisions; no single point of failure | regulators can disagree during a change; needs a coordination protocol |

Warehouses with hundreds of robots typically require the distributed style. Its smallest non-trivial instance, three zone controllers, is studied here.

Strictly, the fleet combines two styles: regimentation is distributed, whereas adaptation, time and sanctioning are centralized.

| Responsibility | P machine | Style | Where it runs |
| --- | --- | --- | --- |
| Admission to a zone (regimentation) | `ResourceGuard`, one per zone | distributed | each zone controller decides from its own occupancy and its installed norm set |
| Change of the norm set (adaptation) | `AdaptationCoordinator`, one | centralized | one coordinator runs prepare and commit with every zone controller |
| Obligations, deadlines and sanctions | `ObligationManager`, one | centralized | the fleet manager |
| Logical time | `Clock`, one | centralized | only the obligation manager subscribes to it |

The coordinator, the fleet manager and the clock are single points of coordination and of failure. The model does not represent their failure; the optional coordinator-crash extension of the assignment addresses it.

### 4.4 Adaptation as a control loop

The detect–design–execute model of [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) is analogous to the **MAPE-K loop** of autonomic computing (Kephart and Chess, 2003), which comprises the steps Monitor, Analyze, Plan and Execute over shared Knowledge:

| MAPE-K step | Adaptation capability | Fleet example |
| --- | --- | --- |
| Monitor + Analyze | detect | the picker's request is recognized as a need to close zone 1 |
| Plan | design | the coordinator computes norm set v + 1 with zone 1 closed |
| Execute | execute | the zone controllers install v + 1 |
| Knowledge | the norm sets and the organization's state | current version, closed zones, open obligations |

The two models differ in one significant respect: in a normative MAS, the adaptation loop is **itself regulated**. Constitutive norms define which facts count as a valid trigger, and regulative norms define who may perform each step, e.g., *only an agent playing `picker` or `safety_officer` may request a closure*. An unauthorized closure request therefore constitutes a violation in its own right. The starter coordinator does not check roles; role-based authorization is a conceptual extension.

### 4.5 Consistency during a regulation change

The **transition window** is the interval between the decision to change the norms and the moment at which every regulator applies the change. Three hazards arise within it:

1. **Stale admission.** A controller still operating under the previous norm set admits a robot into a zone that the new set closes (property S2). S2 is a closure property: it requires only that an admitted zone is not closed by the last committed norm set, and it does not require that the admission carry the committed version, because a controller that the change does not affect legitimately admits robots under the previous version while the change propagates (probe tcStaleOpenZone of the independent evaluation, reviews/evaluation-2026-10-21/probe-stale.txt).
2. **Premature entry.** The person enters before the zone has been drained (properties S1 and R3).
3. **Lost or reordered updates.** Two adaptations overlap, and controllers apply them in different orders. Version numbers and the serialization of adaptations in the coordinator prevent this hazard.

The remedy is a protocol modeled on **two-phase commit** from distributed databases, reduced to three steps: *prepare* (the affected controller stops admitting robots), *drain* (it waits until its zone is empty) and *commit* (the new norm set takes effect everywhere). It is therefore more precisely a **prepare–drain–commit barrier**: unlike classical two-phase commit, the participants do not vote, and there is no abort path. Two kinds of blocking must be distinguished. In classical two-phase commit, blocking arises when the coordinator fails after the participants have prepared, leaving them uncertain about the outcome; the starter kit does not model coordinator failure. In the fleet, blocking arises instead when a participant cannot complete its prepare phase: the controller of zone 1 waits for a robot that cannot leave because the next zone is held by another robot. Whether this can occur is the subject of liveness property L2. The protocol is also an instance of the quiescence-based approach to dynamic reconfiguration of [Kramer and Magee](https://doi.org/10.1109/32.60317), in which a component is changed only after it has been brought to a quiescent state, here an empty zone. A variant with a timeout and an abort path, in which the coordinator cancels the adaptation if the zone does not drain in time, is evaluated in experiment E9. For this variant, property L3 (AdaptationTerminates) requires that every started adaptation be committed or explicitly aborted (log event ADAPT\_ABORT); L2 remains the stronger requirement that the change be installed, and it fails by design for an aborted change.

### 4.6 The inconsistency window

With one controller per zone, there is no single instant at which the rules change: each controller learns of the new norm set when the corresponding message arrives. [Figure 16](#figure-16) depicts the versions held by each controller over time.

<a id="figure-16"></a>

![Figure 16 · versions of the norm set in each zone controller over time](figures/figure16.svg)

*Figure 16 · versions of the norm set in each zone controller over time*

- **Naive protocol (top).** The coordinator commits v1 and informs the picker that the zone is closed. Zones 0 and 2 install v1 promptly, whereas the message to zone 1 is delayed. During the shaded interval, zone 1 still operates under v0 and admits robot 1, while the picker already acts under v1. Consequently, both S1 and S2 can be violated.
- **Two-phase protocol (bottom).** Zone 1 stops admitting robots at *prepare* and drains. The commit occurs only after the zone is empty. The zones still install v1 at slightly different times, so an interval of inconsistency remains; within it, however, no behavior depends on the difference, because zone 1 is closed to robots under both versions.

This observation extends beyond the corridor considered here. In a distributed regulator, a change of norms is not an assignment but a protocol. Its correctness must be established over all possible message delays, which is why it is verified with a model checker rather than by inspection of the norm sets.

**Self-check questions ([Section 4](#4-background-regulation-management-in-mas)).**

1. Why is the fleet's adaptation protocol a barrier rather than a full two-phase commit, and which failure does it not tolerate?
2. Which hazard of the transition window does S2 detect, and which does R3 detect?
3. Why is an inspection of the norm sets insufficient to establish that a change of norms is safe in a regulator with distributed regimentation?

## 5. Background: the P language and PObserve

P models a system as a collection of **state machines that communicate through asynchronous events**. Its checker explores alternative orderings of these events in search of an ordering that violates a property. P was developed at Microsoft Research ([Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/)) and is used at AWS for services such as S3, DynamoDB and EC2.

P has also been applied in robotics. SOTER ([Desai et al.](https://arxiv.org/pdf/1808.07921)) builds runtime-assured robot software on P, and [SOTER on ROS](https://escholarship.org/uc/item/5r78g42p) ports it to the Robot Operating System. A fleet with one controller per zone belongs to the class of asynchronous systems that P is designed to analyze.

**Core concepts:**

| Concept | P syntax | Meaning |
| --- | --- | --- |
| Event | `event eAccessRequest: tAccess;` | a typed message |
| Machine | `machine Robot { … }` | an actor with local variables and an input queue |
| State and handler | `state Moving { on eAccessDenied do (z: int) { … } }` | how the machine reacts to an event in a state |
| Send | `send guards[next], eAccessRequest, (agent = id, …);` | asynchronous message to another machine |
| Defer / ignore | `defer eX;` / `ignore eX;` | keep the event for later / drop it in this state |
| Nondeterminism | `if ($) { … }` | the checker resolves the choice differently across schedules: models robots that may not report |
| Monitor (spec) | `spec S observes eA, eB { … }` | a global observer that asserts properties |
| Announce | `announce eTaskAbandoned, (id = job.id, agent = id, where = z);` | notify monitors without sending to any machine |
| Hot / cold state | `hot state InProgress { … }` | liveness: an execution must not stay in a hot state forever |
| Test case | `test tc [main=Test]: assert S in { … };` | a closed system plus the monitors to check |

The fairness monitor of this project illustrates how a normative property is expressed as a P specification:

```
// id = the obligation whose task was abandoned
type tAbandon = (id: int, agent: int, where: int);
event eTaskAbandoned: tAbandon;

spec SanctionsReflectMisconduct observes eTaskAbandoned, eSanctionApplied {
  var abandoned: set[int];     // obligation ids abandoned after denials
  start state Watching {
    on eTaskAbandoned do (a: tAbandon) { abandoned += (a.id); }
    on eSanctionApplied do (o: tOutcome) {
      assert !(o.id in abandoned),
        format("obligation {0} of robot {1} sanctioned after the robot abandoned it following repeated access denials",
               o.id, o.agent);
    }
  }
}
```

**Checking.** The command `p compile` builds the project, and `p check -tc <test> -s 10000` executes 10,000 schedules of the given test case. A failed assertion produces a trace under `PCheckerOutput/BugFinding/`, which can be replayed with the corresponding seed. The checker is a bug-finding tool: it samples a large number of schedules but does not establish correctness, not even for the small configuration ([Section 5.9](#59-what-n-schedules-guarantee)).

**Modules and refinement.** [Desai's ModP work](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2020/EECS-2020-3.pdf) introduces a module system for compositional, assume–guarantee reasoning, with which it can be shown that a composition of modules refines an abstract specification. This capability underlies research question 3. Before these features are relied upon, it must be determined which of them the current P release supports.

**PObserve: the same monitors at run time.** PObserve checks logs of a deployed system against P specifications. The procedure is as follows:

1. `p compile --mode pobserve` compiles the monitors (without the model machines) into Java classes: `PEvents`, `PTypes` and `PMachines`.
2. A Java **log parser** translates each log line into a P event together with a partition key (here, the site or warehouse).
3. The PObserve command-line interface (`java -jar PObserve-1.0.0.jar --jars <package> --spec <Monitor> -l <log>`) or its JUnit integration replays the events through the monitor.
4. PObserve reports the first violation together with a replay of the events that led to it.

<a id="figure-17"></a>

![Figure 17 · design-time and run-time checking share most monitors](figures/figure17.svg)

*Figure 17 · design-time and run-time checking share most monitors*

Design-time and run-time checks therefore share most of their definition of correctness, but not all of it ([Figure 17](#figure-17)): R1 and R2 are checked only at run time, and L1 and L2 only at design time ([Section 5.11](#511-vacuity-and-sanity-checks)). By default, PObserve sorts the events of each partition key by timestamp before replaying them; logs from several fleet nodes therefore require synchronized clocks (NTP or PTP), and the effect of clock skew is discussed in [Section 5.12](#512-clock-skew-and-causal-order).

PObserve reports assertion failures but does not report hot states that remain open at the end of a finite log. Liveness properties are therefore reformulated as **bounded-response** properties for run-time checking.

**Scope of each check.** The checker and PObserve answer different questions, and neither can replace the other ([Figure 18](#figure-18)).

<a id="figure-18"></a>

![Figure 18 · what the checker and PObserve can each establish](figures/figure18.svg)

*Figure 18 · what the checker and PObserve can each establish*

- **The checker** explores many schedules, but only schedules of the model. A violation that it reports reflects the real system only to the extent that the model is faithful; a violation in the "model only" region is an artifact of abstraction, for example of robots moving between zones instantaneously. The absence of violations constitutes evidence about the design, bounded by the number of schedules explored.
- **PObserve** examines few executions, but executions of the deployed system. A violation that it reports did occur, insofar as the log is accurate. It provides no information about executions that were not logged, nor about faults that the log cannot reflect, such as a localization error that places a robot in the wrong zone.
- **The intersection** is where the two methods overlap: the same monitor, written once, evaluates both the design and the running fleet. A counterexample from the checker can serve as a test log, and a violation reported by PObserve can serve as a new test case for the model.

The region outside both sets motivates a safety layer below the MAS: no software check covers a failure that can be expressed neither in the model nor in the log.

### 5.1 Types and data

P is statically typed and provides the following types:

- **Primitive types:** `int`, `bool`, `float`, `string`, `machine` (a reference to a machine) and `event`.
- **Collections:** `seq[T]`, `set[T]`, `map[K, V]`.
- **Tuples:** named, e.g. `(agent: int, res: int, ver: int)`.
- **Enums and type aliases:** `type tNormSet = (ver: int, closed: set[int]);`.

Values are copied when sent, so machines share no memory. All coordination takes place through messages, which is both the source of the difficulty of distributed regulation and the dimension that the checker explores.

### 5.2 Machine lifecycle

```
machine ZoneController {
  var occupants: set[int];
  start state Init {
    entry (cfg: (zone: int, capacity: int)) {   // payload given to `new`
      goto Open;
    }
  }
  state Open {
    on eAccessRequest do (r: tAccess) { /* admit or deny */ }
    on eNormPrepare goto Draining;                // leave Open, enter Draining
    ignore eTick;                                 // explicitly not interested
  }
  state Draining {
    entry { /* stop admitting; ack when empty */ }
    defer eNormPrepare;                           // keep it queued for later
  }
}
```

- `new ZoneController((zone = 1, capacity = 1))` creates a machine and runs its start state's `entry` with the payload.
- `goto S` runs the current state's `exit`, then `S`'s `entry`.
- `raise e` handles an event immediately inside the same machine.
- `this` is the machine's own reference, used to receive replies.

### 5.3 Communication semantics

- `send m, e, payload;` is **asynchronous**: the sender continues immediately, and the event is appended to the single input queue of `m`.
- Events from one sender to one receiver are delivered in the order in which they were sent, whereas events from different senders may interleave in any order. The checker explores these interleavings.
- By default, messages are not lost. Failures, such as a crashed controller or a lost message, must be modeled explicitly, for example with a machine that may drop or delay messages using `$`.
- **Unhandled events are errors.** If a machine receives an event that its current state neither handles, defers nor ignores, the checker reports a bug. This rule exposes protocol gaps early, such as a controller receiving `eRelease` while draining. `defer` and `ignore` should therefore be introduced deliberately, and never merely to suppress a checker error.

### 5.4 Specification monitors

A `spec` machine is a global observer with the following characteristics:

- It declares the events that it `observes` and executes synchronously each time one of these events is sent or announced.
- It cannot send events; it can only update its own variables and evaluate `assert` statements.
- An execution may terminate in a **cold** state, whereas a **hot** state must eventually be exited. [Section 5.10](#510-what-a-hot-state-violation-means) explains when the checker reports a liveness violation.
- `announce e, payload;` delivers an event to monitors only. Machines use it to publish institutional facts (an entry, a commit, a sanction) without sending them to another machine.

### 5.5 How the checker explores

The checker replaces the scheduler of the real system. At each step, it determines which machine executes next and how each `$` choice is resolved.

A single run up to a step bound is called a **schedule**, and the option `-s 10000` requests 10,000 schedules. Exploration strategies range from random choices to priority-based strategies designed to reach deep bugs with few context switches. Each reported bug is accompanied by the seed that reproduces it.

The search detects bugs but does not prove their absence. Models should therefore be kept small (two robots, three zones and a bounded clock) and enlarged only after the small model satisfies its properties.

**Why interleavings matter.** Failures in a concurrent system arise from particular orderings of events rather than from individual events. Consider three events of a naive closure of zone 1: robot 1 is admitted to zone 1 (A), the coordinator commits v1 (C), and zone 1's controller installs v1 (I). In the naive protocol, I always follows C, which leaves three possible orderings ([Figure 19](#figure-19)).

<a id="figure-19"></a>

![Figure 19 · the orders of three closure events under the naive protocol](figures/figure19.svg)

*Figure 19 · the orders of three closure events under the naive protocol*

Only one of these orderings is safe. If the robot is admitted before the commit, it is not drained, and the picker subsequently enters a zone that the robot occupies. If it is admitted between the commit and the installation, zone 1 applies a rule that has already been superseded. Neither failure results from a defect in an individual component, since each controller behaves as specified. Testing would reveal these failures only if message delays happened to align, which is rare in a laboratory setting but plausible in a heavily loaded warehouse network.

The checker samples schedules; for a race of this size, which involves few events and few context switches, it finds the unsafe orderings with high probability ([Section 5.9](#59-what-n-schedules-guarantee)). The two-phase protocol does not make the unsafe orderings less likely; it eliminates them, because zone 1 refuses new robots and is emptied before the commit. A modification that only makes a race less frequent, such as a delay before the commit, leaves both unsafe branches in the tree.

### 5.6 Common pitfalls

- **Over-deterministic test drivers.** If a test always starts the picker after the robots, many bugs cannot manifest. Nondeterministic choices (`$`) and several drivers should be used to widen the set of reachable orderings.
- **Monitor timing.** A monitor observes an event when it is *sent*, before the receiver processes it. A clock tick is therefore visible to a monitor before the fleet manager has applied it. For this reason, the run-time deadline monitors (R1, R2) are not used in the checker.
- **Liveness and fairness.** The interpretation of hot-state violations depends on fairness assumptions ([Section 5.10](#510-what-a-hot-state-violation-means)). Each liveness violation must be classified as a defect of the design or as an artifact of the scheduling assumptions before it is reported.
- **Unbounded models.** An unbounded clock or retry loop yields unbounded schedules. Such loops must be bounded (`maxTicks`, a retry limit), and the bounds must be reported.

### 5.7 Mapping normative concepts to P

| Normative concept | P construct | Where in the starter kit |
| --- | --- | --- |
| Norm set (closed zones) | a versioned tuple `tNormSet` | `Common/MonitorEvents.p` |
| Regimented prohibition | admission check in a machine + `assert` in a monitor | `ResourceGuard.p`, `Specs.p` (S1) |
| Obligation instance | an entry in a `map` keyed by obligation id | `ObligationManager.p` |
| Deadline | logical clock events `eTick` | `Clock.p` |
| Violation and sanction | deadline check on each tick, then `eSanction` + `announce eSanctionApplied` | `ObligationManager.p` |
| Constitutive rule (count-as) | which `announce` a machine makes; at run time, the log parser | machines; `FleetRegulationParser.java` |
| Adaptation (detect, design, execute) | coordinator states and the prepare/ack/commit events | `AdaptationCoordinator.p` |
| Open agent | nondeterministic `$` choices | `Robot.p` |
| Fairness meta-norm | a monitor over `eTaskAbandoned` and `eSanctionApplied` | `PSpec/FleetSpecs.p` (F1) |

### 5.8 PObserve in more detail

- **Partition keys.** The parser assigns a key to each event. All events with the same key are delivered, in timestamp order, to a dedicated instance of the monitor. The key must be chosen such that every property depends only on the events of a single key. Here, the key is the site, because a closure involves all zones of a site.
- **Ordering.** By default, PObserve sorts the events of each key by timestamp before replaying them; with the option `--assumeInputsAreSorted`, it merges the input files without sorting and reports every out-of-order event as an error. PObserve also retains a replay window of recent events (`--replay`) for reporting. The clocks of fleet nodes must be synchronized, and timestamps require microsecond precision.
- **Parser contract.** `apply(logLine)` returns a stream of zero or more events and an empty stream for lines that do not represent regulation events. The parser must not hold static mutable state, because PObserve executes parsers on several threads.
- **Generated classes.** `p compile --mode pobserve` names tuple classes after their abbreviated field names; for example, `(agent, res, ver)` becomes `PTuple_agent_res_ver`. The generated `PTypes.java` should be inspected before the parser is written.
- **Execution modes.** JUnit tests are suited to continuous integration on recorded logs, whereas the command-line interface is suited to on-demand checking of production logs.

**Learning path (days 1–7):**

- [ ] Install P and work through the repository's `P-Tutorial` (days 1–7); as further reading, study the official tutorials ([p-org.github.io/P](https://p-org.github.io/P/)) ClientServer and TwoPhaseCommit; the latter is directly relevant to this project.
- [ ] Study the PObserve documentation: [overview](https://p-org.github.io/P/advanced/pobserve/pobserve/), [log parser](https://p-org.github.io/P/advanced/pobserve/logparser/) and [command-line interface](https://p-org.github.io/P/advanced/pobserve/pobservecli/).
- [ ] Build and run the LockServer PObserve example in the P repository (`Src/PObserve/Examples/LockServerPObserve`).
- [ ] Read [Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/), sections 1–3, and the SOTER paper ([arXiv 1808.07921](https://arxiv.org/pdf/1808.07921)).

### 5.9 What N schedules guarantee

`p check -s N` executes N schedules, each of which resolves every scheduling decision and every `$` choice according to a search strategy, for instance random choices or probabilistic concurrency testing (PCT; [Burckhardt et al.](https://doi.org/10.1145/1736020.1736040)); the available strategies and their option names should be taken from `p check --help` of the installed release. The search samples the space of schedules; it does not enumerate it. A run without a violation is therefore statistical evidence, not a proof, even for the small configuration.

For PCT, Burckhardt et al. give a lower bound on the probability that a single schedule exposes a bug of *depth* d, i.e., a bug that requires d specific ordering constraints between events: at least 1/(n · k^(d−1)), where n is the number of machines and k the number of steps of a schedule. The races of this project have small depth (the unsafe closure of [Figure 19](#figure-19) requires only that one admission occur between a commit and an installation), so that they are expected to be found after few schedules, whereas bugs of greater depth may require many more.

The choice of N is justified by three arguments, which the report states:

1. **Small-scope hypothesis.** Most design errors are exhibited by small configurations (two robots, three zones); larger configurations are examined in experiment E8.
2. **Calibration with seeded bugs.** A known defect (the naive protocol, or a mutant from [Section 5.11](#511-vacuity-and-sanity-checks)) is reintroduced, and the number of schedules needed to find it is measured over several seeds. N is then chosen as a generous multiple of this number.
3. **Reporting.** Every result states N, the strategy, the step bound, the seeds and the P version in the validation record.

In this project, exploratory runs use `-s 10000`, and the final evidence for experiment E1 uses `-s 100000`, justified by the calibration.

### 5.10 What a hot-state violation means

A monitor in a hot state represents an obligation of the system that has not yet been discharged. The checker reports a liveness violation in two situations: when an execution terminates, i.e., no machine can take a step, while a monitor is in a hot state; and when a monitor remains in a hot state for more consecutive steps than a threshold (the *liveness temperature*) in a long execution. The second criterion is a heuristic for infinite executions; the exact options and defaults should be taken from the documentation of the installed release.

Liveness verdicts depend on **fairness assumptions** about the scheduler:

- **Weak fairness:** a machine that is *continuously* enabled is eventually scheduled.
- **Strong fairness:** a machine that is enabled *infinitely often* is eventually scheduled.

The retry loop of experiment E5 illustrates the difference. If two robots hold each other's next zone, neither request can ever succeed, and the violation of L2 is genuine under any fairness assumption. If, instead, one robot is repeatedly overtaken by another that re-acquires the zone, the request of the first robot is enabled infinitely often but not continuously, and only strong fairness guarantees that it is eventually granted. A reported violation that relies solely on such starvation is classified as an artifact of the scheduling assumptions rather than as a defect.

Nondeterministic choices `$` are **not** assumed to be fair: the checker may resolve a choice in the same way in every iteration. A robot that may never release its zone because of a `$` choice therefore represents a behavior that the model explicitly admits, and the resulting violation of L2 is genuine with respect to the model. L1 requires that the obligation manager eventually processes every tick; L2 requires that every robot in a zone to be drained eventually leaves it, which in turn requires parking or another remedy for the corridor deadlock ([Section 6](#6-the-system-robots-in-a-shared-corridor)).

### 5.11 Vacuity and sanity checks

A monitor that never fails provides evidence only if it *can* fail. Two features of the starter kit make some properties hold by construction:

- The clock ends every execution with a far-future tick ([Section 7.1](#71-model-components)), which causes every open obligation to be sanctioned. L1 therefore holds as long as the obligation manager processes this tick; it does not establish that obligations are resolved in time, which only R1 checks.
- The picker in the model always waits for the commit before entering, so that R3 cannot fail in the model, although it is a meaningful run-time property.

For each monitor, a **mutant** of the model that is expected to violate it is therefore required: for example, an obligation manager that never sanctions (L1, R1), a coordinator that commits before the zone is empty (S1, S2, R3), a picker that does not wait (R3), a duplicated sanction (S3) and a zone controller that never acknowledges (L2). In addition, **event coverage** is reported: for each monitor, the number of observed events of each type in the explored schedules, which demonstrates that the monitored situations actually occur.

The checker and PObserve also share only part of the monitors. R1 and R2 are not run in the checker, because the model announces `eTick` before the obligation manager acts on it ([Section 5.6](#56-common-pitfalls)); L1 and L2 are not run by PObserve, because a finite log cannot violate them ([Section 3.4](#34-norms-as-temporal-properties)). Two remedies are possible: announcing a separate event after the obligation manager has processed a tick, so that R1 and R2 can also run in the checker, or an argument in the report that R1 implies L1 for logs that extend sufficiently far beyond the last deadline.

### 5.12 Clock skew and causal order

PObserve orders the events of a partition key by their timestamps. In a fleet, these timestamps originate from different nodes: zone controllers, robots, the fleet manager and the coordinator. Microsecond *precision* of a timestamp does not imply microsecond *accuracy*: clocks synchronized by NTP typically differ by milliseconds, which may exceed the latency of a message between two nodes. Two causally related events, for example a `COMMIT` and a subsequent `ENTER` at another node, can therefore appear in the merged log in the wrong order.

The effect depends on the property. S2, as implemented, compares each admission with the most recently logged commit and is therefore sensitive to skew between the coordinator and the zone controllers. However, each `ENTER` line also carries the version `Ver` of the norm set under which the admission was decided; this field acts as a logical clock, which allows a refined monitor to check the consistency of versions independently of timestamps. F1 has no such field and depends entirely on the timestamp order of `ABANDON` and `SANCTION`, which are recorded by different nodes ([Section 3.9](#39-conditions-for-a-fair-sanction)). The report states the assumed synchronization accuracy, identifies the monitors whose verdict depends on cross-node order and treats clock skew as a threat to validity; injecting artificial skew into a simulated log is a suitable experiment.

### 5.13 Common misconceptions

- **"No bug was found in N schedules, so the design is correct."** The checker samples schedules ([Section 5.9](#59-what-n-schedules-guarantee)); the result is evidence whose strength depends on N, on the strategy and on calibration.
- **"A violation of F1 proves that a sanction was unfair."** F1 flags candidates only ([Section 3.9](#39-conditions-for-a-fair-sanction)).
- **"A clean PObserve run shows that the system is safe."** It shows that the logged executions violated no safety monitor, insofar as the log is complete and correctly ordered; liveness properties remain inconclusive ([Section 3.4](#34-norms-as-temporal-properties)).
- **"`defer` or `ignore` resolves an unhandled-event error."** These constructs change the protocol; they must be justified and must never be added merely to silence the checker ([Section 5.3](#53-communication-semantics)).
- **"A monitor that always holds is a good monitor."** It may be vacuous ([Section 5.11](#511-vacuity-and-sanity-checks)).

**Self-check questions ([Section 5](#5-background-the-p-language-and-pobserve)).**

1. Why can L1 not be checked by PObserve, and which property replaces it at run time?
2. How is the number of schedules needed to find the naive-protocol bug measured, and how does it inform the choice of `-s`?
3. Why is the violation of L2 in experiment E5 genuine under any fairness assumption?
4. Why does clock skew affect F1, and how could the `Ver` field make a check of S2 robust against it?

## 6. The system: robots in a shared corridor

Two mobile robots deliver goods through a one-lane corridor consisting of three zones (0, 1 and 2), each with capacity 1 and its own zone controller. Robot 1 travels 0 → 1 → 2 and robot 2 travels 2 → 1 → 0; their paths therefore meet head-on. A fleet manager assigns deliveries with deadlines. At unpredictable times, a human picker requires access to zone 1, which first necessitates a **zone closure**: a regulation adaptation that closes zone 1 to robots ([Figure 1](#figure-1)).

<a id="figure-20"></a>

![Figure 20 · fleet architecture, components by MAOP dimension](figures/figure20.svg)

*Figure 20 · fleet architecture, components by MAOP dimension*

Because each zone controller decides independently ([Figure 20](#figure-20)), a closure is safe only if all three controllers switch norm sets before the picker enters. The project verifies the coordinator's protocol and the ability of the robots to drain zone 1.

**Normal operation:**

1. The fleet manager assigns a delivery, which creates an obligation with a deadline.
2. The robot requests entry from the controller of its next zone. It continues to occupy its current zone until entry is granted, because a robot cannot leave a zone instantaneously.
3. If the next zone is open and free, its controller admits the robot, which then releases the zone behind it.
4. After three denials, the robot parks in a side bay, releases its zone and abandons the delivery.
5. At the last zone, the robot leaves the corridor and reports completion. As an open-system agent, a robot may fail to report.
6. If the deadline passes without a report, the fleet manager sanctions the robot.

**Zone closure (regulation adaptation):**

1. **Detect.** The picker requests the closure.
2. **Design.** The regulation coordinator computes the next norm set: version + 1, with zone 1 closed.
3. **Execute.** The new norm set is installed in every zone controller, after which the picker is notified that entry is permitted.
4. Upon leaving, the picker requests the reverse adaptation, which reopens zone 1.

**Norms of the fleet:**

| Norm | Modality | Enforcement | Level | Monitors |
| --- | --- | --- | --- | --- |
| At most one robot per zone | prohibition | regimented by each zone controller | physical safety | S1 |
| No robot in a zone while a person is inside | prohibition | regimented by the zone controllers | physical safety | S1 |
| No admission under a norm set that has been superseded | prohibition on the regulator | regimented by the adaptation protocol | consistency of regulation | S2 |
| Norm sets are installed in version order | obligation on the regulator | by construction of the coordinator, monitored | consistency of regulation | S2 |
| A requested closure is eventually installed | obligation on the regulator | by the protocol, monitored | liveness of regulation | L2; R2 at run time |
| A person enters only after the closure is committed | obligation on the procedure | monitored | safety procedure | R3 |
| Report a delivery before its deadline | obligation with deadline | sanctioned by the fleet manager | performance | L1; R1 at run time |
| A delivery ends either fulfilled or sanctioned, never both | integrity of the organization | by construction, monitored | organizational | S3 |
| Sanction only an agent's own non-compliance | meta-norm on the sanction policy | monitored (approximation) | sanction fairness | F1 |

**Execution policies.** Two policies for executing a closure are compared ([Figure 21](#figure-21)):

- **Naive.** The coordinator declares the new norm set immediately, and each zone controller installs it upon receipt of the corresponding message.
- **Two-phase.** The coordinator sends *prepare*. Controllers whose zone is unaffected acknowledge immediately and continue to serve robots. The controller of the affected zone stops admitting robots, waits until the zone is empty and then acknowledges. The coordinator *commits* only after all controllers have acknowledged.

<a id="figure-21"></a>

![Figure 21 · naive vs. prepare–drain–commit zone closure, as message sequences](figures/figure21.svg)

*Figure 21 · naive vs. prepare–drain–commit zone closure, as message sequences*

In the naive sequence, the zone 1 controller still holds norm set v0 when the robot requests entry, because v1 is still in transit. The two-phase sequence cannot reach this state, since the picker is notified only after zone 1 has been drained and its controller has acknowledged.

The two central results expected from the project are a demonstration that the naive policy is unsafe and an analysis of the sanctions that even the safe policy applies to robots blocked by regulation or traffic.

**The two-phase protocol as state machines.** In the starter kit, the protocol is distributed over two P machines ([Figure 22](#figure-22)): the `AdaptationCoordinator` and one `ResourceGuard` per zone.

<a id="figure-22"></a>

![Figure 22 · the prepare–drain–commit protocol as two communicating state machines](figures/figure22.svg)

*Figure 22 · the prepare–drain–commit protocol as two communicating state machines*

- **Prepare.** The coordinator sends `eNormPrepare` to every zone controller. The controller of zone 1, which the new norm set closes, enters `Draining`: it denies new robots but permits the current occupant to leave. Zones 0 and 2 are unaffected and acknowledge immediately, so they continue to serve robots throughout.
- **Acknowledge.** When zone 1 is empty, its controller sends `eNormPrepareAck` and continues to deny requests, because it cannot yet determine whether the commit has occurred.
- **Commit.** Once all acknowledgements have been received, the coordinator announces `eNormCommitted`, which the monitors observe and which permits the picker to enter. It then sends `eNormCommit`, upon which each controller installs the new version.

The safety argument rests on the highlighted states. The figure also reveals the cost of the protocol: the coordinator remains in `Preparing` until zone 1 is empty, and in the corridor, emptying a zone is not always possible.

**Deadlock in the corridor.** A robot retains its zone until the next zone is granted. Consequently, two robots moving head-on may each hold the zone that the other requires ([Figure 23](#figure-23)). This configuration is a deadlock in the sense of operating systems: a circular wait among processes that hold resources.

<a id="figure-23"></a>

![Figure 23 · head-on robots form a wait-for cycle, and the Coffman condition each remedy removes](figures/figure23.svg)

*Figure 23 · head-on robots form a wait-for cycle, and the Coffman condition each remedy removes*

The cycle is relevant to regulation in two respects. First, it can block the closure: if robot 1 occupies zone 1 while waiting for zone 2, zone 1 is never drained and the adaptation never commits. Property L2 (`AdaptationCompletes`) detects this situation when parking is removed. Second, every resolution of the cycle has a normative cost:

- **Voluntary release (parking).** The robots of the starter kit abandon the task after three denials and park. This resolves the deadlock but leaves the task incomplete, and the robot is subsequently sanctioned for that obligation, which F1 flags as a potentially unfair sanction.
- **Preventing the cycle.** A traffic norm that admits only one direction of travel at a time renders the cycle impossible. It constitutes an additional regimented norm and reduces throughput.
- **Detection and recovery.** A supervisor detects the cycle and backs one robot out. This approach requires a free bay and introduces an additional component that must itself be verified.

**Coffman conditions.** A deadlock requires four conditions to hold simultaneously ([Coffman, Elphick and Shoshani](https://doi.org/10.1145/356586.356588)). Each remedy removes one of them:

| Condition | In the corridor | Remedy that removes it |
| --- | --- | --- |
| Mutual exclusion | a zone admits one robot (capacity 1) | none: it is the safety norm S1 |
| Hold and wait | a robot keeps its zone while it requests the next one | reservation of the whole route before departure |
| No preemption | a robot cannot be forced out of its zone | voluntary release after three denials (parking), or a supervisor that backs a robot out |
| Circular wait | head-on robots wait for each other's zone | a traffic norm that admits one direction at a time |

Parking thus removes the *no-preemption* condition through voluntary release; it does not remove hold-and-wait, because a robot holds its zone while it retries. Two risks remain even without deadlock. **Livelock** occurs if robots repeatedly park and re-enter in the same pattern without progress, and **starvation** occurs if one robot is always overtaken by another ([Section 5.10](#510-what-a-hot-state-violation-means)). Both affect L1 and the sanction counts rather than safety.

A comparison of these remedies with the checker, with respect to both the closure properties and the fairness property, is one of the experiments of the project ([Section 7.3](#73-experiments-priorities-in-75)).

## 7. Technical specification

The deliverable is a P project consisting of three parts:

- a model of the fleet;
- a catalog of monitors checked against this model;
- a PObserve package that checks the same monitors against logs.

A starter kit containing draft versions of all three parts is provided ([Section 9](#9-starter-kit-setup-and-references)). The work consists of bringing the kit to a compilable state, correcting it, justifying every modeling decision and extending it.

### 7.1 Model components

| P machine | Unified-view role | MAOP dimension | Responsibility |
| --- | --- | --- | --- |
| `Robot` (×2) | regulated agent | agent | requests the next zone, holds the current one, parks after 3 denials (announces `eTaskAbandoned`), reports or not (`$`) |
| `ResourceGuard` (×3) | regimentation | environment | one per zone; admits or denies by norm set and capacity; drains during prepare only if its zone changes |
| `ObligationManager` | sanctioning | organization | fleet manager: creates delivery obligations, checks deadlines on each tick, sanctions |
| `AdaptationCoordinator` | adaptation (detect → design → execute) | organization | versioned norm sets sent to all 3 controllers; two-phase or naive |
| `HumanRequester` | source of the detect-fact | environment (human) | the picker: requests the closure of zone 1, enters on commit, leaves, requests reopening |
| `Clock` | time | — | logical ticks; one final far-future tick so that every deadline passes; consequently, L1 holds whenever the obligation manager processes this tick ([Section 5.11](#511-vacuity-and-sanity-checks)) |

### 7.2 Property catalog

| Id | Monitor | Class | Enforcement | Checked by | Expected with prepare–drain–commit / naive |
| --- | --- | --- | --- | --- | --- |
| S1 | `RegimentationSafety`: never two robots in a zone; never a robot and a person together | safety | regimented | checker + PObserve | holds / **violated** |
| S2 | `NoStaleAdmission`: no admission to a zone the committed norm set closes; versions in order | safety | regimented (adaptation protocol) | checker + PObserve | holds / **violated** |
| S3 | `NoDoubleOutcome`: a delivery is never both fulfilled and sanctioned | safety (integrity) | by construction | checker + PObserve | holds / holds |
| L1 | `EveryObligationResolved`: every delivery eventually fulfilled or sanctioned | liveness (hot state) | sanctioned | checker | holds / holds, possibly vacuously ([Section 5.11](#511-vacuity-and-sanity-checks)) |
| L2 | `AdaptationCompletes`: every closure eventually commits | liveness (hot state) | protocol | checker | holds / holds, with parking |
| L3 | `AdaptationTerminates`: every adaptation eventually commits or is explicitly aborted | liveness (hot state) | protocol | checker | holds / holds; in E9, holds where L2 fails by design |
| R1 | `ObligationDeadlineRespected`: resolved by tick Due + 1 | bounded response | sanctioned | PObserve | holds / holds |
| R2 | `AdaptationBoundedTime`: commits within 5 ticks | bounded response | protocol | PObserve | holds if the bound is at least the maximum start-to-commit time, including protocol delay (at most 3 ticks in 500 simulator runs, an empirical value, not a bound) / holds |
| R3 | `LockoutBeforeEntry`: a person enters only a closed zone | safety (procedure) | monitored | checker + PObserve | holds / holds, by construction of the picker model ([Section 5.11](#511-vacuity-and-sanity-checks)) |
| F1 | `SanctionsReflectMisconduct`: no obligation is sanctioned after the robot abandoned it following repeated access denials | safety (approximation of sanction fairness) | monitored | checker + PObserve | **violated** / **violated** |

The expected outcomes are **hypotheses** derived from the design. They are consistent with the output of a sample-log simulator but have not yet been confirmed with `p check`; confirming or refuting them is part of the project. F1 is *expected* to fail, and its counterexample would constitute a finding about the kit's sanction policy rather than a defect of the monitor ([Section 3.9](#39-conditions-for-a-fair-sanction)); the refined monitor of phase 3 attributes each flagged sanction to a cause.

### 7.3 Experiments (priorities in 7.5)

| # | Experiment and change to the model | Question | Prediction | Acceptance criterion | Min. `-s` | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| E0 | Monitor sanity: one mutant per monitor ([Section 5.11](#511-vacuity-and-sanity-checks)) | Can each monitor fail? | each mutant violates its monitor | every monitor fails on its mutant; event coverage reported | 10,000 | mutants, traces, coverage table |
| E1 | Baseline, prepare–drain–commit: no change | Do S1–S3, L1–L3 and R3 hold? | no violation | no violation; N justified by calibration ([Section 5.9](#59-what-n-schedules-guarantee)) | 100,000 | command, seeds, versions, output |
| E2 | Baseline, naive: `twoPhase = false` | Which monitor fails first, and in which zone? | S1 or S2 in zone 1 | violation found and explained with the template of [Section 7.8](#78-reporting-a-counterexample) | 10,000 | trace and explanation |
| E3 | Sanction fairness: test `tcFleetSanctionFairness` | Which situations produce flagged sanctions? | F1 violated after closures and after head-on conflicts | each flagged trace attributed to a cause | 10,000 | traces for both causes, or an argument that one cannot occur |
| E4 | Block every controller during prepare: remove the "unaffected controller acks at once" branch | Does draining depend on parking? Does anything deadlock? | L2 holds only with parking | prediction confirmed or refuted with a trace | 10,000 | trace or run summary |
| E5 | No parking: robots retry forever | Does the corridor deadlock occur, and does L2 fail when zone 1 must drain? | L2 violated by circular wait | violation found and classified as genuine ([Section 5.10](#510-what-a-hot-state-violation-means)) | 10,000 | trace and classification |
| E6 | Traffic norm (remedy 1): one travel direction at a time | Do flagged sanctions then follow only closures? | traffic-caused cases disappear | refined monitor reports no traffic-caused case; all safety monitors hold | 10,000 | refined-monitor output; safety results |
| E7 | Excusing obligations (remedy 2): deadlines suspended while the regulation blocks a robot, and obligations abandoned because of a closure excused | Does F1 hold for regulation-caused cases, and at what cost? | suspension alone: F1 still fails; with excusal: no regulation-caused case | refined monitor reports no regulation-caused case; safety monitors and L1 hold | 10,000 | outputs before and after; cost in L1 (checker) and in sanction counts (PObserve) |
| E8 | Scale: 3–4 robots or 4–5 zones | Where does exploration stop scaling? | run time grows rapidly | run times reported per size | as feasible | table of sizes and times |
| E9 | Prepare timeout and abort: the coordinator aborts if the zone does not drain within k ticks | Does every adaptation terminate without parking (L3), and are S1 and S2 preserved? | L3 holds; L2 fails by design for an aborted change, which is not installed (it remains in its hot state or, if the change is retried, reports a new start before the previous commit); S1 and S2 preserved; the picker is refused | prediction confirmed or refuted; acceptance cases: a timeout followed by `ADAPT_ABORT` satisfies L3; a prepare that is neither committed nor aborted violates L3; an aborted prepare never admits the picker and leaves no controller blocked | 10,000 | traces and discussion |

Predictions are recorded before each run. The identifiers E0–E9 are also used in the assignment and in the instructions.

**Stretch goal: refinement (research question 3).** An abstract centralized regulator is specified as a single machine holding the state of the entire corridor. It is then shown, either by refinement testing or by means of P's module system, that the three distributed controllers together with the coordinator behave as this regulator. Such a result would turn the architectural-style axis of the unified view into a verified claim.

### 7.4 Run-time part (PObserve)

**Log contract.** Each regulation event is recorded as one log line:

- `Site=fleet-A, Event=ENTER, Agent=1, Res=1, Ver=0`;
- in addition, `CONFIG` (all zones: `Capacity=0:1;1:1;2:1`), `TICK`, `OBLIGATION`, `FULFILLED`, `SANCTION`, `LEAVE`, `ADAPT_START`, `COMMIT`, `HUMAN_ENTER` and `HUMAN_LEAVE`; in experiment E9 only, `ADAPT_ABORT` (`Ver`), which the parser maps to eAdaptationAborted;
- `ABANDON` (`Id, Agent, Where`), emitted by a robot when it abandons its task.

Each line is prefixed with a UTC timestamp of microsecond precision. `Site` serves as the partition key.

**Package.** A Gradle project that runs `p compile --mode pobserve` on the monitors only, together with a Java parser, JUnit tests (for safety and fairness) and a script that invokes the command-line interface.

**Validation criteria:**

- the prepare–drain–commit sample log satisfies every safety monitor;
- the naive sample log violates S1 and S2;
- both logs violate F1;
- **injected system faults** (true positives): the simulator or the model is mutated so that the fleet manager does not apply a due sanction while ticks continue to be recorded, which R1 detects, and the coordinator is delayed so that `COMMIT` is late, which R2 detects. Deleting an existing `SANCTION` line from a log afterwards is a log defect, not a system fault: it may produce the same R1 verdict, but the ground truth differs, because the sanction was applied. Both the original and the modified log are kept, and the difference is explained;
- **injected log defects** (false results): at least two defects from `MobileRobots/INSTRUCTIONS.md`, section 3.6, such as a missing `LEAVE` or a duplicate `COMMIT`, are injected, and the resulting false verdicts are explained.

**Instrumentation (stretch goal).** The log is emitted from a ROS 2 simulation of the corridor (e.g., three zones in Gazebo or in a 2D simulator) using the `regulation_log.py` helper. The output is written to a dedicated file rather than through the ROS logger, whose prefix the parser does not accept. PObserve is then run on the resulting log.

### 7.5 Requirements

| Priority | Requirement |
| --- | --- |
| Must | All P files compile; E0–E3 run; each result is explained with the trace or report |
| Must | Every monitor is traced to a norm of [Section 6](#6-the-system-robots-in-a-shared-corridor) ([Section 7.7](#77-traceability)) and shown to be able to fail (E0) |
| Must | Predictions are recorded before each experiment, and the validation record is complete |
| Must | Denial causes are recorded, the refined monitor distinguishes regulation-caused from traffic-caused cases, and one remedy (E6 or E7) is verified |
| Must | The PObserve package builds; the safety and fairness JUnit tests pass on the sample logs |
| Must | The report states the modeling assumptions and the threats to validity ([Section 7.6](#76-modeling-assumptions-and-threats-to-validity)) |
| Should | E4 and E5; the fault-injection runs of [Section 7.4](#74-run-time-part-pobserve); an order-insensitive refinement of F1 |
| Could | E8 and E9; the second remedy; the refinement stretch goal; ROS 2 instrumentation and a run on its logs |

### 7.6 Modeling assumptions and threats to validity

Every result of the project holds relative to the model and to the logs. The following assumptions are recorded, and the report discusses each as a potential threat to validity. An *over-approximation* admits more behaviors than the real fleet, so that safety results transfer to the real fleet; an *under-approximation* admits fewer, so that safety results do not transfer without further argument.

| Model assumption | Real-fleet counterpart | Approximation | Properties affected |
| --- | --- | --- | --- |
| Robots follow the access protocol: they request before entering and never enter without a grant | robots may malfunction or be teleoperated into a zone | under-approximation | S1, S2 |
| Robots may fail to report (`$`) | robots may crash or lose connectivity | over-approximation of reporting failures | L1, R1, S3 |
| Messages are neither lost nor duplicated | networks lose and duplicate messages | under-approximation | S2, L2 |
| Messages between two machines arrive in order; different senders interleave arbitrarily | ROS 2 topics with suitable QoS; arbitrary delays | over-approximation of delays | S1, S2 |
| Zone moves are discrete; a robot holds its zone until the next is granted | continuous motion; a robot occupies two zones while crossing a boundary | abstraction | S1, deadlock |
| The picker waits for the commit before entering | people may enter without permission | under-approximation | R3, S1 |
| Light curtains and badge readers detect every person | sensors fail | under-approximation | S1, R3 |
| Logical ticks; deadlines in ticks | physical time and clock drift | abstraction | L1, R1, R2 |
| The coordinator, the fleet manager and the clock never fail | single points of failure | under-approximation | L1, L2, R2 |
| Two robots, three zones, bounded retries and ticks | larger fleets, unbounded operation | under-approximation (small scope) | all |

The report groups threats to validity into four classes: *internal* (errors in the model or the monitors; addressed by E0), *construct* (whether a monitor expresses the intended norm, in particular F1, [Section 3.9](#39-conditions-for-a-fair-sanction)), *external* (whether the results transfer to real fleets; the table above) and *conclusion* (whether the number of schedules suffices; [Section 5.9](#59-what-n-schedules-guarantee)).

### 7.7 Traceability

The following table traces each norm of [Section 6](#6-the-system-robots-in-a-shared-corridor) to the property that expresses it and to the evidence that checks it.

| Norm ([Section 6](#6-the-system-robots-in-a-shared-corridor)) | Property | Formula (informal) | Class | Enforcement | Design time | Run time | Test case | Log events |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| One robot per zone; no robot with a person | S1 | G ¬(occupancy > capacity ∨ (robot ∧ person in the same zone)) | safety | regimented | checker | PObserve | `tcFleetTwoPhase`, `tcFleetNaive` | CONFIG, ENTER, LEAVE, HUMAN\_ENTER, HUMAN\_LEAVE |
| No admission to a zone that the committed norm set closes; versions in order | S2 | G(admitted(z) → z not closed by the last committed norm set) ∧ commits in version order | safety | regimented | checker | PObserve | `tcFleetNaive` | ENTER, COMMIT |
| Fulfilled or sanctioned, never both | S3 | G ¬(fulfilled(o) ∧ sanctioned(o)) | safety | by construction | checker | PObserve | all | FULFILLED, SANCTION |
| Report before the deadline | L1, R1 | G(created → F resolved); G(created → F≤(Due+1) resolved) | liveness; bounded response | sanctioned | L1 | R1 | all | OBLIGATION, FULFILLED, SANCTION, TICK |
| A requested closure is eventually installed | L2, R2 | G(started → F committed); within 5 ticks | liveness; bounded response | protocol | L2 | R2 | `tcFleetTwoPhase` | ADAPT\_START, COMMIT, TICK |
| A requested closure is eventually committed or explicitly aborted | L3 | G(started → F(committed ∨ aborted)) | liveness | protocol | L3 | — | `tcFleetTwoPhase`; E9 variant | ADAPT\_START, COMMIT, ADAPT\_ABORT |
| A person enters only after the commit | R3 | G(person enters z → z closed by the committed norm set) | safety | monitored | checker | PObserve | `tcFleetTwoPhase` | HUMAN\_ENTER, COMMIT |
| Sanction only own non-compliance | F1 | G ¬(sanctioned(o) ∧ o abandoned earlier) | safety (approximation) | monitored | checker | PObserve | `tcFleetSanctionFairness` | ABANDON, SANCTION |

**Event vocabulary.**

| P event | Log event | Fields | Observed by |
| --- | --- | --- | --- |
| `eMonitorConfig` | CONFIG | Capacity | S1 |
| `eTick` | TICK | Now | R1, R2 |
| `eObligationCreated` | OBLIGATION | Id, Agent, Task, Due | L1, R1 |
| `eObligationFulfilled` | FULFILLED | Id, Agent | S3, L1, R1 |
| `eSanctionApplied` | SANCTION | Id, Agent | S3, L1, R1, F1 |
| `eResourceEntered` | ENTER | Agent, Res, Ver | S1, S2 |
| `eResourceLeft` | LEAVE | Agent, Res | S1 |
| `eAdaptationStarted` | ADAPT\_START | Ver | L2, L3, R2 |
| `eNormCommitted` | COMMIT | Ver, Closed | S2, L2, L3, R2, R3 |
| `eAdaptationAborted` | ADAPT\_ABORT | Ver | L3 (E9 only) |
| `eHumanEntered`, `eHumanLeft` | HUMAN\_ENTER, HUMAN\_LEAVE | Res | S1; R3 (entry only) |
| `eTaskAbandoned` | ABANDON | Id, Agent, Where | F1 |

### 7.8 Reporting a counterexample

Each counterexample in the report follows this template:

1. **Setup.** Test case, configuration (robots, zones, protocol), command, seed, strategy and P version.
2. **Violated property.** Monitor, assertion message and the norm of [Section 6](#6-the-system-robots-in-a-shared-corridor) that it expresses.
3. **Shortest violating prefix.** Only the relevant events, as a message-sequence chart or a numbered list; events of unrelated machines are omitted, and the omission is stated.
4. **Root cause.** The interleaving or design decision that permits the violation, related to a hazard of [Section 4.5](#45-consistency-during-a-regulation-change) or to a figure of [Section 6](#6-the-system-robots-in-a-shared-corridor).
5. **Real defect or model artifact.** An argument, with reference to the assumptions of [Section 7.6](#76-modeling-assumptions-and-threats-to-validity), whether the trace can occur in a real fleet.
6. **Fix.** The change to the model, with its justification.
7. **Regression.** The run that shows that the fix removes the violation and that no other monitor fails.

**Annotated log excerpt.** The following excerpt of the naive sample log `fleet_naive.log` is illustrative: it was produced by the simulator, not by a running fleet, and its timestamps are shortened. It shows the violation of S1 and S2 at tick 3:

```
08:00:03.001  TICK         Now=3
08:00:03.002  ADAPT_START  Ver=1                  <- the picker requests the closure of zone 1
08:00:03.003  COMMIT       Ver=1, Closed=1        <- naive: committed before any controller installed v1
08:00:03.004  HUMAN_ENTER  Res=1                  <- the picker enters on the commit
08:00:03.005  ENTER        Agent=1, Res=1, Ver=0  <- zone 1 still applies v0: S2 (stale admission), S1 (robot with person)
08:00:03.006  LEAVE        Agent=1, Res=0
```

A complete write-up adds the setup (here, simulator seed 2 and the naive policy) and relates the violation to hazards 1 and 2 of [Section 4.5](#45-consistency-during-a-regulation-change). The same template applies to F1: later in the same log, obligation 0 of robot 2 is abandoned at tick 5 (`ABANDON Id=0, Agent=2, Where=2`) and sanctioned at tick 8 (`SANCTION Id=0, Agent=2`), one tick after its deadline of 7.

## 8. Work plan and deliverables

The project comprises five phases over 45 calendar days, counted from the start date ([Figure 24](#figure-24)). Each phase lasts between 7 and 11 days and concludes with a short checkpoint meeting and a tagged commit.

<a id="figure-24"></a>

![Figure 24 · work plan: 5 phases, 45 days, 5 deliverables](figures/figure24.svg)

*Figure 24 · work plan: 5 phases, 45 days, 5 deliverables*

The verification phase constitutes the core of the project. If the modeling work is delayed, the optional ROS 2 instrumentation and the refinement stretch goal are to be omitted, not experiments E1–E3.

**Deliverables:**

| Phase | Days | Activities | Deliverable or checkpoint | Exit criterion |
| --- | --- | --- | --- | --- |
| 1 Background | 1–7 | toolchain; `P-Tutorial`; [Sections 2](#2-background-multi-agent-systems)–5; first `p compile`, with the errors recorded | **D1** (day 7): background note, 2–3 pages, with the fleet placed in the unified-view grid and a one-page mapping of each machine to a regulation capability, stating which responsibilities are distributed and which centralized | note submitted; toolchain versions recorded; toolchain preflight passed: the PObserve Java package builds with a Gradle wrapper pinned in the repository, and its JUnit tests run once on the sample logs |
| 2 Model | 8–17 | compile errors fixed; modeling decisions justified; E0–E2 and at least three of E3–E5 and E9, each with a prediction recorded before the run | **Checkpoint** (day 17): validation record for the P steps; experiment log with change, prediction, result and explanation | project compiles; E0 shows that every monitor can fail; E1 and E2 recorded |
| 3 Verification | 18–28 | analysis (days 18–22): denial causes recorded in `eTaskAbandoned`, refined cause-aware monitor; remedy (days 23–28): E6 or E7 | **D2** (day 28): verified model with the refined monitor, counterexample traces for both causes (or an argument that one cannot occur), all safety monitors still holding, the result of the remedy and the justification of the schedule count ([Section 5.9](#59-what-n-schedules-guarantee)) | the Must requirements of [Section 7.5](#75-requirements) that concern the model are met |
| 4 Run time | 29–38 | PObserve package; logs with denial causes and remedy from the extended simulator; sanction counts by cause before and after the remedy; injection of system faults and log defects ([Section 7.4](#74-run-time-part-pobserve)) | **D3** (day 38): PObserve package, verdicts for every log, counts of flagged sanctions by cause before and after the remedy | JUnit tests pass on the sample logs; every log has a recorded verdict |
| 5 Analysis | 39–45 | article draft and presentation | **D4** (day 45): scientific article draft prepared by each team (complete and internally consistent, though not yet ready for submission), 8–12 pages in a workshop-paper format (e.g., EMAS, COINE or WESAAC), with title, authors, abstract, keywords and references, and with the threats to validity ([Section 7.6](#76-modeling-assumptions-and-threats-to-validity)) and the validation record as an appendix. **D5** (day 45): presentation of 15 minutes plus 5 minutes of questions, with one counterexample replayed live and one PObserve result shown | article draft and presentation delivered |

This table is the authoritative statement of phases and deliverables; `ASSIGNMENT.md` reproduces it. D1 and the day-17 checkpoint are formative: they receive written feedback, and their content is assessed as part of the report.

**Assessment rubric.**

| Component | Weight | Excellent | Adequate | Insufficient |
| --- | --- | --- | --- | --- |
| Baseline and validation record | 10% | every step has command, versions, seed and output, and is reproducible from the repository | most steps recorded, with minor gaps | results without commands or output |
| Design experiments (E0–E5, E9) | 15% | predictions recorded before running; every counterexample explained with the template of [Section 7.8](#78-reporting-a-counterexample); mutants for all monitors | predictions for most experiments; counterexamples described | results reported without prediction or explanation |
| Sanction fairness: analysis and refined monitor | 20% | causes recorded and distinguished; traces for each cause explained; order sensitivity addressed | causes distinguished; traces partially explained | no attribution of causes |
| Sanction fairness: remedy and verification | 20% | remedy verified for the targeted cases; safety monitors still hold; schedule count justified by calibration | remedy implemented and checked; justification of the schedule count incomplete | remedy not verified |
| Run-time monitoring | 15% | verdicts for all logs; counts by cause before and after the remedy; system faults and log defects analyzed; clock skew discussed | verdicts and counts; defects partially analyzed | package does not run, or no analysis |
| Article draft and presentation | 20% | claims match the evidence; no causal claim beyond what the monitors support; threats to validity complete | minor overstatements; threats partially discussed | claims unsupported by evidence |

**Learning outcomes, deliverables and assessment.**

| Outcome | D1 | Day 17 | D2 | D3 | D4 | D5 | Assessed in |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LO1 grid and architecture | ✓ |  |  |  | ✓ |  | article draft and presentation |
| LO2 modeling and assumptions |  | ✓ | ✓ |  | ✓ |  | baseline; design experiments |
| LO3 monitors and counterexamples |  | ✓ | ✓ | ✓ | ✓ | ✓ | design experiments; fairness analysis |
| LO4 schedules and vacuity |  | ✓ | ✓ |  | ✓ |  | design experiments; remedy |
| LO5 causes and remedy |  |  | ✓ | ✓ | ✓ | ✓ | fairness analysis; remedy |
| LO6 run-time monitoring |  |  |  | ✓ | ✓ | ✓ | run-time monitoring |
| LO7 physical constraints and validity | ✓ |  | ✓ | ✓ | ✓ |  | article draft and presentation |

**Guidelines for carrying out the project.** The following practices are expected throughout the project; the rubric above rewards several of them directly.

1. **Set up the toolchain first.** In the first week, install the toolchain, compile the starter kit, run one checker test and build the PObserve package once, recording every tool version. A problem found on day 3 is cheap; one found on day 30 is not.
2. **Read in order.** Follow the reading map of [Appendix A](#appendix-a-glossary-and-reading-map) and work through the P tutorial before modifying the model.
3. **Change one thing at a time.** After each change, compile, run the relevant test and record the result before making the next change.
4. **Predict before running.** Write the expected outcome of every experiment, and the reason for it, before running it; a prediction recorded afterwards is not a prediction.
5. **Keep the validation record current.** For every run, record the command, tool versions, seed or schedule count and the actual output in section 5 of [INSTRUCTIONS.md](https://github.com/perkusic/P-Language/blob/main/Projects/ProjectRobot2026/MobileRobots/INSTRUCTIONS.md).
6. **Never weaken a monitor to make a check pass.** If a monitor appears to be wrong, document and justify the change, and show with a mutant that every monitor can still fail ([Section 5.11](#511-vacuity-and-sanity-checks)).
7. **Report what a check establishes.** "No bug found" holds only for the schedules explored; state their number and justify it ([Section 5.9](#59-what-n-schedules-guarantee)). Keep model results, checker results and PObserve results distinct, and state the assumptions on which each claim rests ([Section 7.6](#76-modeling-assumptions-and-threats-to-validity)).
8. **Explain a counterexample before fixing it.** Write it up with the template of [Section 7.8](#78-reporting-a-counterexample), then correct the design, then re-run the experiment that exposed it.
9. **Commit often and tag each checkpoint.** Commit at least once per working day and tag each checkpoint (`d1` to `d5`); keep generated folders (`PGenerated`, `PCheckerOutput`) out of version control, except the traces cited as evidence.
10. **Organize the team explicitly.** Assign an owner to each experiment, have another member review each trace and write-up, and record each member's contribution.
11. **Escalate early and prioritize.** A tooling problem that blocks progress for more than a day is raised at the next checkpoint or with the instructor. When time is short, optional work is dropped before required work ([Section 7.5](#75-requirements)).

## 9. Starter kit, setup and references

The `p-regulation` starter kit is given in the project folder of the repository; it was originally distributed as an archive. The folders `Common/`, `MobileRobots/` and `tools/` are used; `ManufacturingCell/` contains a simpler, centralized variant that serves as a reference.

| Path | Content | Status |
| --- | --- | --- |
| `Common/*.p` | shared model machines and monitors | compiles with P 3.1.0.0, without warnings (21 October 2026); later changes (the L3 monitor and the S1, L2 and R2 corrections) are not yet compiled |
| `MobileRobots/PSrc`, `PSpec`, `PTst` | robots, system configuration, fairness monitor, test cases | compiles with P 3.1.0.0 (21 October 2026); the three test cases run as expected (see below) |
| `MobileRobots/pobserve/` | Gradle build, parser, JUnit tests, sample logs | parser written against the PObserve API; Java classes generated with `p compile --mode pobserve`; Java build, JUnit and PObserve replay not yet run |
| `MobileRobots/INSTRUCTIONS.md` | step-by-step commands for both parts | P steps run in the independent evaluation; Java and PObserve steps not yet validated |
| `tools/simulate_logs.py` | generates two-phase / naive fleet logs and previews monitor results | tested |
| `tools/instrumentation/regulation_log.py` | logging helper for ROS 2 / Python | tested |

**Independent evaluation, 21 October 2026** (P 3.1.0.0, .NET SDK 8.0.426, OpenJDK 17.0.20.8). `p compile` succeeds without warnings. `tcFleetNaive` violates S2 on the first schedule (robot 2 is admitted under v0 to zone 1, which v1 closes). `tcFleetSanctionFairness` violates F1 on the first schedule, as intended. `tcFleetTwoPhase` reports no bug in 3,442 schedules within a 30-second run; this is not the 100,000-schedule acceptance run of experiment E1. `p compile --mode pobserve` generates the Java classes; the Java build, the JUnit tests and the PObserve replay have not yet been run, because neither Gradle nor Maven was installed and no wrapper is committed. Evidence: [reviews/evaluation-2026-10-21](https://github.com/perkusic/P-Language/tree/main/reviews/evaluation-2026-10-21).

**Required environment:**

- .NET SDK 8.0, followed by `dotnet tool install --global P`;
- Java 17 or later;
- Gradle 8.x, through a Gradle wrapper pinned in the repository (committed in week 1; the independent evaluation found neither Gradle nor Maven installed and no wrapper);
- Python 3;
- optionally, ROS 2 for the instrumentation stretch goal.

Alternatively, the Docker image `ghcr.io/p-org/p:latest` provides .NET, a JDK and the `p` command-line tool. The PObserve command-line interface is built once from the P repository (`Src/PObserve/PObserve`, `./gradlew build`).

**Getting started:**

```
cd MobileRobots
p compile
p check -tc tcFleetNaive -s 10000
p check -tc tcFleetSanctionFairness -s 10000
cd pobserve && gradle wrapper && ./gradlew build uberjar && ./run_pobserve.sh
```

**Self-check questions (the model and its limits).**

1. Why is `Clock` a P machine but not a domain agent? *Answer sketch:* It models infrastructure, namely logical time; it has no goals and makes no decisions on behalf of a participant.
2. Can two robots still form a multi-agent system when one organization assigns their tasks? *Answer sketch:* Yes. A multi-agent system may contain centralized services; autonomy concerns how agents pursue their tasks, not who assigns them.
3. Does `$` in `Robot` mean that the agent implements a BDI interpreter? *Answer sketch:* No. `$` is a nondeterministic choice that lets the checker explore both outcomes; it abstracts a decision rather than implementing reasoning.
4. Can an agent be permitted to enter a resource and still be unable to enter it now? *Answer sketch:* Yes. An open resource may be occupied. Normative permission, physical or protocol feasibility, and an eventual-service guarantee are different properties.
5. Who blocks an entry: `ResourceGuard` or the P monitor? *Answer sketch:* `ResourceGuard`. The monitor only observes the events and reports a violation.
6. Does a sanctioned delivery count as completed? What does L1 actually establish? *Answer sketch:* No. L1 establishes that every obligation is resolved, by fulfillment or by sanction; a sanction resolves the record but is not success.
7. Does observing a denial before a missed deadline prove that the denial caused it? *Answer sketch:* No. A denial can follow from a closure or from occupancy by the other robot, and it need not have caused the miss; F1 flags candidates only.
8. Which norm data can the starter coordinator change, and which remain fixed? *Answer sketch:* Only the set of closed resources and the version number; deadlines, sanctions and roles are fixed.
9. Which lifecycle transitions and enforcement effects are proposed extensions rather than baseline behavior? *Answer sketch:* The inactivation of an obligation, concrete sanction effects such as priority reductions or fines, and role checks on adaptation requests.

## Appendix A. Glossary and reading map

**Glossary.**

| Term | Meaning in this project |
| --- | --- |
| Abandonment | a robot gives up a delivery after three denials and parks; announced as `eTaskAbandoned` |
| Adaptation | a run-time change of the norm set, executed by the coordinator (detect, design, execute) |
| Announce | a P statement that delivers an event to monitors only |
| Bounded response | a property such as G(p → F≤k q); a safety property that can be checked on finite logs |
| Cold / hot state | a monitor state in which an execution may / must not end or remain forever |
| Constitutive rule | a count-as rule that relates physical facts to institutional facts |
| Counterexample | a trace that violates a monitor, together with the seed that reproduces it |
| Deadlock | a state in which robots wait for each other indefinitely; requires the four Coffman conditions |
| Denial | the refusal of an access request by a zone controller |
| Detect-fact | the institutional fact that a change of regulation is required |
| Drain | waiting until the zone to be closed is empty |
| Fairness assumption | an assumption about the scheduler (weak or strong fairness) under which liveness is judged |
| Livelock | repeated activity without progress |
| Liveness property | a property stating that something good eventually happens; it cannot be violated on a finite prefix |
| Monitor (spec) | a P machine that observes events and asserts a property |
| Mutant | a deliberately faulty variant of the model, used to show that a monitor can fail |
| Norm instance | one activation of a norm, e.g., the obligation for one delivery |
| Norm set (version) | the set of closed zones in force, numbered by a version |
| Partition key | the log field by which PObserve groups events into independent monitor instances (here, `Site`) |
| Regimentation | enforcement that makes a violation impossible |
| Safety property | a property stating that nothing bad happens; every violation has a finite bad prefix |
| Sanction fairness | the requirement that a robot is sanctioned only for non-compliance it could have avoided |
| Sanctioning | enforcement that detects a violation and responds with a sanction |
| Schedule | one execution explored by the checker, with all scheduling and `$` choices resolved |
| Tick | one step of the organization's logical clock |
| Transition window | the interval during which regulators may apply different norm sets |
| Vacuity | satisfaction of a property for a trivial reason, which therefore carries no information |

**Reading map.** Essential subsections are required for the phase indicated; enrichment subsections deepen the background and may be read later.

| Section | Status | Needed in phase |
| --- | --- | --- |
| 2, 2.2, 2.4 | essential | 1 |
| 2.1, 2.3, 2.5 | enrichment | 1 |
| 3, 3.1, 3.3, 3.4, 3.7, 3.9 | essential | 1–3 |
| 3.2: deontic and temporal readings, norm patterns | essential | 1 |
| 3.2: Andersonian reduction, paradoxes; 3.5, 3.6, 3.8 | enrichment | 1 |
| 4, 4.5, 4.6 | essential | 1–2 |
| 4.1–4.4 | enrichment | 1 |
| 5, 5.1–5.6, 5.9–5.11 | essential | 2 |
| 5.7, 5.8, 5.12 | essential for the run-time part | 4 |
| 5.13 | essential | 2–5 |
| 6, 7, 8 | essential | 2–5 |

## References

Core:

- E. Yan, L. G. Nardin, O. Boissier, J. S. Sichman. *A Unified View on Regulation Management in Multi-Agent Systems.* COINE workshop, 2025. [HAL](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1)
- E. Yan, L. G. Nardin, O. Boissier, J. S. Sichman. *A Regulation Adaptation Model for Multi-Agent Systems.* ECAI 2025, doi:10.3233/FAIA251245. [HAL](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1)
- E. Yan, L. G. Nardin, J. F. Hübner, O. Boissier, J. S. Sichman. *Perspectives on Regulation Adaptation in Multi-Agent Systems.* WESAAC 2025, doi:10.5753/wesaac.2025.37527. [SOL](https://sol.sbc.org.br/index.php/wesaac/article/view/37527)
- A. Desai et al. *P: Safe Asynchronous Event-Driven Programming.* PLDI 2013. [Microsoft Research](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/)
- A. Desai. *Modular and Safe Event-Driven Programming.* PhD thesis, UC Berkeley, 2020 (ModP, Drona). [PDF](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2020/EECS-2020-3.pdf)
- P language documentation and PObserve guides. [p-org.github.io/P](https://p-org.github.io/P/)
- M. Brooker, A. Desai. *Systems Correctness Practices at AWS.* ACM Queue / CACM. [ACM Queue](https://queue.acm.org/detail.cfm?id=3712057)

P in robotics:

- A. Desai et al. *SOTER: A Runtime Assurance Framework for Programming Safe Robotics Systems.* DSN 2019. [arXiv](https://arxiv.org/pdf/1808.07921)
- S. Shivakumar et al. *SOTER on ROS: A Run-Time Assurance Framework on the Robot Operating System.* RV 2020, doi:10.1007/978-3-030-60508-7\_10. [eScholarship](https://escholarship.org/uc/item/5r78g42p)

Norms and verification:

- N. Alechina, N. Bulling, M. Dastani, B. Logan. *Practical run-time norm enforcement with bounded lookahead.* AAMAS 2015. [repository](https://nottingham-repository.worktribe.com/output/752739)
- L. Dennis et al. *Model Checking Normative Agent Organisations.* [PDF](https://personalpages.manchester.ac.uk/staff/louise.dennis/pubs/climaX.pdf)
- L. Gasparini et al. *CÒIR: Verifying normative specifications of complex systems.* COIN 2015, LNCS 9628. [record](https://abdn.elsevierpure.com/en/publications/c%C3%B2ir-verifying-normative-specifications-of-complex-systems)
- M. Dastani, S. Sardina, V. Yazdanpanah. *Norm Enforcement as Supervisory Control.* PRIMA 2017. [record](https://research.utwente.nl/en/publications/norm-enforcement-as-supervisory-control/)
- D. Dell'Anna, M. Dastani, F. Dalpiaz. *Runtime Revision of Sanctions in Normative MAS.* JAAMAS 34(2), 2020. [PDF](https://webspace.science.uu.nl/~dalpi001/papers/dell-dast-dalp-20-jaamas.pdf)
- *Norm specification and verification in multi-agent systems* (survey). IfCoLoG J. Logics and their Applications 5(2), 2018. [record](https://research.ou.nl/en/publications/norm-specification-and-verification-in-multi-agent-systems/)

Deontic and temporal logic:

- A. R. Anderson. [A reduction of deontic logic to alethic modal logic](https://doi.org/10.1093/mind/LXVII.265.100). *Mind* 67(265):100–103, 1958.
- J.-J. Ch. Meyer. [A different approach to deontic logic: deontic logic viewed as a variant of dynamic logic](https://doi.org/10.1305/ndjfl/1093637776). *Notre Dame Journal of Formal Logic* 29(1):109–136, 1988.
- P. McNamara and F. Van De Putte. [Deontic logic](https://plato.stanford.edu/entries/logic-deontic/). *Stanford Encyclopedia of Philosophy*.

Concurrency, testing and run-time verification:

- E. G. Coffman, M. J. Elphick, A. Shoshani. [System deadlocks](https://doi.org/10.1145/356586.356588). *ACM Computing Surveys* 3(2):67–78, 1971.
- J. Kramer, J. Magee. [The evolving philosophers problem: dynamic change management](https://doi.org/10.1109/32.60317). *IEEE Transactions on Software Engineering* 16(11):1293–1306, 1990.
- S. Burckhardt, P. Kothari, M. Musuvathi, S. Nagarakatte. [A randomized scheduler with probabilistic guarantees of finding bugs](https://doi.org/10.1145/1736020.1736040). ASPLOS 2010.
- A. Bauer, M. Leucker, C. Schallhart. [Runtime verification for LTL and TLTL](https://doi.org/10.1145/2000799.2000800). *ACM Transactions on Software Engineering and Methodology* 20(4), 2011.

Textbooks and background (from the field's standard literature; locate the current editions):

- M. Wooldridge. *An Introduction to MultiAgent Systems.* Wiley, 2nd ed. 2009.
- O. Boissier, R. H. Bordini, J. F. Hübner, A. Ricci. *Multi-Agent Oriented Programming: Programming Multi-Agent Systems Using JaCaMo.* MIT Press, 2020.
- G. Boella, L. van der Torre, H. Verhagen. *Introduction to normative multiagent systems.* Computational & Mathematical Organization Theory, 2006.
