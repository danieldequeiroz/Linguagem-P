# Verified Regulation Management for a Mobile Robot Fleet (P + PObserve)

Graduate project specification · Oct 20, 2026 · Angelo

## 1. Summary

The student builds and verifies the regulation layer of a small fleet of mobile robots that share a narrow corridor with people, in two steps:

1. Model the layer in the P language and model-check it.
2. Check fleet logs (simulated, or from a ROS 2 system) against the same P monitors with PObserve.

The project turns one cell of the conceptual grid of [Yan, Nardin, Boissier & Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) (*A Unified View on Regulation Management in Multi-Agent Systems*, COINE 2025) into a system whose properties can be checked. The grid crosses three perspectives: regulation capabilities, programming dimensions and architectural style. The cell in question is **hybrid (environment + organization + agent), distributed**. Each corridor zone has its own controller, and the controllers coordinate only through messages.

**Research questions:**

1. Does a distributed regulation layer keep its safety guarantees while a zone is closed for a person? Which adaptation protocol is needed?
2. When regulation and physical traffic block robots, does the sanctioning system still punish only real misconduct?
3. (Stretch) Can the distributed design be shown to behave like a simple centralized regulator?

**Expected results:**

- **Safety.** A naive adaptation ("declare the closure, let each zone controller install it later") admits a robot into a zone that is already closed and may hold a person. A two-phase adaptation (prepare, drain, commit) does not.
- **Fairness.** Even with the safe protocol, robots blocked by the closure or by a head-on conflict are sanctioned for missing their deadlines. This is a design gap in the norms, not misconduct by the robots, and the project must expose it and evaluate a remedy.

**Learning outcomes.** On completion the student can:

- explain multi-agent systems, normative MAS and regulation management, and place a design in the unified-view grid;
- formalize distributed regulation, obligations, sanctions and adaptation as communicating state machines in P;
- write safety, liveness and fairness specifications as P monitors and interpret counterexamples;
- compile the monitors for PObserve, write a log parser, and check fleet logs;
- reason about how physical constraints (a robot cannot vanish from a zone) interact with norms.

## 2. Background: multi-agent systems

A multi-agent system (MAS) is a set of autonomous agents that share an environment and interact to reach individual or collective goals. Each agent decides for itself, so the system's global behaviour is not programmed directly. That is why it needs regulation.

**Agents.** Following [Wooldridge](#references), an agent is a software or physical entity with four properties:

- **autonomy**: acts without direct intervention
- **reactivity**: responds to changes in its environment
- **pro-activeness**: pursues its own goals
- **social ability**: communicates with other agents

Most MAS platforms use the BDI model: agents reason over *beliefs*, *desires* (goals) and *intentions* (committed plans). The language Jason (AgentSpeak) is an example.

**Multi-Agent Oriented Programming (MAOP).** [Boissier et al.](#references) split a MAS into four programming dimensions, each with its own abstractions. JaCaMo combines one technology per dimension. In a robot fleet these map onto familiar robotics components:

| Dimension | First-class abstractions | JaCaMo technology | Role in this project | Typical robotics counterpart |
| --- | --- | --- | --- | --- |
| Agent | beliefs, goals, plans | Jason | each mobile robot's task logic | robot task node |
| Environment | artifacts with operations and observable properties | CArtAgO | one controller per corridor zone, admitting robots | zone / traffic controller node |
| Interaction | protocols, messages | Jason speech acts | request / grant / deny / release; prepare / ack / commit | ROS 2 topics and services |
| Organization | roles, groups, missions, norms | Moise + NPL | delivery obligations, deadlines, sanctions, zone closures | fleet manager |

![Figure 1 · MAOP dimensions and JaCaMo technologies, with the fleet's components](figures/figure1.png)

*Figure 1 · MAOP dimensions and JaCaMo technologies, with the fleet's components*

The physical layer sits outside the MAS. The environment layer is where the MAS touches it, which is why regimented safety norms belong there.

**Open systems.** In an open MAS the designer does not control the agents' internal code. Robots may come from different vendors, run learned policies, or be teleoperated. Correctness cannot rely on agents complying: the regulation layer must hold its guarantees against *any* agent behaviour. Section 7 models this assumption with nondeterministic agents.

**Robot fleets as MAS.** Warehouses, hospitals and factories run fleets of autonomous mobile robots in spaces shared with people. Traffic is managed per zone, because a narrow aisle can hold only one robot, and zones close when people work in them. Each zone controller decides locally, and messages between controllers take time. That makes the fleet a *distributed* regulation problem: two controllers can briefly disagree on which zones are closed.

### 2.1 Agent architectures and the BDI cycle

Agent architectures fall into three families:

- **Reactive** agents map percepts directly to actions. Brooks' subsumption architecture for robots is the classic example. They are fast but cannot plan.
- **Deliberative** agents keep a symbolic model of the world and reason about goals before acting.
- **Hybrid** agents layer a reactive part, e.g. obstacle avoidance, under a deliberative one, e.g. route and task choice.

Most mobile robots are hybrid. JaCaMo agents are deliberative at the task level.

A BDI agent repeats a **reasoning cycle**:

1. **Perceive.** Read percepts (sensors, artifact properties) and messages, and update the *belief base*.
2. **Deliberate.** Choose which goals to pursue; the chosen ones become *intentions*.
3. **Select a plan.** From the plan library, pick a plan whose trigger matches the goal and whose context condition holds in the current beliefs.
4. **Act.** Execute one step of one intention: an action, a message, or a sub-goal. Then go back to 1.

![Figure 2 · the BDI reasoning cycle](figures/figure2.png)

*Figure 2 · the BDI reasoning cycle*

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

The agent *chooses* whether to retry, park or report, which is its autonomy. The regulation layer can only constrain the outcomes, not the reasoning.

### 2.2 Environment: artifacts

In CArtAgO the environment is built from **artifacts**: objects that agents use, like tools. An artifact offers:

- **operations**: actions agents can perform on it
- **observable properties**: state that agents perceive as beliefs
- **signals**: one-off events

An operation can refuse to execute. That makes artifacts the natural place for *regimentation*: a prohibited action simply fails.

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

In a real fleet the artifact wraps a ROS 2 zone-controller node or a traffic server. The `ResourceGuard` machine of section 7 is its P model.

### 2.3 Interaction

Agents communicate with an agent communication language (KQML, FIPA ACL). Each message carries a **performative** stating its intent: *inform*, *request*, *propose*, *accept*, *refuse*. In Jason, `.send(r2, tell, at(zone1))` informs and `.send(r2, achieve, wait)` asks for a goal.

Recurring exchanges are fixed as **protocols**. The **Contract Net** is the classic one for task allocation: the manager announces a task, robots bid (e.g. distance to the pickup point), and the manager awards the task. Social-commitment approaches (Singh) give protocol steps a normative meaning. *"Having accepted the task, the robot is committed to delivering it"*, which links interaction to the norms of section 3.

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

At run time the organization is an artifact too. Agents adopt roles and commit to missions, and the organization's normative engine (NPL, section 3) creates and tracks the resulting obligations.

### 2.5 Multi-robot coordination

Fleets face three classic coordination problems, each a source of norms:

- **Task allocation.** Who does which delivery. Gerkey and Matarić (IJRR 2004) classify these problems by robot type (single- or multi-task), task type (single- or multi-robot) and timing (instantaneous or time-extended).
- **Path planning and traffic.** Multi-agent path finding computes collision-free routes. Industrial fleets often use simpler **zone reservation**: a robot may enter a zone only when it holds that zone. This is the model used here.
- **Deadlock.** Two robots facing each other in a one-lane corridor, each holding its zone and waiting for the other's, form a cycle of waiting. Remedies include one-way lanes, priorities, timeouts with backing off (here: parking after 3 denials), and global reservation of the whole corridor.

Each remedy is a norm: "one direction at a time" is a prohibition, "yield to the robot with priority" is an obligation. The project tests whether such norms interact safely with sanctions and closures.

## 3. Background: norms and normative MAS

Norms let a MAS steer autonomous agents without programming their internals. They state what *ought* to happen and say what follows when it does not. A **normative MAS** is a MAS whose behaviour is constrained by explicitly represented norms, which agents can reason about and the system can monitor and enforce ([Boella, van der Torre and Verhagen](#references)).

**Deontic modalities.** A regulative norm is usually one of:

- **Obligation** O(φ): the agent must bring about φ, typically before a deadline. *"The robot assigned delivery d must report it before tick 5."*
- **Prohibition** F(φ): the agent must not bring about φ. *"No robot may be in a zone while a person is inside."*
- **Permission** P(φ): φ is allowed, often as an exception to a prohibition.

Norms are usually *conditional*: an activation condition, a deontic content, a deadline or expiry, and a sanction. Their lifecycle runs: inactive → active → fulfilled, or violated → sanctioned.

**Regulative vs. constitutive norms.** Regulative norms constrain behaviour ("must", "must not"). Constitutive norms define what things *count as* in the institution, e.g. *"a person detected by the zone 1 light curtain counts as a human in zone 1"*. The adaptation model used in this project relies on both kinds (section 4).

**Two ways to enforce a norm:**

| Mechanism | Idea | Guarantee | Cost | In this project |
| --- | --- | --- | --- | --- |
| Regimentation | make the violation impossible: the environment refuses the action | the norm always holds | removes autonomy; only for actions the environment controls | each zone controller refuses entry to a closed or occupied zone |
| Sanctioning (regulation) | allow the violation, detect it, react with a sanction | holds only as far as sanctions deter | needs monitoring and a fair sanction policy | a missed delivery deadline leads to a sanction |

Safety-critical norms (people and robots in the same zone) must be regimented. Performance norms (deadlines) are normally sanctioned. [Alechina, Bulling, Dastani and Logan (AAMAS 2015)](https://nottingham-repository.worktribe.com/output/752739) show that not every norm can be enforced by a guard. This is why the split matters.

**Fairness of sanctions.** A sanction is justified only if the agent could have complied. In a fleet, regimentation itself can make compliance impossible. A robot denied entry to a closed zone, or stuck facing another robot in a one-lane corridor, will miss its deadline through no fault of its own. Sanctioning it penalizes the regulation's own side effects and distorts any reputation or incentive scheme built on sanctions.

This project states fairness as a checkable property: *an agent is sanctioned only for its own non-compliance, never for being blocked*. [Dell'Anna, Dastani and Dalpiaz](https://webspace.science.uu.nl/~dalpi001/papers/dell-dast-dalp-20-jaamas.pdf) study how to revise sanctions at run time when they turn out to be ineffective. This project instead looks for unfairness that is built into the design.

**Norms in JaCaMo.** Moise organizations are compiled into NPL (Normative Programming Language) programs. An NPL engine creates obligations when agents adopt roles and commit to missions, tracks their deadlines, and reports violations to the organization.

**Verifying norms.** Previous work verifies norms with model checking, for example:

- ORWELL + MCAPL ([Dennis et al.](https://personalpages.manchester.ac.uk/staff/louise.dennis/pubs/climaX.pdf))
- CÒIR in Maude ([Gasparini et al.](https://abdn.elsevierpure.com/en/publications/c%C3%B2ir-verifying-normative-specifications-of-complex-systems))
- norm enforcement as supervisory control ([Dastani, Sardina and Yazdanpanah](https://research.utwente.nl/en/publications/norm-enforcement-as-supervisory-control/))

These mostly verify a normative *specification*. This project verifies the *regulation machinery*: the concurrent components that monitor, enforce and change the norms.

### 3.1 Anatomy of a norm

A conditional norm can be written as a tuple of six parts. The delivery obligation of this project, part by part:

| Part | Meaning | Fleet example |
| --- | --- | --- |
| Addressee | who the norm binds (an agent or a role) | the robot playing `courier` for delivery d |
| Activation | when an instance of the norm starts | the fleet manager assigns d |
| Modality | obligation, prohibition or permission | obligation |
| Content | the state or action concerned | d is reported as delivered |
| Deadline | when the content must hold | tick of assignment + 5 |
| Sanction | what follows a violation (or reward for compliance) | a penalty recorded against the robot |

The norm is a template. Each assignment creates a new **norm instance** with its own deadline. The `ObligationManager` of section 7 keeps one record per instance.

### 3.2 Deontic logic in brief

Standard deontic logic (SDL) is a modal logic with the operators O (obligatory), P (permitted) and F (forbidden). They are interdefinable, and axiom D says that an obligation implies a permission, so no agent is obliged to do the impossible:

```latex
P(\varphi) \equiv \neg O(\neg\varphi) \qquad F(\varphi) \equiv O(\neg\varphi) \qquad O(\varphi) \rightarrow P(\varphi)
```

SDL has well-known limits. The best known is **contrary-to-duty** reasoning: what is obligatory *after* a violation. Example: *"a robot must not enter a closed zone; if it does, it must stop and report"*. Chisholm's paradox shows that SDL handles such norms badly.

For this reason normative MAS usually treat norms *operationally*, as objects with a lifecycle (section 3.3), checked against what happens in the system. This is also how P models them.

### 3.3 Lifecycle of a norm instance

Each norm instance moves through a small state machine. The monitors of section 7 watch these transitions through the P events shown under each state.

![Figure 3 · lifecycle of an obligation instance, with the P events that mark each state](figures/figure3.png)

*Figure 3 · lifecycle of an obligation instance, with the P events that mark each state*

An instance left in **Active** forever is the failure that liveness property L1 catches. A move from **Violated** to **Sanctioned** for a robot that could not have complied is what the fairness property F1 catches.

### 3.4 Norms as temporal properties

To verify norms with a model checker, each kind of norm becomes a temporal-logic property (G = always, F = eventually). The kind of property decides how it is checked in P:

| Norm kind | Temporal property | Property class | P construct | Checked at run time? |
| --- | --- | --- | --- | --- |
| Prohibition: *never two robots in a zone* | G ¬(occupancy > 1) | safety | `assert` in a spec | yes (PObserve) |
| Obligation without deadline: *every delivery is eventually resolved* | G(assigned → F resolved) | liveness | `hot` state in a spec | no: a finite log cannot show "never" |
| Obligation with deadline d | G(assigned → F≤d resolved) | bounded response (a safety property over time) | `assert` when the clock passes d | yes (PObserve) |
| Permission | none on its own | — | only as an exception inside a prohibition's monitor | — |

In an open system the regulation cannot guarantee that every obligation is *fulfilled*. It can only guarantee that every obligation is *resolved*, by fulfilment or by sanction. The property checked is therefore:

```latex
\mathbf{G}\big(\mathit{assigned}(r,d) \rightarrow \mathbf{F}_{\le 5}\,(\mathit{reported}(r,d) \lor \mathit{sanctioned}(r,d))\big)
```

### 3.5 Normative programming in JaCaMo: NPL

The Normative Programming Language (NPL) of Hübner, Boissier and Bordini states norms as rules. Each rule has a condition and a deontic consequence with a deadline. A simplified NPL-style rule for the delivery obligation:

```
norm n_deliver:
     play(R, courier, corridor_A) & assigned(R, D)
  -> obligation(R, n_deliver, delivered(D), `now` + `5 minutes`).
```

The NPL engine keeps every obligation instance in one of four states:

- **active**: condition holds, deadline not reached
- **fulfilled**: the content was achieved in time
- **unfulfilled**: the deadline passed, i.e. violated
- **inactive**: the condition stopped holding

The organization reacts to unfulfilled obligations, typically with a sanction. [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) extend NPL(s) and the SAI engine to support regulation adaptation (section 4).

### 3.6 Constitutive rules: Situated Artificial Institutions

Norms speak about *institutional* facts ("a person is in zone 1", "robot 2 entered zone 1"). The system observes *physical* facts ("light curtain 1 is interrupted", "robot 2 crossed marker M7"). **Constitutive rules** connect the two. In Situated Artificial Institutions (SAI, de Brito, Hübner and Boissier) they have the form *X count-as Y when C*:

- *light curtain 1 interrupted* **count-as** *a person in zone 1*
- *a message `close(zone1)` from an agent playing `picker`* **count-as** *a detect-fact for closing zone 1*

This matters for verification. If a count-as rule is wrong, the regulation acts on wrong facts even when every other component is correct. In this project the count-as layer appears twice:

- in the model, where the `announce` statements decide which events count as institutional facts;
- at run time, in the PObserve **log parser**, which turns log lines into those facts.

The parser is therefore part of what must be validated.

### 3.7 Sanctions

Sanctions can be:

- **material**: a fine or lost reward
- **reputational**: a lower trust score
- **access-based**: lower priority in task allocation or zone reservation

They can be applied by the organization, by peers or by the environment. Good sanction policies are *proportional* and *fair*: they punish only what the agent could have avoided (section 3, fairness of sanctions). In a fleet, access-based sanctions feed back into traffic. A robot whose priority was lowered waits longer and is more likely to miss its next deadline, so an unfair sanction can trigger more sanctions.

## 4. Background: regulation management in MAS

Regulation management balances the agents' autonomy with control of the whole system. It covers how regulations are represented, monitored, enforced and changed at run time. [Yan, Nardin, Boissier and Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) propose a **unified view** that places any design on three perspectives. They then use the resulting grid to classify existing MAS frameworks.

| Perspective | Options | This project (fleet) |
| --- | --- | --- |
| Regulation capabilities | what the regulation layer can do; operationalized here as *represent, monitor, enforce (regiment or sanction), adapt* | all four |
| MAOP dimension | agent-, environment-, interaction-, organization-centric, or hybrid (several at once) | **hybrid**: environment (zone controllers) + organization (fleet manager, closures) + agent (robots decide to park and give up) |
| Architectural style | centralized vs. decentralized / distributed regulators | **distributed**: one controller per zone, coordinated only by messages |

![Figure 4 · the fleet placed in the unified-view grid](figures/figure4.png)

*Figure 4 · the fleet placed in the unified-view grid*

The COINE 2025 paper is not openly deposited. In the first week the student checks the paper's exact list of capabilities and adjusts the mapping in section 7.

**Regulation adaptation.** Rules change at run time. Examples: a picker needs an aisle, a zone floods, a robot breaks down in a lane. [Yan et al. (ECAI 2025)](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) give a general adaptation model with three capabilities, each producing a fact:

1. **Detect**: notice a change that requires new regulation (a *detect-fact*).
2. **Design**: work out the new regulation (a *design-fact*).
3. **Execute**: install it in the running system (an *execute-fact*).

Constitutive and regulative norms govern who may run each step and when. The authors implement the model by extending the SAI and NPL(s) normative engines inside JaCaMo.

**Why the distributed style is hard.** With one regulator, executing an adaptation is a single local update. With one regulator per zone, the update must reach every controller. Messages arrive in some order, and agents keep acting while they travel. During that window controllers may disagree, and a robot can be admitted under the old rules. Two-phase commit, borrowed from distributed databases, closes the window:

- **Prepare.** Affected controllers stop admitting and drain the zone.
- **Commit.** Only after every controller has acknowledged does the new norm set take effect.

A new risk appears with it. Draining depends on robots being *able* to leave. In a one-lane corridor they may be blocked by each other.

**The gap this project addresses.** The unified view is a *classification*: it says where regulation lives, not whether a given design is correct. Interactions between distributed regulators, physical constraints and sanctions can only be found by exploring message interleavings: section 5.

### 4.1 The capabilities in detail

Each capability answers one design question. Two designs can place the same capability very differently.

| Capability | Question it answers | Design options | In this fleet |
| --- | --- | --- | --- |
| Represent | Where and how are the norms written down? | implicit in agent or controller code; explicit declarative norms (NPL); versioned norm sets | a versioned norm set: the set of closed zones, plus delivery obligations in the fleet manager |
| Monitor | Who observes what, and is it enough to detect a violation? | agents monitor themselves; artifacts observe actions on them; the organization collects reports | zone controllers observe entries and exits; the fleet manager observes reports and the clock |
| Enforce | What happens to a violation? | regimentation (it cannot happen) or sanctioning (it is detected and punished) | regimented zone capacity and closures; sanctioned deadlines |
| Adapt | How do the norms change at run time, and who may change them? | detect, design and execute steps, each run by an agent, an artifact or the organization | the picker detects; the coordinator designs and executes; the zone controllers install |

**Observability.** A norm can be monitored only if its content can be observed. *"No robot in a zone with a person"* needs both robot positions and person detection. If the light curtain of zone 1 fails, the regulation cannot see the person and silently stops protecting them. Run-time monitoring with PObserve checks what the logs say, so it inherits the same blind spots.

### 4.2 The MAOP views, with examples

The unified view places regulation along the four MAOP dimensions. The examples below are typical systems for each view; they are our reading, not the paper's classification, which the student checks in the first week.

| View | Regulation is represented and managed by… | Typical mechanism | Strength | Weakness |
| --- | --- | --- | --- | --- |
| Agent-centric | the agents themselves | norm-aware BDI agents that reason about obligations and choose to comply | full autonomy; no central component | relies on agents being honest and correct |
| Environment-centric | artifacts in the environment | CArtAgO artifacts or smart controllers that refuse forbidden actions | strong guarantees (regimentation) | only for actions that pass through an artifact |
| Interaction-centric | the protocols agents use to communicate | electronic institutions whose governors filter messages; commitment protocols | catches violations in communication | blind to physical actions |
| Organization-centric | an organizational infrastructure | Moise roles and missions with an NPL engine | explicit, inspectable norms | needs reliable reports from agents and environment |
| Hybrid | several of the above together | e.g. organization for obligations + environment for safety | each norm enforced where it is cheapest and strongest | the parts must stay consistent with each other |

The fleet is hybrid. Safety norms live in the environment (zone controllers), performance norms in the organization (fleet manager), and part of the regulation in the agents (robots decide when to give up). The consistency problem between these parts is what the project studies.

### 4.3 Architectural styles

| Style | Structure | Advantages | Risks |
| --- | --- | --- | --- |
| Centralized | one regulator for the whole system | one consistent view; simple to verify | bottleneck and single point of failure; does not scale to large sites |
| Hierarchical | regulators per area under a supervisor | local decisions with global oversight | the supervisor still sees changes late |
| Distributed | several peer regulators, each owning part of the system | scales; local, fast decisions; no single point of failure | regulators can disagree during a change; needs a coordination protocol |

Warehouses with hundreds of robots usually need the distributed style. This project uses its smallest interesting instance: three zone controllers.

### 4.4 Adaptation as a control loop

The detect, design, execute model of [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) resembles the **MAPE-K loop** of autonomic computing (Kephart and Chess, 2003). MAPE-K stands for Monitor, Analyze, Plan, Execute, over shared Knowledge:

| MAPE-K step | Adaptation capability | Fleet example |
| --- | --- | --- |
| Monitor + Analyze | detect | the picker's request is recognized as a need to close zone 1 |
| Plan | design | the coordinator computes norm set v + 1 with zone 1 closed |
| Execute | execute | the zone controllers install v + 1 |
| Knowledge | the norm sets and the organization's state | current version, closed zones, open obligations |

One difference matters. In a normative MAS the adaptation loop is **itself regulated**. Constitutive norms say which facts count as a valid trigger. Regulative norms say who may run each step, e.g. *only an agent playing `picker` or `safety_officer` may request a closure*. An unauthorized closure request is itself a violation.

### 4.5 Consistency during a regulation change

The **transition window** is the time between the decision to change the norms and the moment every regulator applies the change. Three hazards live in it:

1. **Stale admission.** A controller still on the old norm set admits a robot into a zone the new set closes (property S2).
2. **Premature entry.** The person enters before the zone has drained (properties S1 and R3).
3. **Lost or reordered update.** Two adaptations overlap and controllers apply them in different orders. Version numbers and serializing the adaptations in the coordinator prevent it.

The remedy borrowed from distributed databases is **two-phase commit**. It guarantees that all regulators switch or none does, and here it adds a drain step. It has a known cost: a participant that cannot finish its prepare phase blocks everyone. In the fleet, that participant is the zone 1 controller, waiting for a robot that cannot leave because the zone ahead is held by another robot. Whether this blocking can happen is liveness property L2.

## 5. Background: the P language and PObserve

P models a system as **state machines that communicate by asynchronous events**. Its checker explores many orderings of those events to find the one that breaks a property. P was created at Microsoft Research ([Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/)) and is used at AWS on services such as S3, DynamoDB and EC2.

P has also been used for robotics. SOTER ([Desai et al.](https://arxiv.org/pdf/1808.07921)) builds runtime-assured robot software on P, and [SOTER on ROS](https://escholarship.org/uc/item/5r78g42p) ports it to the Robot Operating System. A fleet with one controller per zone is exactly the kind of asynchronous system P targets.

**Core concepts:**

| Concept | P syntax | Meaning |
| --- | --- | --- |
| Event | `event eAccessRequest: tAccess;` | a typed message |
| Machine | `machine Robot { … }` | an actor with local variables and an input queue |
| State and handler | `state Moving { on eAccessDenied do (z: int) { … } }` | how the machine reacts to an event in a state |
| Send | `send guards[next], eAccessRequest, (agent = id, …);` | asynchronous message to another machine |
| Defer / ignore | `defer eX;` / `ignore eX;` | keep the event for later / drop it in this state |
| Nondeterminism | `if ($) { … }` | the checker tries both branches: models robots that may not report |
| Monitor (spec) | `spec S observes eA, eB { … }` | a global observer that asserts properties |
| Announce | `announce eTaskAbandoned, (agent = id, where = z);` | notify monitors without sending to any machine |
| Hot / cold state | `hot state InProgress { … }` | liveness: an execution must not stay in a hot state forever |
| Test case | `test tc [main=Test]: assert S in { … };` | a closed system plus the monitors to check |

The fairness monitor of this project shows how a normative property becomes a P spec:

```
type tAbandon = (agent: int, where: int);
event eTaskAbandoned: tAbandon;

spec SanctionsReflectMisconduct observes eTaskAbandoned, eSanctionApplied {
  var blocked: set[int];
  start state Watching {
    on eTaskAbandoned do (a: tAbandon) { blocked += (a.agent); }
    on eSanctionApplied do (o: tOutcome) {
      assert !(o.agent in blocked),
        format("robot {0} sanctioned although it was blocked", o.agent);
    }
  }
}
```

**Checking.** `p compile` builds the project. `p check -tc <test> -s 10000` runs 10,000 schedules of that test case. A failed assertion yields a trace under `PCheckerOutput/BugFinding/`, replayable with its seed. The checker is a bug finder: it explores many schedules but does not prove correctness for every fleet size.

**Modules and refinement.** [Desai's ModP work](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2020/EECS-2020-3.pdf) adds a module system for compositional, assume-guarantee reasoning. With it one can show that a composition of modules refines an abstract specification. That is the basis of research question 3. The student must check which of these features the current P release supports before relying on them.

**PObserve: the same monitors at run time.** PObserve checks logs of a real system against P specs.

1. `p compile --mode pobserve` compiles the monitors (no model machines) to Java classes: `PEvents`, `PTypes`, `PMachines`.
2. A Java **log parser** turns each log line into a P event plus a partition key (here, the site or warehouse).
3. The PObserve CLI (`java -jar PObserve-1.0.0.jar --jars <package> --spec <Monitor> -l <log>`) or the JUnit integration replays the events through the monitor.
4. It reports the first violation with a replay of the events that led to it.

![Figure 5 · design-time and run-time checking share one set of monitors](figures/figure5.png)

*Figure 5 · design-time and run-time checking share one set of monitors*

The design-time and run-time checks therefore share one definition of "correct". PObserve orders events by timestamp within a key, so logs from several fleet nodes need synchronized clocks (NTP or PTP).

PObserve reports assertion failures; it does not report hot states still open at the end of a finite log. Liveness properties are therefore restated as **bounded response** for run time.

### 5.1 Types and data

P is statically typed:

- **Primitive types:** `int`, `bool`, `float`, `string`, `machine` (a reference to a machine) and `event`.
- **Collections:** `seq[T]`, `set[T]`, `map[K, V]`.
- **Tuples:** named, e.g. `(agent: int, res: int, ver: int)`.
- **Enums and type aliases:** `type tNormSet = (ver: int, closed: set[int]);`.

Values are copied when sent, so machines share no memory. All coordination happens through messages, which is exactly what makes distributed regulation hard and what the checker explores.

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

- `send m, e, payload;` is **asynchronous**: the sender continues at once, and the event joins `m`'s single input queue.
- Events from one sender to one receiver arrive in the order sent. Events from different senders interleave in any order. This interleaving is what the checker explores.
- Messages are not lost by default. Failures (a crashed controller, a lost message) must be modelled explicitly, e.g. with a machine that may drop or delay messages using `$`.
- **Unhandled events are errors.** If a machine receives an event that its current state neither handles, defers nor ignores, the checker reports a bug. This catches protocol gaps early, such as a controller receiving `eRelease` while draining. Add `defer` and `ignore` deliberately, never just to silence the checker.

### 5.4 Specification monitors

A `spec` machine is a global observer:

- It lists the events it `observes`, and runs synchronously each time one of them is sent or announced.
- It cannot send events. It can only update its own variables and `assert`.
- A **cold** state is fine to end in. A **hot** state must eventually be left. If a run stays in a hot state for too long, the checker reports a liveness violation.
- `announce e, payload;` delivers an event to monitors only. Machines use it to publish institutional facts (an entry, a commit, a sanction) without sending them to anyone.

### 5.5 How the checker explores

The checker replaces the real scheduler. At every step it decides which machine runs next and how each `$` choice resolves.

One run up to a step bound is a **schedule**, and `-s 10000` asks for 10,000 of them. Strategies range from random choices to priority-based ones designed to reach deep bugs with few context switches. Each bug comes with the seed that reproduces it.

The search finds bugs; it does not prove their absence. Keep models small (2 robots, 3 zones, a bounded clock) and grow them only when the small model passes.

### 5.6 Common pitfalls

- **Over-deterministic test drivers.** If the test always starts the picker after the robots, many bugs cannot appear. Use `$` and several drivers to open up the orderings.
- **Monitor timing.** A monitor sees an event when it is *sent*, before the receiver processes it. A clock tick is visible to a monitor before the fleet manager has applied it. That is why the run-time deadline monitors (R1, R2) are not used in the checker.
- **Liveness and fairness.** Hot-state checks assume that every enabled machine eventually runs. A "violation" caused only by starving a machine forever is not a real bug.
- **Unbounded models.** An endless clock or retry loop makes schedules endless. Bound them (`maxTicks`, a retry limit) and say so in the report.

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

- **Partition keys.** The parser gives each event a key. All events of one key go, in timestamp order, to their own copy of the monitor. Choose the key so that every property needs the events of one key only. Here the key is the site, because a closure involves all zones of a site.
- **Ordering.** Events out of timestamp order within a key are counted as errors. PObserve also keeps a replay window of recent events (`--replay`) for reports. Clocks of fleet nodes must be synchronized; timestamps need microsecond precision.
- **Parser contract.** `apply(logLine)` returns a stream of zero or more events. It returns an empty stream for lines that are not regulation events. It must keep no static mutable state, because PObserve runs parsers on several threads.
- **Generated classes.** `p compile --mode pobserve` names tuple classes after their abbreviated field names, e.g. `(agent, res, ver)` becomes `PTuple_agent_res_ver`. Check the generated `PTypes.java` before writing the parser.
- **Two ways to run.** JUnit tests fit continuous integration on recorded logs. The CLI fits checking production logs on demand.

**Learning path (days 1–7):**

- [ ] Install P and complete the official tutorials ([p-org.github.io/P](https://p-org.github.io/P/)): ClientServer, TwoPhaseCommit. The second is directly relevant here.
- [ ] Read the PObserve pages: [overview](https://p-org.github.io/P/advanced/pobserve/pobserve/), [log parser](https://p-org.github.io/P/advanced/pobserve/logparser/), [CLI](https://p-org.github.io/P/advanced/pobserve/pobservecli/).
- [ ] Build and run the LockServer PObserve example in the P repository (`Src/PObserve/Examples/LockServerPObserve`).
- [ ] Read [Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/), sections 1–3, and the SOTER paper ([arXiv 1808.07921](https://arxiv.org/pdf/1808.07921)).

## 6. The system: robots in a shared corridor

Two mobile robots deliver goods through a one-lane corridor of three zones (0, 1, 2), each with capacity 1 and its own zone controller. Robot 1 travels 0 → 1 → 2 and robot 2 travels 2 → 1 → 0, so they meet head-on. A fleet manager assigns deliveries with deadlines. At unpredictable times a human picker needs zone 1, which first requires a **zone closure**: a regulation adaptation that closes zone 1 to robots.

![Figure 6 · the corridor seen from above (illustrative)](figures/figure6.png)

*Figure 6 · the corridor seen from above (illustrative)*

![Figure 7 · fleet architecture, components by MAOP dimension](figures/figure7.png)

*Figure 7 · fleet architecture, components by MAOP dimension*

Each zone controller decides alone, so a closure is safe only if all three switch norm sets before the picker enters. The coordinator's protocol, and the robots' ability to drain zone 1, are what the project verifies.

**Normal operation:**

1. The fleet manager assigns a delivery. This creates an obligation with a deadline.
2. The robot asks the controller of its next zone for entry. It keeps occupying its current zone until entry is granted, because a robot cannot vanish from a zone.
3. If the next zone is open and free, its controller admits the robot. The robot then releases the zone behind it.
4. After 3 denials the robot parks in a side bay, releases its zone and abandons the delivery.
5. At the last zone the robot leaves the corridor and reports. An open-system robot may fail to report.
6. If the deadline passes without a report, the fleet manager sanctions the robot.

**Zone closure (regulation adaptation):**

1. **Detect.** The picker requests the closure.
2. **Design.** The regulation coordinator computes the next norm set: version + 1, with zone 1 closed.
3. **Execute.** The new norm set is installed in every zone controller. Then the picker is told to enter.
4. On leaving, the picker requests the reverse adaptation, which reopens zone 1.

**Norms of the fleet:**

| Norm | Modality | Enforcement | Level |
| --- | --- | --- | --- |
| At most one robot per zone | prohibition | regimented by each zone controller | physical safety |
| No robot in a zone while a person is inside | prohibition | regimented by the zone controllers | physical safety |
| A person enters only after the closure is committed | obligation on the procedure | monitored | safety procedure |
| Report a delivery before its deadline | obligation with deadline | sanctioned by the fleet manager | performance |
| A delivery ends either fulfilled or sanctioned, never both | integrity of the organization | by construction, monitored | organizational |
| Sanction only an agent's own non-compliance | meta-norm on the sanction policy | monitored | fairness |

**Two execution policies.** Two ways of executing a closure are compared:

- **Naive.** The coordinator declares the new norm set at once and each zone controller installs it whenever its message arrives.
- **Two-phase.** The coordinator sends *prepare*. Controllers whose zone does not change acknowledge at once and keep serving. The controller of the affected zone stops admitting and waits until the zone is empty, then acknowledges. Only when all have acknowledged does the coordinator *commit*.

![Figure 8 · naive vs. two-phase zone closure, as message sequences](figures/figure8.png)

*Figure 8 · naive vs. two-phase zone closure, as message sequences*

In the naive sequence the zone 1 controller still holds norm set v0 when the robot asks to enter, because v1 is still in transit. The two-phase sequence cannot reach that state: the picker is told to enter only after zone 1 has drained and its controller has acknowledged.

Showing why the naive policy is unsafe, and why even the safe one is unfair to robots, are the two core results of the project.

## 7. Technical specification

The deliverable is a P project with three parts:

- a model of the fleet
- a catalogue of monitors checked against that model
- a PObserve package that checks the same monitors against logs

A starter kit with draft versions of all three is provided (section 9). The student must make it compile, correct it, justify every modelling choice, and extend it.

### 7.1 Model components

| P machine | Unified-view role | MAOP dimension | Responsibility |
| --- | --- | --- | --- |
| `Robot` (×2) | regulated agent | agent | requests the next zone, holds the current one, parks after 3 denials (announces `eTaskAbandoned`), reports or not (`$`) |
| `ResourceGuard` (×3) | regimentation | environment | one per zone; admits or denies by norm set and capacity; drains during prepare only if its zone changes |
| `ObligationManager` | sanctioning | organization | fleet manager: creates delivery obligations, checks deadlines on each tick, sanctions |
| `AdaptationCoordinator` | adaptation (detect → design → execute) | organization | versioned norm sets sent to all 3 controllers; two-phase or naive |
| `HumanRequester` | source of the detect-fact | environment (human) | the picker: requests the closure of zone 1, enters on commit, leaves, requests reopening |
| `Clock` | time | — | logical ticks; one final far-future tick so that every deadline passes |

### 7.2 Property catalogue

| Id | Monitor | Kind | Checked by | Expected with two-phase / naive |
| --- | --- | --- | --- | --- |
| S1 | `RegimentationSafety`: never two robots in a zone; never a robot and a person together | safety | checker + PObserve | holds / **violated** |
| S2 | `NoStaleAdmission`: no admission to a zone the committed norm set closes; versions in order | safety | checker + PObserve | holds / **violated** |
| S3 | `NoDoubleOutcome`: a delivery is never both fulfilled and sanctioned | safety | checker + PObserve | holds / holds |
| L1 | `EveryObligationResolved`: every delivery eventually fulfilled or sanctioned | liveness (hot state) | checker | holds / holds |
| L2 | `AdaptationCompletes`: every closure eventually commits | liveness (hot state) | checker | holds / holds |
| R1 | `ObligationDeadlineRespected`: resolved within 1 tick of the deadline | bounded response | PObserve | holds / holds |
| R2 | `AdaptationBoundedTime`: commits within 5 ticks | bounded response | PObserve | holds / holds |
| R3 | `LockoutBeforeEntry`: a person enters only a closed zone | safety (procedure) | checker + PObserve | holds / holds |
| F1 | `SanctionsReflectMisconduct`: no sanction for a robot that was blocked | fairness | checker + PObserve | **violated** / **violated** |

The expected outcomes are **hypotheses** from the design. A sample-log simulator agrees with them, but they have not yet been confirmed with `p check`. Confirming or refuting them is part of the work. F1 is *expected* to fail: its counterexample is a finding about the norms, not a bug in the monitor.

### 7.3 Experiments (priorities in 7.5)

| # | Experiment | Change to the model | Question answered |
| --- | --- | --- | --- |
| E1 | Baseline, two-phase | none | Do S1–S3, L1, L2 and R3 hold under 10^5 schedules? |
| E2 | Baseline, naive | `twoPhase = false` | Which monitor fails first, in which zone? Explain the trace step by step |
| E3 | Sanction fairness | test `tcFleetSanctionFairness` | Which situations cause unfair sanctions: the closure, the head-on conflict, or both? |
| E4 | Block every controller during prepare | remove the "unaffected controller acks at once" branch | Does draining now depend on parking? Does anything deadlock? |
| E5 | No parking | robots retry forever | Expect hold-and-wait in the corridor: does L2 fail when zone 1 must drain? |
| E6 | Traffic norm (remedy 1) | add a direction controller: one travel direction per corridor at a time | Does F1 then fail only because of closures? |
| E7 | Deadline suspension (remedy 2) | the fleet manager suspends a deadline while the regulation blocks the robot | Does F1 hold? At what cost to L1 and R1? |
| E8 | Scale | 3–4 robots or 4–5 zones | Checker run time; where does exploration stop scaling? |

**Stretch: refinement (research question 3).** Write an abstract centralized regulator: one machine holding the whole corridor state. Then show, by testing refinement or with P's module system, that the three distributed controllers plus the coordinator behave like it. The answer turns the unified view's architectural-style axis into a verified claim.

### 7.4 Run-time part (PObserve)

**Log contract.** One line per regulation event:

- `Site=fleet-A, Event=ENTER, Agent=1, Res=1, Ver=0`
- also `CONFIG` (all zones: `Capacity=0:1;1:1;2:1`), `TICK`, `OBLIGATION`, `FULFILLED`, `SANCTION`, `LEAVE`, `ADAPT_START`, `COMMIT`, `HUMAN_ENTER`, `HUMAN_LEAVE`
- `ABANDON` (`Agent, Where`), emitted by the robot when it gives up

The line is prefixed by a UTC timestamp with microseconds. `Site` is the partition key.

**Package.** A Gradle project that runs `p compile --mode pobserve` on the monitors only, plus a Java parser, JUnit tests (safety and fairness) and a CLI runner script.

**Validation:**

- the two-phase sample log passes every safety monitor
- the naive sample log fails S1 and S2
- both logs fail F1
- R1 and R2 detect injected faults: delete a `SANCTION` line, delay a `COMMIT`

**Instrumentation (stretch goal).** Emit the log from a ROS 2 simulation of the corridor (e.g. three zones in Gazebo or a 2D simulator), using the `regulation_log.py` helper. Write to a dedicated file, not through the ROS logger, whose prefix the parser does not expect. Run PObserve on that log.

### 7.5 Requirements

| Priority | Requirement |
| --- | --- |
| Must | All P files compile; E1–E3 run; each result is explained with the trace or report |
| Must | Every monitor is justified against a norm of section 6 |
| Must | The PObserve package builds; the safety and fairness JUnit tests pass on the sample logs |
| Should | E4 and E5; one remedy (E6 or E7) evaluated; the fault-injection runs for R1 and R2 |
| Could | E8; the second remedy; the refinement stretch; ROS 2 instrumentation and a run on its logs |

## 8. Work plan and deliverables

The project runs in five phases over 45 calendar days, counted from the start date. Each phase is 7 to 11 days long. Each phase ends with a short checkpoint meeting and a tagged commit.

![Figure 9 · work plan: 5 phases, 45 days, 5 deliverables](figures/figure9.png)

*Figure 9 · work plan: 5 phases, 45 days, 5 deliverables*

The verification phase is the core of the project: if the model slips, cut the optional ROS 2 instrumentation and the refinement stretch, not experiments E1–E3.

**Deliverables:**

| # | Deliverable | Due (day) | Content |
| --- | --- | --- | --- |
| D1 | Background note | 7 | 2–3 pages: MAS, norms, the unified view, P; the fleet placed in the grid, with justification |
| D2 | Verified model | 28 | compiling P project; results of E1–E3 and the Should experiments, with traces and explanations; one remedy evaluated |
| D3 | PObserve package | 38 | parser, JUnit tests (safety and fairness), runner, fault-injection logs, results |
| D4 | Final report | 45 | 8–12 pages in a workshop-paper format (e.g. EMAS, COINE or WESAAC) |
| D5 | Presentation and demo | 45 | 15 minutes: one checker counterexample and one PObserve fairness violation shown live |

## 9. Starter kit, setup and references

The `p-regulation` archive is given. This project uses `Common/`, `MobileRobots/` and `tools/`; `ManufacturingCell/` holds a simpler, centralized variant that is a useful reference.

| Path | Content | Status |
| --- | --- | --- |
| `Common/*.p` | shared model machines and monitors | draft, not yet compiled |
| `MobileRobots/PSrc`, `PSpec`, `PTst` | robots, wiring, fairness monitor, test cases | draft, not yet compiled |
| `MobileRobots/pobserve/` | Gradle build, parser, JUnit tests, sample logs | parser compiled and run on the sample logs; JUnit not yet run |
| `MobileRobots/INSTRUCTIONS.md` | step-by-step commands for both parts | ready |
| `tools/simulate_logs.py` | generates two-phase / naive fleet logs and previews monitor results | tested |
| `tools/instrumentation/regulation_log.py` | logging helper for ROS 2 / Python | tested |

**Environment:**

- .NET SDK 8.0, then `dotnet tool install --global P`
- Java 17 or later
- Gradle 8.x
- Python 3
- optionally ROS 2 for the instrumentation stretch

Alternatively, use the Docker image `ghcr.io/p-org/p:latest`, which bundles .NET, a JDK and the `p` CLI. Build the PObserve CLI once from the P repository (`Src/PObserve/PObserve`, `./gradlew build`).

**Getting started:**

```
cd MobileRobots
p compile
p check -tc tcFleetNaive -s 10000
p check -tc tcFleetSanctionFairness -s 10000
cd pobserve && gradle wrapper && ./gradlew build uberjar && ./run_pobserve.sh
```

### References

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

Textbooks and background (from the field's standard literature; locate the current editions):

- M. Wooldridge. *An Introduction to MultiAgent Systems.* Wiley, 2nd ed. 2009.
- O. Boissier, R. H. Bordini, J. F. Hübner, A. Ricci. *Multi-Agent Oriented Programming: Programming Multi-Agent Systems Using JaCaMo.* MIT Press, 2020.
- G. Boella, L. van der Torre, H. Verhagen. *Introduction to normative multiagent systems.* Computational & Mathematical Organization Theory, 2006.
