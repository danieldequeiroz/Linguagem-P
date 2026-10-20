# Verified Regulation Management for a Manufacturing Cell (P + PObserve)

Graduate project specification · Oct 20, 2026 · Angelo

## Repository and access

All material is in the GitHub repository [perkusic/P-Language](https://github.com/perkusic/P-Language):

- **This project:** [`Projects/ProjectManufacturingCell2026`](https://github.com/perkusic/P-Language/tree/main/Projects/ProjectManufacturingCell2026). It contains the starter kit, the instructions and this specification.
- **P tutorial:** [`P-Tutorial`](https://github.com/perkusic/P-Language/tree/main/P-Tutorial). It covers installation, a first P program, specs and the checker; work through it in days 1–7.

**The repository is public: no account or authorization is needed.** Anyone can read it on GitHub, clone it (`git clone https://github.com/perkusic/P-Language.git`) or download it as a ZIP (green **Code** button → **Download ZIP**). A GitHub account is only needed to fork it or to propose changes.

## 1. Summary

The objective of this project is to build and verify the regulation layer of a manufacturing cell, in two steps:

1. Model the layer in the P language and model-check it.
2. Check logs from a running (or simulated) cell against the same P monitors with PObserve.

The project turns one cell of the conceptual grid of [Yan, Nardin, Boissier & Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) (*A Unified View on Regulation Management in Multi-Agent Systems*, COINE 2025) into a system whose properties can be checked. That grid crosses three perspectives: regulation capabilities, programming dimensions and architectural style. The cell in question is **organization-centric + environment-centric, centralized**.

**Research question.** Which regulation properties of a centralized, normative multi-agent manufacturing cell can be verified at design time? Which can only be monitored at run time? Where does the obvious implementation of regulation adaptation break?

**Expected result.** A naive adaptation ("declare the new norms, let controllers install them later") lets a maintenance technician enter an occupied work envelope. A two-phase adaptation (prepare, drain, commit) does not. The project must show both, with a counterexample trace and a run-time violation report.

**Learning outcomes.** On completion the student can:

- explain multi-agent systems, normative MAS and regulation management, and place a design in the unified-view grid;
- formalize obligations, prohibitions, sanctions and regulation adaptation as communicating state machines in P;
- write safety and liveness specifications as P monitors and interpret counterexamples from `p check`;
- compile the same monitors for PObserve, write a log parser, and check execution logs;
- argue which properties belong to design-time verification and which to run-time monitoring.

## 2. Background: multi-agent systems

A multi-agent system (MAS) is a set of autonomous agents that share an environment and interact to reach individual or collective goals. Each agent decides for itself, so the system's global behaviour is not programmed directly. That is why it needs regulation.

**Agents.** Following [Wooldridge](#references), an agent is a software or physical entity with four properties:

- **autonomy**: acts without direct intervention
- **reactivity**: responds to changes in its environment
- **pro-activeness**: pursues its own goals
- **social ability**: communicates with other agents

Most MAS platforms use the BDI model: agents reason over *beliefs*, *desires* (goals) and *intentions* (committed plans). The language Jason (AgentSpeak) is an example.

**Multi-Agent Oriented Programming (MAOP).** [Boissier et al.](#references) split a MAS into four programming dimensions, each with its own abstractions. JaCaMo combines one technology per dimension.

| Dimension | First-class abstractions | JaCaMo technology | Role in this project |
| --- | --- | --- | --- |
| Agent | beliefs, goals, plans | Jason | robot arm and AGV controllers |
| Environment | artifacts with operations and observable properties | CArtAgO | cell controller (PLC) admitting agents to the work envelope |
| Interaction | protocols, messages | Jason speech acts | access request / grant / deny protocol |
| Organization | roles, groups, missions, norms | Moise + NPL | job obligations, deadlines, sanctions, lock-out procedure |

![Figure 1 · MAOP dimensions and JaCaMo technologies, with the cell's components](figures/figure1.png)

*Figure 1 · MAOP dimensions and JaCaMo technologies, with the cell's components*

The physical layer sits outside the MAS. The environment layer is where the MAS touches it, which is why regimented safety norms belong there.

**Open systems.** In an open MAS the designer does not control the agents' internal code. Agents may come from different vendors or include learning components. Correctness cannot rely on agents complying: the regulation layer must hold its guarantees against *any* agent behaviour. Section 7 models this assumption with nondeterministic agents.

**MAS in industrial cyber-physical systems.** In Industry 4.0, machines, robots and transport units are wrapped as agents that negotiate tasks and resources. A manufacturing cell becomes a small MAS whose shared physical resources (a work envelope, a buffer, a tool) must be regulated. Some of its rules protect people, so they must hold *physically*, not only logically.

### 2.1 Agent architectures and the BDI cycle

Agent architectures fall into three families:

- **Reactive** agents map percepts directly to actions. They are fast but cannot plan.
- **Deliberative** agents keep a symbolic model of the world and reason about goals before acting.
- **Hybrid** agents layer a reactive part, e.g. a robot's collision stop, under a deliberative one, e.g. job sequencing.

Industrial agents are usually hybrid: a deliberative agent on top of a PLC or robot controller that handles real-time control. JaCaMo agents are deliberative at the task level.

A BDI agent repeats a **reasoning cycle**:

1. **Perceive.** Read percepts (sensors, artifact properties) and messages, and update the *belief base*.
2. **Deliberate.** Choose which goals to pursue; the chosen ones become *intentions*.
3. **Select a plan.** From the plan library, pick a plan whose trigger matches the goal and whose context condition holds in the current beliefs.
4. **Act.** Execute one step of one intention: an action, a message, or a sub-goal. Then go back to 1.

![Figure 2 · the BDI reasoning cycle](figures/figure2.png)

*Figure 2 · the BDI reasoning cycle*

The robot arm in Jason (AgentSpeak), simplified:

```
// plan: <trigger> : <context> <- <body>.
+!do_job(J) : true
   <- requestAccess;              // operation on the cell controller artifact; fails if denied
      !process(J);
      release;
      .send(org, tell, done(J)).    // the report that fulfils the obligation

// failure handling: after 3 denials give up the job (and accept the sanction)
-!do_job(J) : denials(N) & N >= 3
   <- .drop_intention(do_job(J)).
-!do_job(J)
   <- .wait(500); !do_job(J).
```

The agent *chooses* whether to retry, give up or report, which is its autonomy. The regulation layer can only constrain the outcomes, not the reasoning.

### 2.2 Environment: artifacts

In CArtAgO the environment is built from **artifacts**: objects that agents use, like tools. An artifact offers:

- **operations**: actions agents can perform on it
- **observable properties**: state that agents perceive as beliefs
- **signals**: one-off events

An operation can refuse to execute. That makes artifacts the natural place for *regimentation*: a prohibited action simply fails.

```java
// The cell controller as a CArtAgO artifact (sketch)
public class CellController extends Artifact {
  private int capacity;

  void init(int capacity) {
    this.capacity = capacity;
    defineObsProperty("occupancy", 0);
    defineObsProperty("lockedOut", false);    // set by the norm set in force
  }

  @OPERATION void requestAccess() {
    ObsProperty occ = getObsProperty("occupancy");
    if (getObsProperty("lockedOut").booleanValue() || occ.intValue() >= capacity) {
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

In a real cell the artifact wraps the PLC, typically through OPC UA, and the PLC drives the interlocks. The `ResourceGuard` machine of section 7 is its P model.

### 2.3 Interaction

Agents communicate with an agent communication language (KQML, FIPA ACL). Each message carries a **performative** stating its intent: *inform*, *request*, *propose*, *accept*, *refuse*. In Jason, `.send(org, tell, done(j7))` informs and `.send(agv, achieve, unload)` asks for a goal.

Recurring exchanges are fixed as **protocols**. The **Contract Net** is the classic one for job allocation: the organization announces a job, the arm and the AGV bid (e.g. on availability), and the job is awarded to one of them. Social-commitment approaches (Singh) give protocol steps a normative meaning. *"Having accepted the job, the agent is committed to completing it"*, which links interaction to the norms of section 3.

### 2.4 Organization: Moise

Moise describes an organization with three linked specifications:

| Specification | Describes | Cell example |
| --- | --- | --- |
| Structural | roles, groups, links between roles, cardinalities | group `cell_A` with role `operator_robot` (max 2) and role `cell_supervisor` (1) |
| Functional | global goals decomposed into **schemes** and **missions** | scheme `job`: goals `load`, `process`, `unload`, `report`; mission `m_job` covers them |
| Normative | obligations and permissions linking roles to missions, with deadlines | *an `operator_robot` is obliged to commit to `m_job` and achieve it within 4 ticks* |

A simplified normative specification:

```xml
<normative-specification>
  <norm id="n_job" type="obligation" role="operator_robot"
        mission="m_job" time-constraint="4 minutes"/>
</normative-specification>
```

At run time the organization is an artifact too. Agents adopt roles and commit to missions, and the organization's normative engine (NPL, section 3) creates and tracks the resulting obligations.

### 2.5 Agents in manufacturing

Agent-based manufacturing has a long history, and its architectures shape how regulation can be placed:

- **Holonic manufacturing.** PROSA (Van Brussel et al., 1998) splits a plant into product, resource and order holons, with optional staff holons that advise. ADACOR (Leitão and Restivo) adds adaptive switching between hierarchical and decentralized control.
- **Agents over automation.** Agents run above the real-time control layer (PLCs, IEC 61131 or IEC 61499 function blocks) and talk to it through OPC UA. Hard real-time and safety functions stay in that layer.
- **Safety rules.** Robot safety standards (ISO 10218) and lock-out/tag-out procedures (e.g. OSHA 29 CFR 1910.147) fix how people may enter a robot cell. The lock-out of this project is the normative-MAS counterpart of such a procedure.

The last point sets the bar for the project. A lock-out that is "usually" respected is not acceptable; the regulation must guarantee it, or the design must say which lower layer (an e-stop, a door interlock) does.

## 3. Background: norms and normative MAS

Norms let a MAS steer autonomous agents without programming their internals. They state what *ought* to happen and say what follows when it does not. A **normative MAS** is a MAS whose behaviour is constrained by explicitly represented norms, which agents can reason about and the system can monitor and enforce ([Boella, van der Torre and Verhagen](#references)).

**Deontic modalities.** A regulative norm is usually one of:

- **Obligation** O(φ): the agent must bring about φ, typically before a deadline. *"The agent assigned job j must report completion before tick d."*
- **Prohibition** F(φ): the agent must not bring about φ. *"No agent may be in the envelope while a person is inside."*
- **Permission** P(φ): φ is allowed, often as an exception to a prohibition.

Norms are usually *conditional*: an activation condition, a deontic content, a deadline or expiry, and a sanction. Their lifecycle runs: inactive → active → fulfilled, or violated → sanctioned.

**Regulative vs. constitutive norms.** Regulative norms constrain behaviour ("must", "must not"). Constitutive norms define what things *count as* in the institution, e.g. *"a badge swipe at door D counts as the technician entering the cell"*. The adaptation model used in this project relies on both kinds (section 4).

**Two ways to enforce a norm:**

| Mechanism | Idea | Guarantee | Cost | In this project |
| --- | --- | --- | --- | --- |
| Regimentation | make the violation impossible: the environment refuses the action | the norm always holds | removes autonomy; only for actions the environment controls | the cell controller refuses admission to a closed or full envelope |
| Sanctioning (regulation) | allow the violation, detect it, react with a sanction | holds only as far as sanctions deter | needs monitoring and a fair sanction policy | a missed job deadline leads to a sanction |

Safety-critical norms in a CPS (people and machines in the same space) must be regimented. Performance norms (deadlines) are normally sanctioned. [Alechina, Bulling, Dastani and Logan (AAMAS 2015)](https://nottingham-repository.worktribe.com/output/752739) show that not every norm can be enforced by a guard. This is why the split matters.

**Norms in JaCaMo.** Moise organizations are compiled into NPL (Normative Programming Language) programs. An NPL engine creates obligations when agents adopt roles and commit to missions, tracks their deadlines, and reports violations to the organization.

**Verifying norms.** Previous work verifies norms with model checking, for example:

- ORWELL + MCAPL ([Dennis et al.](https://personalpages.manchester.ac.uk/staff/louise.dennis/pubs/climaX.pdf))
- CÒIR in Maude ([Gasparini et al.](https://abdn.elsevierpure.com/en/publications/c%C3%B2ir-verifying-normative-specifications-of-complex-systems))
- norm enforcement as supervisory control ([Dastani, Sardina and Yazdanpanah](https://research.utwente.nl/en/publications/norm-enforcement-as-supervisory-control/))

These mostly verify a normative *specification*. This project verifies the *regulation machinery*: the concurrent components that monitor, enforce and change the norms.

### 3.1 Anatomy of a norm

A conditional norm can be written as a tuple of six parts. The job obligation of this cell, part by part:

| Part | Meaning | Cell example |
| --- | --- | --- |
| Addressee | who the norm binds (an agent or a role) | the agent playing `operator_robot` that accepted job j |
| Activation | when an instance of the norm starts | the organization assigns j |
| Modality | obligation, prohibition or permission | obligation |
| Content | the state or action concerned | j is reported as done |
| Deadline | when the content must hold | tick of assignment + 4 |
| Sanction | what follows a violation (or reward for compliance) | lower priority in the next job allocation |

The norm is a template. Each assignment creates a new **norm instance** with its own deadline. The `ObligationManager` of section 7 keeps one record per instance.

### 3.2 Deontic logic in brief

Standard deontic logic (SDL) is a modal logic with the operators O (obligatory), P (permitted) and F (forbidden). They are interdefinable, and axiom D says that an obligation implies a permission, so no agent is obliged to do the impossible:

```latex
P(\varphi) \equiv \neg O(\neg\varphi) \qquad F(\varphi) \equiv O(\neg\varphi) \qquad O(\varphi) \rightarrow P(\varphi)
```

SDL has well-known limits. The best known is **contrary-to-duty** reasoning: what is obligatory *after* a violation. Example: *"no agent may move in the envelope during a lock-out; if one does, the cell must trigger the e-stop"*. Chisholm's paradox shows that SDL handles such norms badly.

For this reason normative MAS usually treat norms *operationally*, as objects with a lifecycle (section 3.3), checked against what happens in the system. This is also how P models them.

#### Deontic logic seen from temporal logic

If you know LTL and CTL, you already know the shape of deontic logic. All three are *normal modal logics*: a box operator, its dual diamond, and a Kripke structure that gives them meaning. The box distributes over implication (axiom K) and every theorem can be boxed (necessitation). What changes is what the accessibility relation means (Figure 3). In temporal logic it links a point of a run to the later points; in deontic logic it links a world to its *ideal alternatives*, the worlds in which every norm is respected.

![Figure 3 · the box of temporal logic and the box of deontic logic](figures/figure3.png)

*Figure 3 · the box of temporal logic and the box of deontic logic*

|  | Temporal logic (LTL / CTL) | Deontic logic (SDL) |
| --- | --- | --- |
| Box | G φ: φ at every future point (AG: on every run) | O φ: φ in every ideal world |
| Diamond | F φ = ¬G¬φ: φ at some future point | P φ = ¬O¬φ: φ in some ideal world |
| Box of a negation | G ¬φ: φ never happens | Forb φ = O ¬φ: φ is forbidden |
| Accessibility | "later than", along a run | "ideal alternative of" |
| Characteristic axiom | T (reflexivity): G φ → φ | D (seriality): O φ → P φ |
| What ¬φ in the current state means | G φ is false: a counterexample | nothing wrong with the logic: O φ ∧ ¬φ is consistent |

A warning on notation: F means *eventually* in temporal logic and *forbidden* in deontic logic. This document writes Forb for the deontic operator.

The last two rows carry the essential difference. G is reflexive: if φ must always hold, it holds now, so a single state with ¬φ refutes G φ. O is *not* reflexive: the ideal worlds need not include the actual one, so "the job ought to be reported" and "the job was not reported" can both be true. This is exactly what a normative system needs. A violation is not a contradiction and not a bug; it is a state the system must be able to represent and react to. Axiom D only asks that every world have at least one ideal alternative, which rules out conflicting obligations (O φ ∧ O ¬φ) and nothing else.

#### From "ought" to "happens": the Andersonian reduction

[Anderson (1958)](https://doi.org/10.1093/mind/LXVII.265.100) showed that deontic logic can be reduced to an ordinary (alethic) modal logic plus one propositional constant V, read "a violation has occurred":

```latex
O\varphi \equiv \Box(\neg\varphi \rightarrow V) \qquad
P\varphi \equiv \Diamond(\varphi \wedge \neg V) \qquad
\mathit{Forb}\,\varphi \equiv \Box(\varphi \rightarrow V)
```

[Meyer (1988)](https://doi.org/10.1305/ndjfl/1093637776) applied the same idea to actions, in the style of dynamic logic: an action α is forbidden when every way of doing it ends in a violation, \[α\]V, and permitted when some way of doing it does not, ⟨α⟩¬V.

This reduction is the bridge the project relies on. Make the violation an observable event and read the box temporally, and every norm turns into an ordinary temporal property *about violations*. That is how the monitors of section 3.4 are written: none of them uses a deontic operator, and all of them mention fulfilment, violation or sanction events.

#### One trace, two readings

The reduction also makes clear *whose* behaviour is being specified (Figure 4).

![Figure 4 · one trace read deontically (agents) and temporally (regulator)](figures/figure4.png)

*Figure 4 · one trace read deontically (agents) and temporally (regulator)*

- **For the agents, norms are deontic.** An agent may miss a deadline. The specification must not reject that trace; it must say what follows. Writing G ¬V as a requirement would be a mistake: it would turn every norm into a regimented constraint and remove the agents' autonomy, which is the point of an open MAS.
- **For the regulator, properties are temporal.** The regulator must sanction every violation exactly once, must never admit an agent the norm set forbids, and must finish every adaptation. These are G and F properties that have to hold on every run, and a run that breaks them is a bug.

This is why the P monitors never assert that agents behave well. They assert that the *regulation* behaves well, whatever the agents do: S1 to S3 and R3 for regimented norms, where the regulator can block, and L1 and R1 for sanctioned norms, where the regulator must react.

#### Kinds of norms as temporal patterns

Once violations are events, each kind of norm has a recognisable temporal pattern. The table uses the cell's norms.

| Kind of norm | Example in the cell | Violation V occurs when | What the regulator must guarantee |
| --- | --- | --- | --- |
| Achievement obligation with a deadline | report the job by tick d | tick d passes without a report | G(created → F(fulfilled ∨ sanctioned)), L1; bounded at run time, R1 |
| Maintenance obligation | keep the envelope empty while it is locked out | an agent is admitted while it is closed | regimented: G(closed → ¬admitted), S2 |
| Prohibition | no agent in the envelope with a person | both are inside | regimented: G ¬(agent inside ∧ person inside), S1 |
| Contrary-to-duty obligation | if an agent is inside during lock-out, trigger the e-stop | the prohibition above is violated | G(V → X e-stop): a property of the *reaction* |
| Permission | an agent may enter an open, empty envelope | never: a permission cannot be violated | AG(request ∧ open → EF granted): branching, not a trace property |

Two rows deserve a comment.

- **Contrary-to-duty norms become easy.** Chisholm's paradox arises in SDL, which has neither time nor an explicit violation. With V as an event, the secondary obligation is simply triggered by it. Temporal deontic logics with deadlines avoid the paradox in the same way.
- **Permission is not a trace property.** "An agent *may* enter" says that some allowed continuation lets it enter. One run in which it did not enter proves nothing, because it may have chosen not to. In CTL this is an EF property over all possible futures. Neither a single-trace monitor nor PObserve can check it. The P checker can approximate it as liveness under fairness: every request to an open resource is eventually granted. Deciding which of the cell's norms become safety, liveness or branching properties is a good exercise for the report.

#### Two more paradoxes worth knowing

- **Ross's paradox.** From O(report the job) SDL derives O(report the job ∨ delete the log), because the box is closed under logical consequence. In LTL the same step, G φ → G(φ ∨ ψ), is harmless; for obligations it reads absurdly, since deleting the log seems to discharge the duty.
- **Free-choice permission.** "You may use cell A or cell B" should imply "you may use cell A", but P(φ ∨ ψ) → P φ is not valid in SDL.

These paradoxes are why this project specifies norms *operationally*, as machines that create, fulfil and violate norm instances, and verifies them with temporal monitors instead of reasoning in SDL. The [Stanford Encyclopedia entry on deontic logic](https://plato.stanford.edu/entries/logic-deontic/) is a good next read.

### 3.3 Lifecycle of a norm instance

Each norm instance moves through a small state machine. The monitors of section 7 watch these transitions through the P events shown under each state.

![Figure 5 · lifecycle of an obligation instance, with the P events that mark each state](figures/figure5.png)

*Figure 5 · lifecycle of an obligation instance, with the P events that mark each state*

An instance left in **Active** forever is the failure that liveness property L1 catches. Reaching both **Fulfilled** and **Sanctioned** for the same instance is what safety property S3 rules out.

### 3.4 Norms as temporal properties

To verify norms with a model checker, each kind of norm becomes a temporal-logic property (G = always, F = eventually). The kind of property decides how it is checked in P:

| Norm kind | Temporal property | Property class | P construct | Checked at run time? |
| --- | --- | --- | --- | --- |
| Prohibition: *never an agent and a person in the envelope* | G ¬(agentIn ∧ personIn) | safety | `assert` in a spec | yes (PObserve) |
| Obligation without deadline: *every job is eventually resolved* | G(assigned → F resolved) | liveness | `hot` state in a spec | no: a finite log cannot show "never" |
| Obligation with deadline d | G(assigned → F≤d resolved) | bounded response (a safety property over time) | `assert` when the clock passes d | yes (PObserve) |
| Permission | none on its own | — | only as an exception inside a prohibition's monitor | — |

In an open system the regulation cannot guarantee that every obligation is *fulfilled*. It can only guarantee that every obligation is *resolved*, by fulfilment or by sanction. The property checked is therefore:

```latex
\mathbf{G}\big(\mathit{assigned}(a,j) \rightarrow \mathbf{F}_{\le 4}\,(\mathit{reported}(a,j) \lor \mathit{sanctioned}(a,j))\big)
```

### 3.5 Normative programming in JaCaMo: NPL

The Normative Programming Language (NPL) of Hübner, Boissier and Bordini states norms as rules. Each rule has a condition and a deontic consequence with a deadline. A simplified NPL-style rule for the job obligation:

```
norm n_job:
     play(A, operator_robot, cell_A) & assigned(A, J)
  -> obligation(A, n_job, done(J), `now` + `4 minutes`).
```

The NPL engine keeps every obligation instance in one of four states:

- **active**: condition holds, deadline not reached
- **fulfilled**: the content was achieved in time
- **unfulfilled**: the deadline passed, i.e. violated
- **inactive**: the condition stopped holding

The organization reacts to unfulfilled obligations, typically with a sanction. [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) extend NPL(s) and the SAI engine to support regulation adaptation (section 4).

### 3.6 Constitutive rules: Situated Artificial Institutions

Norms speak about *institutional* facts ("the technician is in the cell", "the arm entered the envelope"). The system observes *physical* facts ("the light curtain is interrupted", "badge 0412 was swiped at door D"). **Constitutive rules** connect the two. In Situated Artificial Institutions (SAI, de Brito, Hübner and Boissier) they have the form *X count-as Y when C*:

- *badge swipe at door D* **count-as** *the technician entering the cell*, **when** *a lock-out is committed*
- *a lock-out request from an agent playing `maintenance`* **count-as** *a detect-fact for closing the cell*

This matters for verification. If a count-as rule is wrong, the regulation acts on wrong facts even when every other component is correct. In this project the count-as layer appears twice:

- in the model, where the `announce` statements decide which events count as institutional facts;
- at run time, in the PObserve **log parser**, which turns log lines into those facts.

The parser is therefore part of what must be validated.

### 3.7 Sanctions

Sanctions can be:

- **material**: a lost reward or a penalty in a cost model
- **reputational**: a lower trust score
- **access-based**: lower priority in job allocation, or a forced health check before the next job

They can be applied by the organization, by peers or by the environment. Good sanction policies are *proportional* and *fair*: they punish only what the agent could have avoided. In the cell, an agent denied access during a lock-out may miss its deadline through no fault of its own. Whether to sanction it then is a design decision the report should discuss.

### 3.8 Choosing an enforcement mechanism

The right mechanism for a norm depends on two questions: how much one violation costs, and whether the environment can physically block the forbidden action. Figure 6 places the norms of the cell on these two axes.

![Figure 6 · the norms of the cell placed by cost and controllability](figures/figure6.png)

*Figure 6 · the norms of the cell placed by cost and controllability*

- **High cost, blockable: regiment.** The cell controller can refuse entry, and a single collision or injury is unacceptable. Capacity and "no agent with a person" are therefore regimented.
- **High cost, not blockable: monitor, and add a safety layer.** The multi-agent system cannot stop a person from opening the door. The lock-out procedure can only be monitored (property R3), so the real guarantee must come from a layer below the MAS, such as a door interlock or an e-stop.
- **Low cost, not blockable: sanction.** A late job report costs throughput, not safety. The agents' autonomy is worth more than strict control.
- **Low cost, blockable: a design choice.** Regimentation is possible, but it may cost flexibility for little gain.

The figure also shows where verification matters most. A regimented norm must hold in every interleaving of events, which is exactly what the P checker explores. A sanctioned norm only needs to be resolved, fulfilled or sanctioned, which is a liveness question.

## 4. Background: regulation management in MAS

Regulation management balances the agents' autonomy with control of the whole system. It covers how regulations are represented, monitored, enforced and changed at run time. [Yan, Nardin, Boissier and Sichman](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1) propose a **unified view** that places any design on three perspectives. They then use the resulting grid to classify existing MAS frameworks.

| Perspective | Options | This project (cell) |
| --- | --- | --- |
| Regulation capabilities | what the regulation layer can do; operationalized here as *represent, monitor, enforce (regiment or sanction), adapt* | all four |
| MAOP dimension | agent-, environment-, interaction-, organization-centric, or hybrid (several at once) | organization-centric (obligations, adaptation) + environment-centric (the cell controller) |
| Architectural style | centralized vs. decentralized / distributed regulators | **centralized**: one cell controller, one organizational engine |

![Figure 7 · the cell placed in the unified-view grid](figures/figure7.png)

*Figure 7 · the cell placed in the unified-view grid*

The COINE 2025 paper is not openly deposited. In the first week the student checks the paper's exact list of capabilities and adjusts the mapping in section 7.

**Regulation adaptation.** Rules change at run time. Examples: a technician needs the cell, a shift changes, a sensor fails. [Yan et al. (ECAI 2025)](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) give a general adaptation model with three capabilities, each producing a fact:

1. **Detect**: notice a change that requires new regulation (a *detect-fact*).
2. **Design**: work out the new regulation (a *design-fact*).
3. **Execute**: install it in the running system (an *execute-fact*).

Constitutive and regulative norms govern who may run each step and when. The authors implement the model by extending the SAI and NPL(s) normative engines inside JaCaMo. A companion paper ([WESAAC 2025](https://sol.sbc.org.br/index.php/wesaac/article/view/37527)) discusses where adaptation can live along the MAOP dimensions, using a manufacturing case.

**The gap this project addresses.** The unified view is a *classification*. It says where regulation lives, not whether a given design is correct. Two components that each look correct can still interact badly. For example, an adaptation coordinator and a cell controller exchange messages asynchronously, so for a moment they may disagree on which norms are in force. Here that moment is the window in which a person and a robot share the envelope. Finding such windows needs a tool that explores message interleavings: section 5.

### 4.1 The capabilities in detail

Each capability answers one design question. Two designs can place the same capability very differently.

| Capability | Question it answers | Design options | In this cell |
| --- | --- | --- | --- |
| Represent | Where and how are the norms written down? | implicit in agent or controller code; explicit declarative norms (NPL); versioned norm sets | a versioned norm set (is the envelope locked out?), plus job obligations in the organization |
| Monitor | Who observes what, and is it enough to detect a violation? | agents monitor themselves; artifacts observe actions on them; the organization collects reports | the cell controller observes entries and exits; the door switch observes people; the organization observes reports and the clock |
| Enforce | What happens to a violation? | regimentation (it cannot happen) or sanctioning (it is detected and punished) | regimented capacity and lock-out; sanctioned deadlines |
| Adapt | How do the norms change at run time, and who may change them? | detect, design and execute steps, each run by an agent, an artifact or the organization | the technician detects; the coordinator designs and executes; the cell controller installs |

**Observability.** A norm can be monitored only if its content can be observed. *"No agent in the envelope with a person"* needs both the envelope occupancy and person detection. If the light curtain fails, the regulation cannot see the technician and silently stops protecting them. Run-time monitoring with PObserve checks what the logs say, so it inherits the same blind spots.

### 4.2 The MAOP views, with examples

The unified view places regulation along the four MAOP dimensions. The examples below are typical systems for each view; they are our reading, not the paper's classification, which the student checks in the first week.

| View | Regulation is represented and managed by… | Typical mechanism | Strength | Weakness |
| --- | --- | --- | --- | --- |
| Agent-centric | the agents themselves | norm-aware BDI agents that reason about obligations and choose to comply | full autonomy; no central component | relies on agents being honest and correct |
| Environment-centric | artifacts in the environment | CArtAgO artifacts or PLC interlocks that refuse forbidden actions | strong guarantees (regimentation) | only for actions that pass through an artifact |
| Interaction-centric | the protocols agents use to communicate | electronic institutions whose governors filter messages; commitment protocols | catches violations in communication | blind to physical actions |
| Organization-centric | an organizational infrastructure | Moise roles and missions with an NPL engine | explicit, inspectable norms | needs reliable reports from agents and environment |
| Hybrid | several of the above together | e.g. organization for obligations + environment for safety | each norm enforced where it is cheapest and strongest | the parts must stay consistent with each other |

The cell combines two views. Safety norms live in the environment (the cell controller) and performance norms in the organization (job obligations). The lock-out is where the two meet: the organization decides, the environment enforces.

### 4.3 Architectural styles

| Style | Structure | Advantages | Risks |
| --- | --- | --- | --- |
| Centralized | one regulator for the whole system | one consistent view; simple to verify | bottleneck and single point of failure; does not scale to large plants |
| Hierarchical | regulators per area under a supervisor | local decisions with global oversight | the supervisor still sees changes late |
| Distributed | several peer regulators, each owning part of the system | scales; local, fast decisions; no single point of failure | regulators can disagree during a change; needs a coordination protocol |

A single cell is naturally centralized: one controller owns the envelope. Even so, the regulator is split into two components, the coordinator (organization) and the controller (environment). The messages between them recreate in miniature the consistency problem of distributed systems.

### 4.4 Adaptation as a control loop

The detect, design, execute model of [Yan et al.](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1) resembles the **MAPE-K loop** of autonomic computing (Kephart and Chess, 2003). MAPE-K stands for Monitor, Analyze, Plan, Execute, over shared Knowledge:

| MAPE-K step | Adaptation capability | Cell example |
| --- | --- | --- |
| Monitor + Analyze | detect | the technician's request is recognized as a need for a lock-out |
| Plan | design | the coordinator computes norm set v + 1 with the envelope closed |
| Execute | execute | the cell controller installs v + 1 |
| Knowledge | the norm sets and the organization's state | current version, lock-out status, open obligations |

One difference matters. In a normative MAS the adaptation loop is **itself regulated**. Constitutive norms say which facts count as a valid trigger. Regulative norms say who may run each step, e.g. *only an agent playing `maintenance` or `safety_officer` may request a lock-out*. An unauthorized request is itself a violation.

### 4.5 Consistency during a regulation change

The **transition window** is the time between the decision to change the norms and the moment the controller applies the change. Three hazards live in it:

1. **Stale admission.** The controller, still on the old norm set, admits an agent after the lock-out was declared (property S2).
2. **Premature entry.** The technician enters before the envelope is empty (properties S1 and R3).
3. **Lost or reordered update.** Two adaptations overlap, e.g. a second technician's request arrives during a lock-out. Version numbers and serializing the adaptations in the coordinator prevent it.

The remedy borrowed from distributed databases is **two-phase commit**, here with a drain step: prepare, wait until the envelope is empty, acknowledge, then commit. It has a known cost: if the agent inside never leaves, the lock-out never completes. That is liveness property L2, and experiment E3 tests it. In a real cell the answer is a lower-level safeguard, the e-stop, which this project models only as a limit.

### 4.6 Lock-out/tag-out as regulation adaptation

The cell's lock-out is not an invented example. Industrial safety rules already prescribe a lock-out/tag-out (LOTO) procedure, and each of its steps has a counterpart in the adaptation model (Figure 8).

![Figure 8 · lock-out/tag-out steps and their counterparts in the model](figures/figure8.png)

*Figure 8 · lock-out/tag-out steps and their counterparts in the model*

The correspondence shows what the model adds and what it leaves out:

- **What the model adds.** In a real cell, "verify" means a person trying to start the machine. In the model, verification is a monitor checked in every explored interleaving: S1 (no agent with a person) and R3 (entry only after commit).
- **What the model leaves out.** Physical energy isolation and personal locks have no counterpart. The model trusts that a committed norm set stops the agents; the real procedure does not trust software at all. The report should state this gap explicitly.
- **Where the risk sits.** Prepare and commit are the steps the naive design gets wrong. In LOTO terms, it tells the technician to enter before the lock is on.

## 5. Background: the P language and PObserve

P models a system as **state machines that communicate by asynchronous events**. Its checker explores many orderings of those events to find the one that breaks a property. P was created at Microsoft Research ([Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/)) and is used at AWS on services such as S3, DynamoDB and EC2. Regulation components exchange messages asynchronously, so they fit this model directly.

**Core concepts:**

| Concept | P syntax | Meaning |
| --- | --- | --- |
| Event | `event eAccessRequest: tAccess;` | a typed message |
| Machine | `machine ResourceGuard { … }` | an actor with local variables and an input queue |
| State and handler | `state Open { on eAccessRequest do (r: tAccess) { … } }` | how the machine reacts to an event in a state |
| Send | `send guard, eAccessRequest, (agent = 1, …);` | asynchronous message to another machine |
| Defer / ignore | `defer eX;` / `ignore eX;` | keep the event for later / drop it in this state |
| Nondeterminism | `if ($) { … }` | the checker tries both branches: models agents that may not comply |
| Monitor (spec) | `spec S observes eA, eB { … }` | a global observer that asserts properties |
| Announce | `announce eResourceEntered, e;` | notify monitors without sending to any machine |
| Hot / cold state | `hot state Waiting { … }` | liveness: an execution must not stay in a hot state forever |
| Test case | `test tc [main=Test]: assert S in { … };` | a closed system plus the monitors to check |

A minimal regimentation guard and the safety monitor that watches it:

```
machine ResourceGuard {
  var occupants: set[int];
  var normSet: tNormSet;
  start state Open {
    on eAccessRequest do (r: tAccess) {
      if (!(resource in normSet.closed) && sizeof(occupants) < capacity) {
        occupants += (r.agent);
        announce eResourceEntered, (agent = r.agent, res = resource, ver = normSet.ver);
        send r.agentRef, eAccessGranted, (resource = resource, version = normSet.ver);
      } else {
        send r.agentRef, eAccessDenied, resource;
      }
    }
  }
}

spec RegimentationSafety observes eResourceEntered, eHumanEntered /* … */ {
  start state Watching {
    on eResourceEntered do (e: tEnter) {
      assert !(e.res in humanIn), "agent admitted while a human is inside";
    }
  }
}
```

**Checking.** `p compile` builds the project. `p check -tc <test> -s 10000` runs 10,000 schedules of that test case. A failed assertion yields a trace under `PCheckerOutput/BugFinding/`, replayable with its seed. The checker is a bug finder: it explores many schedules but does not prove correctness for every input size.

**PObserve: the same monitors at run time.** PObserve checks logs of a real system against P specs.

1. `p compile --mode pobserve` compiles the monitors (no model machines) to Java classes: `PEvents`, `PTypes`, `PMachines`.
2. A Java **log parser** turns each log line into a P event plus a partition key (here, the site).
3. The PObserve CLI (`java -jar PObserve-1.0.0.jar --jars <package> --spec <Monitor> -l <log>`) or the JUnit integration replays the events through the monitor.
4. It reports the first violation with a replay of the events that led to it.

![Figure 9 · design-time and run-time checking share one set of monitors](figures/figure9.png)

*Figure 9 · design-time and run-time checking share one set of monitors*

The design-time and run-time checks therefore share one definition of "correct".

PObserve reports assertion failures; it does not report hot states still open at the end of a finite log. Liveness properties are therefore restated as **bounded response** for run time, e.g. *"resolved within 1 tick of the deadline"*.

**What each check can establish.** The checker and PObserve answer different questions, and neither replaces the other (Figure 10).

![Figure 10 · what the checker and PObserve can each establish](figures/figure10.png)

*Figure 10 · what the checker and PObserve can each establish*

- **The checker** explores many schedules, but only of the model. A violation it finds is real only if the model is faithful. A violation in the "model only" region comes from an abstraction, for example agents that release the envelope instantly. Absence of violations is evidence about the design, bounded by the number of schedules explored.
- **PObserve** sees few executions, but real ones. A violation it reports happened, as far as the log is accurate. It says nothing about executions that were never logged, and nothing about faults the log cannot show, such as a sensor that missed a person.
- **The overlap** is where the two meet: the same monitor, written once, judging both the design and the running system. A finding in one place should be reproduced in the other. A counterexample from the checker becomes a test log; a PObserve violation becomes a new test case for the model.

The region outside both sets is the reason for a safety layer below the MAS: no software check covers a failure that neither the model nor the log can express.

### 5.1 Types and data

P is statically typed:

- **Primitive types:** `int`, `bool`, `float`, `string`, `machine` (a reference to a machine) and `event`.
- **Collections:** `seq[T]`, `set[T]`, `map[K, V]`.
- **Tuples:** named, e.g. `(agent: int, res: int, ver: int)`.
- **Enums and type aliases:** `type tNormSet = (ver: int, closed: set[int]);`.

Values are copied when sent, so machines share no memory. All coordination happens through messages, which is exactly why the coordinator and the cell controller can disagree for a moment, and what the checker explores.

### 5.2 Machine lifecycle

```
machine CellController {
  var occupants: set[int];
  start state Init {
    entry (cfg: (resource: int, capacity: int)) {  // payload given to `new`
      goto Open;
    }
  }
  state Open {
    on eAccessRequest do (r: tAccess) { /* admit or deny */ }
    on eNormPrepare goto Draining;                // leave Open, enter Draining
    ignore eTick;                                 // explicitly not interested
  }
  state Draining {
    entry { /* stop admitting; ack when the envelope is empty */ }
    defer eNormPrepare;                           // keep it queued for later
  }
}
```

- `new CellController((resource = 0, capacity = 1))` creates a machine and runs its start state's `entry` with the payload.
- `goto S` runs the current state's `exit`, then `S`'s `entry`.
- `raise e` handles an event immediately inside the same machine.
- `this` is the machine's own reference, used to receive replies.

### 5.3 Communication semantics

- `send m, e, payload;` is **asynchronous**: the sender continues at once, and the event joins `m`'s single input queue.
- Events from one sender to one receiver arrive in the order sent. Events from different senders interleave in any order. This interleaving is what the checker explores.
- Messages are not lost by default. Failures (a crashed controller, a lost message) must be modelled explicitly, e.g. with a machine that may drop or delay messages using `$`.
- **Unhandled events are errors.** If a machine receives an event that its current state neither handles, defers nor ignores, the checker reports a bug. This catches protocol gaps early, such as the controller receiving `eRelease` while draining. Add `defer` and `ignore` deliberately, never just to silence the checker.

### 5.4 Specification monitors

A `spec` machine is a global observer:

- It lists the events it `observes`, and runs synchronously each time one of them is sent or announced.
- It cannot send events. It can only update its own variables and `assert`.
- A **cold** state is fine to end in. A **hot** state must eventually be left. If a run stays in a hot state for too long, the checker reports a liveness violation.
- `announce e, payload;` delivers an event to monitors only. Machines use it to publish institutional facts (an entry, a commit, a sanction) without sending them to anyone.

### 5.5 How the checker explores

The checker replaces the real scheduler. At every step it decides which machine runs next and how each `$` choice resolves.

One run up to a step bound is a **schedule**, and `-s 10000` asks for 10,000 of them. Strategies range from random choices to priority-based ones designed to reach deep bugs with few context switches. Each bug comes with the seed that reproduces it.

The search finds bugs; it does not prove their absence. Keep models small (2 agents, 1 technician, a bounded clock) and grow them only when the small model passes.

**Why interleavings matter.** A concurrent system fails in orders of events, not in single events. Take three events during the lock-out: the arm leaves the envelope (L), the coordinator commits the new norm set (C), and the technician enters (H). The technician waits for the commit, so H always comes after C. That leaves three possible orders (Figure 11).

![Figure 11 · the orders of three lock-out events, and the one that breaks S1](figures/figure11.png)

*Figure 11 · the orders of three lock-out events, and the one that breaks S1*

Two of them are safe. The third, C then H then L, puts the technician in the envelope with the arm. Testing would see it only if the scheduler happened to deliver the messages in that order, which might be rare on a lightly loaded controller. The checker does not wait for luck: it enumerates the orders systematically, so a three-event race is found in seconds.

The figure also shows what a design fix does. The two-phase protocol does not make the unsafe order less likely; it makes it impossible, because the coordinator commits only after every guard reports that its resource is empty. A fix that only makes a race rarer, such as adding a delay before the commit, still leaves the branch in the tree, and the checker will still find it.

### 5.6 Common pitfalls

- **Over-deterministic test drivers.** If the test always starts the technician after the agents, many bugs cannot appear. Use `$` and several drivers to open up the orderings.
- **Monitor timing.** A monitor sees an event when it is *sent*, before the receiver processes it. A clock tick is visible to a monitor before the organization has applied it. That is why the run-time deadline monitors (R1, R2) are not used in the checker.
- **Liveness and fairness.** Hot-state checks assume that every enabled machine eventually runs. A "violation" caused only by starving a machine forever is not a real bug.
- **Unbounded models.** An endless clock or retry loop makes schedules endless. Bound them (`maxTicks`, a retry limit) and say so in the report.

### 5.7 Mapping normative concepts to P

| Normative concept | P construct | Where in the starter kit |
| --- | --- | --- |
| Norm set (lock-out status) | a versioned tuple `tNormSet` | `Common/MonitorEvents.p` |
| Regimented prohibition | admission check in a machine + `assert` in a monitor | `ResourceGuard.p`, `Specs.p` (S1) |
| Obligation instance | an entry in a `map` keyed by obligation id | `ObligationManager.p` |
| Deadline | logical clock events `eTick` | `Clock.p` |
| Violation and sanction | deadline check on each tick, then `eSanction` + `announce eSanctionApplied` | `ObligationManager.p` |
| Constitutive rule (count-as) | which `announce` a machine makes; at run time, the log parser | machines; `CellRegulationParser.java` |
| Adaptation (detect, design, execute) | coordinator states and the prepare/ack/commit events | `AdaptationCoordinator.p` |
| Open agent | nondeterministic `$` choices | `CellAgent.p` |
| Lock-out procedure | a monitor over `eNormCommitted` and `eHumanEntered` | `RuntimeSpecs.p` (R3) |

### 5.8 PObserve in more detail

- **Partition keys.** The parser gives each event a key. All events of one key go, in timestamp order, to their own copy of the monitor. Choose the key so that every property needs the events of one key only. Here the key is the cell (site), so several cells can share one log file.
- **Ordering.** Events out of timestamp order within a key are counted as errors. PObserve also keeps a replay window of recent events (`--replay`) for reports. Timestamps need microsecond precision.
- **Parser contract.** `apply(logLine)` returns a stream of zero or more events. It returns an empty stream for lines that are not regulation events. It must keep no static mutable state, because PObserve runs parsers on several threads.
- **Generated classes.** `p compile --mode pobserve` names tuple classes after their abbreviated field names, e.g. `(agent, res, ver)` becomes `PTuple_agent_res_ver`. Check the generated `PTypes.java` before writing the parser.
- **Two ways to run.** JUnit tests fit continuous integration on recorded logs. The CLI fits checking production logs on demand.

**Learning path (days 1–7):**

- [ ] Install P and complete the official tutorials ([p-org.github.io/P](https://p-org.github.io/P/)): ClientServer, TwoPhaseCommit.
- [ ] Read the PObserve pages: [overview](https://p-org.github.io/P/advanced/pobserve/pobserve/), [log parser](https://p-org.github.io/P/advanced/pobserve/logparser/), [CLI](https://p-org.github.io/P/advanced/pobserve/pobservecli/).
- [ ] Build and run the LockServer PObserve example in the P repository (`Src/PObserve/Examples/LockServerPObserve`).
- [ ] Read [Desai et al., PLDI 2013](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/), sections 1–3.

## 6. The system: a regulated manufacturing cell

A robot arm (agent 1) and an automated guided vehicle (AGV, agent 2) share one work envelope (resource 0, capacity 1). A single cell controller admits agents to the envelope. An organizational engine assigns jobs with deadlines. At unpredictable times a maintenance technician must enter the cell, which first requires a **lock-out**: a regulation adaptation that closes the envelope to agents.

![Figure 12 · the cell seen from above (illustrative)](figures/figure12.png)

*Figure 12 · the cell seen from above (illustrative)*

![Figure 13 · cell architecture, components by MAOP dimension](figures/figure13.png)

*Figure 13 · cell architecture, components by MAOP dimension*

The cell controller is the only path into the envelope, so regimented norms hold as long as its norm set is current. Keeping it current during a lock-out is the coordinator's job, and the job the project verifies.

**Normal operation:**

1. The organizational engine assigns a job to an agent. This creates an obligation with a deadline.
2. The agent requests the envelope from the cell controller.
3. If the envelope is open and free, the controller admits the agent. Otherwise it denies the request, and the agent retries up to 3 times before giving up.
4. The agent works, releases the envelope and reports completion. An open-system agent may fail to report.
5. If the deadline passes without a report, the organization sanctions the agent.

**Lock-out (regulation adaptation):**

1. **Detect.** The technician requests the lock-out.
2. **Design.** The adaptation coordinator computes the next norm set: version + 1, with resource 0 closed.
3. **Execute.** The new norm set is installed in the controller. Then the technician is told to enter.
4. On leaving, the technician requests the reverse adaptation, which reopens the envelope.

**Norms of the cell:**

| Norm | Modality | Enforcement | Level |
| --- | --- | --- | --- |
| At most one agent in the envelope | prohibition | regimented by the cell controller | physical safety |
| No agent in the envelope while a person is inside | prohibition | regimented by the cell controller | physical safety |
| A person enters only after the lock-out is committed | obligation on the procedure | monitored | safety procedure |
| Report a job before its deadline | obligation with deadline | sanctioned by the organization | performance |
| A job ends either fulfilled or sanctioned, never both | integrity of the organization | by construction, monitored | organizational |

**Two execution policies.** Two ways of executing the lock-out are compared:

- **Naive.** The coordinator declares the new norm set at once and the controller installs it whenever its message arrives.
- **Two-phase.** The coordinator sends *prepare*. The controller stops admitting, waits until the envelope is empty (drain), then acknowledges. Only then does the coordinator *commit*.

![Figure 14 · naive vs. two-phase lock-out, as message sequences](figures/figure14.png)

*Figure 14 · naive vs. two-phase lock-out, as message sequences*

In the naive sequence the controller still holds norm set v0 when the arm asks to enter, because v1 is still in transit. The two-phase sequence cannot reach that state: the technician is told to enter only after the controller has drained the envelope and acknowledged.

The naive policy is what a first implementation usually does. Showing *why* it is unsafe is the core result of the project.

**The two-phase protocol as state machines.** In the starter kit, the protocol is split between two P machines (Figure 15): the `AdaptationCoordinator` and one `ResourceGuard` per resource.

![Figure 15 · the two-phase protocol as two communicating state machines](figures/figure15.png)

*Figure 15 · the two-phase protocol as two communicating state machines*

- **Prepare.** The coordinator sends `eNormPrepare` to every guard. A guard whose resource the new norm set closes moves to `Draining`: it denies every new request but lets current occupants finish. An empty or unaffected guard acknowledges at once and goes straight to `AwaitCommit`.
- **Acknowledge.** When the last agent leaves, the guard sends `eNormPrepareAck` and waits. It still denies requests, because it does not yet know whether the commit has happened.
- **Commit.** Only with all acknowledgements in hand does the coordinator announce `eNormCommitted`, which the monitors observe and which allows the technician to enter. It then sends `eNormCommit` so each guard installs the new version.

The highlighted states carry the safety argument. Between `Preparing` and the commit, the closed resource is empty and nobody can enter it, so there is no moment in which a guard admits under the old rules while the technician acts under the new ones. The naive design skips both highlighted states. The cost of the protocol is visible too: if an occupant never leaves, the coordinator waits in `Preparing` forever. That is why L2 (`AdaptationCompletes`) is a liveness property worth checking, and why the experiments remove releases on purpose.

## 7. Technical specification

The deliverable is a P project with three parts:

- a model of the cell
- a catalogue of monitors checked against that model
- a PObserve package that checks the same monitors against logs

A starter kit with draft versions of all three is provided (section 9). The project consists of making it compile, correcting it, justifying every modelling choice, and extending it.

### 7.1 Model components

| P machine | Unified-view role | MAOP dimension | Responsibility |
| --- | --- | --- | --- |
| `CellAgent` (×2) | regulated agent | agent | requests the envelope, works, releases; reports or not (`$`) |
| `ResourceGuard` | regimentation | environment | admits or denies by norm set and capacity; drains during prepare |
| `ObligationManager` | sanctioning | organization | creates obligations, checks deadlines on each tick, sanctions |
| `AdaptationCoordinator` | adaptation (detect → design → execute) | organization | versioned norm sets; two-phase or naive policy |
| `HumanRequester` | source of the detect-fact | environment (human) | requests the lock-out, enters on commit, leaves, requests reopening |
| `Clock` | time | — | logical ticks; one final far-future tick so that every deadline passes |

### 7.2 Property catalogue

| Id | Monitor | Kind | Checked by | Expected with two-phase / naive |
| --- | --- | --- | --- | --- |
| S1 | `RegimentationSafety`: capacity never exceeded; never an agent and a person together | safety | checker + PObserve | holds / **violated** |
| S2 | `NoStaleAdmission`: no admission to a resource the committed norm set closes; versions in order | safety | checker + PObserve | holds / **violated** |
| S3 | `NoDoubleOutcome`: an obligation is never both fulfilled and sanctioned | safety | checker + PObserve | holds / holds |
| L1 | `EveryObligationResolved`: every obligation is eventually fulfilled or sanctioned | liveness (hot state) | checker | holds / holds |
| L2 | `AdaptationCompletes`: every adaptation eventually commits | liveness (hot state) | checker | holds / holds |
| R1 | `ObligationDeadlineRespected`: resolved within 1 tick of the deadline | bounded response | PObserve | holds / holds |
| R2 | `AdaptationBoundedTime`: commits within 5 ticks | bounded response | PObserve | holds / holds |
| R3 | `LockoutBeforeEntry`: a person enters only a locked-out resource | safety (procedure) | checker + PObserve | holds / holds |

The expected outcomes are **hypotheses** from the design. A sample-log simulator agrees with them, but they have not yet been confirmed with `p check`. Confirming or refuting them is part of the work.

### 7.3 Experiments (priorities in 7.5)

| # | Experiment | Change to the model | Question answered |
| --- | --- | --- | --- |
| E1 | Baseline, two-phase | none | Do S1–S3, L1, L2 and R3 hold under 10^5 schedules? |
| E2 | Baseline, naive | `twoPhase = false` | Which monitor fails first? Explain the trace step by step |
| E3 | Stuck agent | an agent never releases the envelope | Does L2 fail? What physical safeguard (e-stop) does this argue for? |
| E4 | Two technicians | a second `HumanRequester` | Are overlapping adaptations serialized correctly? |
| E5 | Deadline pressure | `due` from 4–6 down to 2 | How do sanctions grow, and do S3 and L1 still hold? |
| E6 | Scale | 3–4 agents, larger `maxTicks` | Checker run time and schedules per second; where does exploration stop scaling? |

### 7.4 Run-time part (PObserve)

**Log contract.** One line per regulation event:

- `Site=cell-A, Event=ENTER, Agent=1, Res=0, Ver=0`
- also `CONFIG`, `TICK`, `OBLIGATION`, `FULFILLED`, `SANCTION`, `LEAVE`, `ADAPT_START`, `COMMIT`, `HUMAN_ENTER`, `HUMAN_LEAVE`

The line is prefixed by a UTC timestamp with microseconds. `Site` is the partition key.

**Package.** A Gradle project that runs `p compile --mode pobserve` on the monitors only, plus a Java parser, JUnit tests and a CLI runner script.

**Validation:**

- the two-phase sample log passes every safety monitor
- the naive sample log fails S1 and S2
- R1 and R2 detect injected faults: delete a `SANCTION` line, delay a `COMMIT`

**Instrumentation (stretch goal).** Emit the log from a small JaCaMo implementation of the cell, using the `RegulationLog.java` helper. Run PObserve on that log.

### 7.5 Requirements

| Priority | Requirement |
| --- | --- |
| Must | All P files compile; E1 and E2 run; each result is explained with the trace or report |
| Must | Every monitor is justified against a norm of section 6 |
| Must | The PObserve package builds; both JUnit tests pass on the sample logs |
| Should | E3 and E4; the fault-injection runs for R1 and R2 |
| Could | E5 and E6; JaCaMo instrumentation and a run on its logs; comparison with a Maude or UPPAAL encoding of one property |

## 8. Work plan and deliverables

The project runs in five phases over 45 calendar days, counted from the start date. Each phase is 7 to 11 days long. Each phase ends with a short checkpoint meeting and a tagged commit.

![Figure 16 · work plan: 5 phases, 45 days, 5 deliverables](figures/figure16.png)

*Figure 16 · work plan: 5 phases, 45 days, 5 deliverables*

The verification phase is the core of the project: if the model slips, cut the optional JaCaMo instrumentation from the run-time phase, not experiments E1 and E2.

**Deliverables:**

| # | Deliverable | Due (day) | Content |
| --- | --- | --- | --- |
| D1 | Background note | 7 | 2–3 pages: MAS, norms, the unified view, P; the cell placed in the grid, with justification |
| D2 | Verified model | 28 | compiling P project; results of E1, E2 and the Should experiments, with traces and explanations |
| D3 | PObserve package | 38 | parser, JUnit tests, runner, fault-injection logs, results |
| D4 | Final report | 45 | 8–12 pages in a workshop-paper format (e.g. EMAS, COINE or WESAAC) |
| D5 | Presentation and demo | 45 | 15 minutes: one checker counterexample and one PObserve violation shown live |

## 9. Starter kit, setup and references

The `p-regulation` archive is given. This project uses `Common/`, `ManufacturingCell/` and `tools/`.

| Path | Content | Status |
| --- | --- | --- |
| `Common/*.p` | shared model machines and monitors | draft, not yet compiled |
| `ManufacturingCell/PSrc`, `PTst` | cell agents, wiring, test cases | draft, not yet compiled |
| `ManufacturingCell/pobserve/` | Gradle build, parser, JUnit tests, sample logs | parser compiled and run on the sample logs; JUnit not yet run |
| `ManufacturingCell/INSTRUCTIONS.md` | step-by-step commands for both parts | ready |
| `tools/simulate_logs.py` | generates two-phase / naive logs and previews monitor results | tested |
| `tools/instrumentation/RegulationLog.java` | logging helper for JaCaMo | compiles |

**Environment:**

- .NET SDK 8.0, then `dotnet tool install --global P`
- Java 17 or later
- Gradle 8.x
- Python 3

Alternatively, use the Docker image `ghcr.io/p-org/p:latest`, which bundles .NET, a JDK and the `p` CLI. Build the PObserve CLI once from the P repository (`Src/PObserve/PObserve`, `./gradlew build`).

**Getting started:**

```
cd ManufacturingCell
p compile
p check -tc tcCellNaive -s 10000
cd pobserve && gradle wrapper && ./gradlew build uberjar && ./run_pobserve.sh
```

### References

Core:

- E. Yan, L. G. Nardin, O. Boissier, J. S. Sichman. *A Unified View on Regulation Management in Multi-Agent Systems.* COINE workshop, 2025. [HAL](https://hal-emse.ccsd.cnrs.fr/emse-05162306v1)
- E. Yan, L. G. Nardin, O. Boissier, J. S. Sichman. *A Regulation Adaptation Model for Multi-Agent Systems.* ECAI 2025, doi:10.3233/FAIA251245. [HAL](https://hal-lara.archives-ouvertes.fr/ISCOD-ENSMSE/hal-05350751v1)
- E. Yan, L. G. Nardin, J. F. Hübner, O. Boissier, J. S. Sichman. *Perspectives on Regulation Adaptation in Multi-Agent Systems.* WESAAC 2025, doi:10.5753/wesaac.2025.37527. [SOL](https://sol.sbc.org.br/index.php/wesaac/article/view/37527)
- A. Desai et al. *P: Safe Asynchronous Event-Driven Programming.* PLDI 2013. [Microsoft Research](https://www.microsoft.com/en-us/research/publication/p-safe-asynchronous-event-driven-programming-2/)
- P language documentation and PObserve guides. [p-org.github.io/P](https://p-org.github.io/P/)
- M. Brooker, A. Desai. *Systems Correctness Practices at AWS.* ACM Queue / CACM. [ACM Queue](https://queue.acm.org/detail.cfm?id=3712057)

Norms and verification:

- N. Alechina, N. Bulling, M. Dastani, B. Logan. *Practical run-time norm enforcement with bounded lookahead.* AAMAS 2015. [repository](https://nottingham-repository.worktribe.com/output/752739)
- L. Dennis et al. *Model Checking Normative Agent Organisations.* [PDF](https://personalpages.manchester.ac.uk/staff/louise.dennis/pubs/climaX.pdf)
- L. Gasparini et al. *CÒIR: Verifying normative specifications of complex systems.* COIN 2015, LNCS 9628. [record](https://abdn.elsevierpure.com/en/publications/c%C3%B2ir-verifying-normative-specifications-of-complex-systems)
- M. Dastani, S. Sardina, V. Yazdanpanah. *Norm Enforcement as Supervisory Control.* PRIMA 2017. [record](https://research.utwente.nl/en/publications/norm-enforcement-as-supervisory-control/)
- D. Dell'Anna, M. Dastani, F. Dalpiaz. *Runtime Revision of Sanctions in Normative MAS.* JAAMAS 34(2), 2020. [PDF](https://webspace.science.uu.nl/~dalpi001/papers/dell-dast-dalp-20-jaamas.pdf)
- *Norm specification and verification in multi-agent systems* (survey). IfCoLoG J. Logics and their Applications 5(2), 2018. [record](https://research.ou.nl/en/publications/norm-specification-and-verification-in-multi-agent-systems/)
- O. Boissier, B. Gâteau. *Normative Multi-Agent Organizations: Modeling, Support and Control.* Dagstuhl 2007. [DROPS](https://drops.dagstuhl.de/entities/document/10.4230/DagSemProc.07122.18)

Deontic and temporal logic:

- A. R. Anderson. [A reduction of deontic logic to alethic modal logic](https://doi.org/10.1093/mind/LXVII.265.100). *Mind* 67(265):100–103, 1958.
- J.-J. Ch. Meyer. [A different approach to deontic logic: deontic logic viewed as a variant of dynamic logic](https://doi.org/10.1305/ndjfl/1093637776). *Notre Dame Journal of Formal Logic* 29(1):109–136, 1988.
- P. McNamara and F. Van De Putte. [Deontic logic](https://plato.stanford.edu/entries/logic-deontic/). *Stanford Encyclopedia of Philosophy*.

Textbooks and background (from the field's standard literature; locate the current editions):

- M. Wooldridge. *An Introduction to MultiAgent Systems.* Wiley, 2nd ed. 2009.
- O. Boissier, R. H. Bordini, J. F. Hübner, A. Ricci. *Multi-Agent Oriented Programming: Programming Multi-Agent Systems Using JaCaMo.* MIT Press, 2020.
- G. Boella, L. van der Torre, H. Verhagen. *Introduction to normative multiagent systems.* Computational & Mathematical Organization Theory, 2006.
- P. Leitão et al. *Smart Agents in Industrial Cyber-Physical Systems.* Proceedings of the IEEE 104(5), 2016.
