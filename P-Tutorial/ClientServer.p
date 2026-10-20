/*******************************************************************
  Lesson 2 — first P program.
  A client sends ePing to the server and waits for ePong back.

  Run:  p compile
        p check -tc tcSingleClient -i 100
*******************************************************************/

event ePing : machine;   // payload: who to reply to
event ePong;             // no payload

machine Client {
  var server : machine;

  start state Init {
    entry (s : machine) {      // payload passed at creation
      server = s;
      send server, ePing, this;
      goto WaitingForPong;
    }
  }

  state WaitingForPong {
    on ePong goto Done;
  }

  state Done {
    entry { print "client got pong"; }
  }
}

machine Server {
  start state Listening {
    on ePing do (client : machine) {
      send client, ePong;
    }
  }
}

machine Main {
  start state Init {
    entry {
      var server : machine;
      server = new Server();
      new Client(server);
    }
  }
}

test tcSingleClient [main = Main]: { Main, Client, Server };
