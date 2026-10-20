# P-Language

Work with the [P language](https://p-org.github.io/P/) — modeling and formal verification of distributed systems.

## Contents

| Folder | Description |
| --- | --- |
| [`P-Tutorial/`](P-Tutorial/) | A tutorial from zero: installation, a first program (client-server), specs, and running the checker. |

## Prerequisites

- .NET SDK **8.0**
- Java 11+
- The P tool: `dotnet tool install --global P`

Full install instructions in [`P-Tutorial/README.md`](P-Tutorial/README.md).

## Building and checking

Each folder compiles independently — `cd` into it first:

```powershell
cd P-Tutorial
p compile
p check -tc tcSingleClient -i 100
```
