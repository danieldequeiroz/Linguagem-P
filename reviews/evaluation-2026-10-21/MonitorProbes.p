// Evaluation harness only. Project sources remain unchanged.
machine ProbeStaleVersion {
  start state Init {
    entry {
      var closed: set[int];
      closed += (1);
      announce eNormCommitted, (ver = 1, closed = closed);
      announce eResourceEntered, (agent = 1, res = 0, ver = 0);
    }
  }
}
test tcStaleOpenZone [main=ProbeStaleVersion]:
  assert NoStaleAdmission in { ProbeStaleVersion };

machine ProbeSanctionThenAbandon {
  start state Init {
    entry {
      announce eSanctionApplied, (id = 0, agent = 1);
      announce eTaskAbandoned, (id = 0, agent = 1, where = 1);
    }
  }
}
test tcSanctionThenAbandon [main=ProbeSanctionThenAbandon]:
  assert SanctionsReflectMisconduct in { ProbeSanctionThenAbandon };

machine ProbeAbandonThenSanction {
  start state Init {
    entry {
      announce eTaskAbandoned, (id = 0, agent = 1, where = 1);
      announce eSanctionApplied, (id = 0, agent = 1);
    }
  }
}
test tcAbandonThenSanction [main=ProbeAbandonThenSanction]:
  assert SanctionsReflectMisconduct in { ProbeAbandonThenSanction };
