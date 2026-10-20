# P Tutorial

Learning [P](https://p-org.github.io/P/) — modeling and formally verifying distributed systems — starting from zero formal methods.

A browsable version of this tutorial lives in [`docs/index.html`](../docs/index.html) at the repo root, published via GitHub Pages.

---

## Why P exists

Distributed systems fail because of *interleavings*, not bad logic. Your coordinator sends a commit, a replica dies mid-write, a retry arrives out of order. Tests catch maybe one of these orderings. There are millions.

P's answer: write a **model** of your system as communicating state machines. A checker then explores the interleavings systematically — every order in which the machines can take their steps — looking for a scenario that violates a property you stated. Lost messages and crashed machines are part of that search too, once you model them (Lesson 4); P's `send` itself is reliable. When it finds one, it hands you the exact sequence of steps.

Three concepts cover most of it:

| Concept | What it is |
| --- | --- |
| `event` | A typed message. `event ePing : machine;` means "a ping carrying a machine reference". |
| `machine` | A state machine with local variables and an input queue. It's in exactly one state; it handles events and transitions with `goto`. |
| `spec` | An observer machine that watches events and asserts invariants. Specs never send messages; they only judge. |

The mental shift from testing: you don't write "given input X, expect output Y." You write "*no matter what happens*, two clients must never hold the lock at once" — and let the checker hunt for the counterexample.

---

## Installing (Windows / PowerShell)

P needs .NET SDK **8.0** specifically, plus Java 11+.

```powershell
winget install Microsoft.DotNet.SDK.8
winget install Microsoft.OpenJDK.17

# close and reopen PowerShell so PATH updates, then:
dotnet --list-sdks     # need an 8.0.*
java -version          # need 11+
```

Then the P tool itself. If the machine has no NuGet feed configured, the install fails with `No NuGet sources are defined or enabled` — add the default feed first:

```powershell
dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org
dotnet tool install --global P

# verify (PowerShell has no `which`)
Get-Command p
p --version
```

If `p` isn't recognized, add `%USERPROFILE%\.dotnet\tools` to your `PATH` and restart the shell.

Recommended editor:

```powershell
winget install Microsoft.VisualStudioCode
code --install-extension PLanguage.peasy-extension
```

---

## Lesson 2 — first program

[`ClientServer.p`](ClientServer.p) — a client pings the server, the server pongs back.

```powershell
p compile
p check -tc tcSingleClient -i 100
```

Key points:

- `send` is asynchronous and non-blocking — it puts the event in the target's input queue and returns. Each queue is FIFO, so two events one machine sends to another arrive in the order sent. What the checker varies is which machine runs next, so events from *different* senders can reach a queue in any order — that's the whole point.
- `on ePing do (client : machine) { ... }` handles the event and stays in the current state.
- `on ePong goto Done` transitions instead.
- `entry` runs once when you arrive in a state.
- `-i 100` explores 100 different schedules.

Read the output carefully: all 100 pass, and the summary says **"Explored 1 timeline."** One client, one server, nothing to reorder — only one distinct behavior exists. The checker had nothing to do, because we never told it what "correct" means.

---

## Lesson 3 — specs, and a bug worth finding

[`LockServer.p`](LockServer.p) — two clients, a lock server that grants the lock to anyone who asks, and a spec that notices.

```powershell
p compile
p check -tc tcMutualExclusion -i 100
```

The new idea is `spec`. A spec machine can't `send`, can't `new`, can't use `this`, and exactly one instance exists globally. It runs **synchronously**: the moment any machine executes `send client, eGranted, ...`, the spec's handler fires before anything else happens. So it sees a true global ordering of the events it observes — something no real participant in a distributed system could.

> **Watch out:** `assert MutualExclusion in { ... }` in the test declaration is what attaches the spec. Without that line the spec is dead code and the test passes silently.

**Question to sit with before running it:** the server grants unconditionally — so why might some of the 100 schedules still *pass*?

---

## Generated output

`p compile` and `p check` create `PGenerated/` and `PCheckerOutput/`. Both are gitignored — they're build artifacts that change every run and depend on the random seed. `PCheckerOutput/` holds the run summary, coverage data, and `.sci` schedule files; when the checker finds a bug, that `.sci` is what you feed to `p check --replay` to walk the counterexample step by step. Worth committing one only if you want to preserve a specific interesting trace as documentation.

---

## Next lessons

4. **Nondeterminism, failures, and liveness** — modeling message loss and crashed machines; `hot` and `cold` states for properties like "every request is *eventually* answered". A system satisfies a liveness spec if it never gets stuck in a `hot` state.
5. **Two-phase commit, end to end** — a real protocol with safety and liveness specs and multiple test cases.

---

## References

- [P documentation](https://p-org.github.io/P/)
- [Manual: monitors (specs)](https://p-org.github.io/P/manual/monitors/)
- [Official tutorial: two-phase commit](https://p-org.github.io/P/tutorial/twophasecommit/)
- [p-org/P on GitHub](https://github.com/p-org/P)
