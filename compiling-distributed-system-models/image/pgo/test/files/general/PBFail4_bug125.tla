------------------------------ MODULE PBFail4 ------------------------------

EXTENDS Naturals, Sequences, TLC

CONSTANT BUFFER_SIZE
CONSTANT NUM_REPLICAS
CONSTANT NUM_CLIENTS
CONSTANT EXPLORE_FAIL

ASSUME NUM_REPLICAS > 0 /\ NUM_CLIENTS > 0

(************************
--mpcal PBFail {

    define {
        NUM_NODES == NUM_REPLICAS + NUM_CLIENTS

        CLIENT_SRC == 1
        PRIMARY_SRC == 2
        BACKUP_SRC == 3

        GET_REQ == 1
        GET_RESP == 2
        PUT_REQ == 3
        PUT_RESP == 4

        ACK_MSG == "ack-body"

        KEY1 == "KEY1"
        VALUE1 == "VALUE1"
        TEMP_VAL == "TEMP"
    }

    macro mayFail() {
        if (EXPLORE_FAIL = TRUE) {
            either {
                skip;
            } or {
                goto failLabel;
            };
        };
    }

    mapping macro TCPChannel {
        read {
            await Len($variable) > 0;
            with (msg = Head($variable)) {
                $variable := Tail($variable);
                yield msg;
            };
        }

        write {
            await Len($variable) < BUFFER_SIZE;
            yield Append($variable, $value);
        }
    }

    mapping macro FailureDetector {
        read {
            yield $variable;
        }

        write {
            yield $value;
        }
    }

    mapping macro FileSystem {
        read {
            yield $variable;
        }

        write {
            yield $value;
        }
    }

    archetype AReplica(ref net[_], ref fs[_], ref fd[_])
    variables
        msg, respBody, respTyp, idx, repMsg, rep, resp;
    {
        replicaLoop:
            while (TRUE) {
                rcvMsg:
                    either {
                        msg := net[<<self, GET_REQ>>];
                    } or {
                        msg := net[<<self, PUT_REQ>>];
                    };
                    assert(msg.to = self);
                    if (msg.srcTyp = CLIENT_SRC) {
                        goto handlePrimary;
                    } else if (msg.srcTyp = PRIMARY_SRC) {
                        goto handleBackup;
                    };

                handleBackup:
                    if (msg.typ = GET_REQ) {
                        respBody := fs[<<self, msg.body.key>>];
                        respTyp := GET_RESP;
                    } else if (msg.typ = PUT_REQ) {
                        fs[<<self, msg.body.key>>] := msg.body.value;
                        respBody := ACK_MSG;
                        respTyp := PUT_RESP;
                    };
                    resp := [from |-> self, to |-> msg.from, body |-> respBody,
                             srcTyp |-> BACKUP_SRC, typ |-> respTyp, id |-> msg.id];
                    net[<<resp.to, resp.typ>>] := resp;
                    goto replicaLoop;

                handlePrimary:
                    if (msg.typ = GET_REQ) {
                        respBody := fs[<<self, msg.body.key>>];
                        respTyp := GET_RESP;
                        goto sndResp;
                    } else if (msg.typ = PUT_REQ) {
                        fs[<<self, msg.body.key>>] := msg.body.value;
                        respBody := ACK_MSG;
                        respTyp := PUT_RESP;
                        goto sndReplicaMsg;
                    };
                    sndReplicaMsg:
                        idx := 1;
                        sndMsgLoop:
                            while (idx <= NUM_REPLICAS) {
                                sndMsg:
                                    if (fd[idx] = TRUE /\ idx # self) {
                                        repMsg := [from |-> self, to |-> idx, body |-> msg.body,
                                                   srcTyp |-> PRIMARY_SRC, typ |-> PUT_REQ,
                                                   id |-> msg.id];
                                        net[<<idx, PUT_REQ>>] := repMsg;
                                    };
                                    idx := idx + 1;
                            };
                    rcvReplicaMsg:
                        idx := 1;
                        rcvMsgLoop:
                            while (idx <= NUM_REPLICAS) {
                                rcvMsgFromReplica:
                                    if (fd[idx] = TRUE /\ idx # self) {
                                        rep := net[<<self, PUT_RESP>>];
                                        assert(rep.from = idx);
                                        assert(rep.to = self);
                                        assert(rep.body = ACK_MSG);
                                        assert(rep.srcTyp = BACKUP_SRC);
                                        assert(rep.typ = PUT_RESP);
                                        assert(rep.id = msg.id);
                                    };
                                    idx := idx + 1;
                            };
                    sndResp:
                        resp := [from |-> self, to |-> msg.from, body |-> respBody,
                                 srcTyp |-> PRIMARY_SRC, typ |-> respTyp, id |-> msg.id];
                        net[<<resp.to, resp.typ>>] := resp;
                        \* mayFail();
            };

        failLabel:
            fd[self] := FALSE;
    }

    archetype AClient(ref net[_], ref fd[_])
    variables
        req, resp, idx, body;
    {
        sndPutReq:
            idx := 1;
            sndPutReqLoop:
                while (idx <= NUM_REPLICAS) {
                    sndPutMsg:
                        if (fd[idx] = TRUE) {
                            body := [key |-> KEY1, value |-> VALUE1];
                            req := [from |-> self, to |-> idx, body |-> body,
                                    srcTyp |-> CLIENT_SRC, typ |-> PUT_REQ, id |-> 1];
                            net[<<req.to, req.typ>>] := req;
                            goto rcvPutResp;
                        };
                };
        rcvPutResp:
            if (fd[idx] = TRUE) {
                resp := net[<<self, PUT_RESP>>];
                assert(resp.to = self);
                assert(resp.body = ACK_MSG);
                assert(resp.srcTyp = PRIMARY_SRC);
                assert(resp.typ = PUT_RESP);
                assert(resp.id = 1);
                print <<"PUT RESP: ", resp>>;
            } else {
                goto sndPutReq;
            };

        sndGetReq:
            idx := 1;
            sndGetReqLoop:
                while (idx <= NUM_REPLICAS) {
                    sndGetMsg:
                        if (fd[idx] = TRUE) {
                            body := [key |-> KEY1, value |-> TEMP_VAL];
                            req := [from |-> self, to |-> idx, body |-> body,
                                    srcTyp |-> CLIENT_SRC, typ |-> GET_REQ, id |-> 2];
                            net[<<req.to, req.typ>>] := req;
                            goto rcvGetResp;
                        };
                };
        rcvGetResp:
            if (fd[idx] = TRUE) {
                resp := net[<<self, GET_RESP>>];
                assert(resp.to = self);
                assert(resp.body = VALUE1);
                assert(resp.typ = GET_RESP);
                assert(resp.id = 2);
                print <<"GET RESP: ", resp>>;
            } else {
                goto sndGetReq;
            };
    }

    variables
        network = [id \in 1..NUM_NODES, typ \in 1..4 |-> <<>>];
        fd = [id \in 1..NUM_NODES |-> TRUE];
        fs = [id \in 1..NUM_NODES, key \in {KEY1} |-> <<>>];

    fair process (Replica \in 1..NUM_REPLICAS) == instance AReplica(ref network[_], ref fs[_], ref fd[_])
        mapping network[_] via TCPChannel
        mapping fs[_] via FileSystem
        mapping fd[_] via FailureDetector;

    fair process (Client \in (NUM_REPLICAS+1)..(NUM_REPLICAS+NUM_CLIENTS)) == instance AClient(ref network[_], ref fd[_])
        mapping network[_] via TCPChannel
        mapping fd[_] via FailureDetector;
}

\* BEGIN PLUSCAL TRANSLATION

--algorithm PBFail {
    variables network = [id \in (1) .. (NUM_NODES), typ \in (1) .. (4) |-> <<>>], fd = [id \in (1) .. (NUM_NODES) |-> TRUE], fs = [id \in (1) .. (NUM_NODES), key \in {KEY1} |-> <<>>], netRead, netWrite, netRead0, netWrite0, fsRead, fsWrite, fsWrite0, fsWrite1, fsWrite2, fsWrite3, fdRead, netWrite1, netWrite2, netWrite3, netWrite4, netWrite5, fsWrite4, fdWrite, fdRead0, netWrite6, netWrite7, netWrite8, netRead1, netWrite9, netWrite10, netWrite11, netWrite12;
    define {
        NUM_NODES == (NUM_REPLICAS) + (NUM_CLIENTS)
        CLIENT_SRC == 1
        PRIMARY_SRC == 2
        BACKUP_SRC == 3
        GET_REQ == 1
        GET_RESP == 2
        PUT_REQ == 3
        PUT_RESP == 4
        ACK_MSG == 1
        KEY1 == "KEY1"
        VALUE1 == "VALUE1"
    }
    fair process (Replica \in (1) .. (NUM_REPLICAS))
    variables msg, respBody, respTyp, idx, repMsg, rep, resp;
    {
        replicaLoop:
            if (TRUE) {
                rcvMsg:
                    either {
                        await (Len(network[<<self, GET_REQ>>])) > (0);
                        with (msg0 = Head(network[<<self, GET_REQ>>])) {
                            netWrite := [network EXCEPT ![<<self, GET_REQ>>] = Tail(network[<<self, GET_REQ>>])];
                            netRead := msg0;
                        };
                        msg := netRead;
                        netWrite0 := netWrite;
                    } or {
                        await (Len(network[<<self, PUT_REQ>>])) > (0);
                        with (msg1 = Head(network[<<self, PUT_REQ>>])) {
                            netWrite := [network EXCEPT ![<<self, PUT_REQ>>] = Tail(network[<<self, PUT_REQ>>])];
                            netRead0 := msg1;
                        };
                        msg := netRead0;
                        netWrite0 := netWrite;
                    };
                    assert ((msg).to) = (self);
                    if (((msg).srcTyp) = (CLIENT_SRC)) {
                        network := netWrite0;
                        goto handlePrimary;
                    } else {
                        if (((msg).srcTyp) = (PRIMARY_SRC)) {
                            network := netWrite0;
                            goto handleBackup;
                        } else {
                            network := netWrite0;
                        };
                    };

                handleBackup:
                    if (((msg).typ) = (GET_REQ)) {
                        fsRead := fs[<<self, ((msg).body).key>>];
                        respBody := fsRead;
                        respTyp := GET_RESP;
                        fsWrite1 := fs;
                    } else {
                        if (((msg).typ) = (PUT_REQ)) {
                            fsWrite := [fs EXCEPT ![<<self, ((msg).body).key>>] = ((msg).body).value];
                            respBody := ACK_MSG;
                            respTyp := PUT_RESP;
                            fsWrite0 := fsWrite;
                            fsWrite1 := fsWrite0;
                        } else {
                            fsWrite0 := fs;
                            fsWrite1 := fsWrite0;
                        };
                    };
                    resp := [from |-> self, to |-> (msg).from, body |-> respBody, srcTyp |-> BACKUP_SRC, typ |-> respTyp, id |-> (msg).id];
                    await (Len(network[<<(resp).to, (resp).typ>>])) < (BUFFER_SIZE);
                    netWrite := [network EXCEPT ![<<(resp).to, (resp).typ>>] = Append(network[<<(resp).to, (resp).typ>>], resp)];
                    network := netWrite;
                    fs := fsWrite1;
                    goto replicaLoop;

                handlePrimary:
                    if (((msg).typ) = (GET_REQ)) {
                        fsRead := fs[<<self, ((msg).body).key>>];
                        respBody := fsRead;
                        respTyp := GET_RESP;
                        fsWrite3 := fs;
                        fs := fsWrite3;
                        goto sndResp;
                    } else {
                        if (((msg).typ) = (PUT_REQ)) {
                            fsWrite := [fs EXCEPT ![<<self, ((msg).body).key>>] = ((msg).body).value];
                            respBody := ACK_MSG;
                            respTyp := PUT_RESP;
                            fsWrite2 := fsWrite;
                            fsWrite3 := fsWrite2;
                            fs := fsWrite3;
                            goto sndReplicaMsg;
                        } else {
                            fsWrite2 := fs;
                            fsWrite3 := fsWrite2;
                            fs := fsWrite3;
                        };
                    };

                sndReplicaMsg:
                    idx := 1;

                sndMsgLoop:
                    if ((idx) <= (NUM_REPLICAS)) {
                        sndMsg:
                            fdRead := fd[idx];
                            if (((fdRead) = (TRUE)) /\ ((idx) # (self))) {
                                repMsg := [from |-> self, to |-> idx, body |-> (msg).body, srcTyp |-> PRIMARY_SRC, typ |-> PUT_REQ, id |-> (msg).id];
                                await (Len(network[<<idx, PUT_REQ>>])) < (BUFFER_SIZE);
                                netWrite := [network EXCEPT ![<<idx, PUT_REQ>>] = Append(network[<<idx, PUT_REQ>>], repMsg)];
                                netWrite1 := netWrite;
                            } else {
                                netWrite1 := network;
                            };
                            idx := (idx) + (1);
                            network := netWrite1;
                            goto sndMsgLoop;

                    } else {
                        netWrite2 := network;
                        network := netWrite2;
                    };

                rcvReplicaMsg:
                    idx := 1;

                rcvMsgLoop:
                    if ((idx) <= (NUM_REPLICAS)) {
                        rcvMsgFromReplica:
                            fdRead := fd[idx];
                            if (((fdRead) = (TRUE)) /\ ((idx) # (self))) {
                                await (Len(network[<<self, PUT_RESP>>])) > (0);
                                with (msg2 = Head(network[<<self, PUT_RESP>>])) {
                                    netWrite := [network EXCEPT ![<<self, PUT_RESP>>] = Tail(network[<<self, PUT_RESP>>])];
                                    netRead := msg2;
                                };
                                rep := netRead;
                                assert ((rep).from) = (idx);
                                assert ((rep).to) = (self);
                                assert ((rep).body) = (ACK_MSG);
                                assert ((rep).srcTyp) = (BACKUP_SRC);
                                assert ((rep).typ) = (PUT_RESP);
                                assert ((rep).id) = ((msg).id);
                                netWrite3 := netWrite;
                            } else {
                                netWrite3 := network;
                            };
                            idx := (idx) + (1);
                            network := netWrite3;
                            goto rcvMsgLoop;

                    } else {
                        netWrite4 := network;
                        network := netWrite4;
                    };

                sndResp:
                    resp := [from |-> self, to |-> (msg).from, body |-> respBody, srcTyp |-> PRIMARY_SRC, typ |-> respTyp, id |-> (msg).id];
                    await (Len(network[<<(resp).to, (resp).typ>>])) < (BUFFER_SIZE);
                    netWrite := [network EXCEPT ![<<(resp).to, (resp).typ>>] = Append(network[<<(resp).to, (resp).typ>>], resp)];
                    network := netWrite;
                    goto replicaLoop;

            } else {
                netWrite5 := network;
                fsWrite4 := fs;
                network := netWrite5;
                fs := fsWrite4;
            };
        failLabel:
            fdWrite := [fd EXCEPT ![self] = FALSE];
            fd := fdWrite;

    }
    fair process (Client \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)))
    variables req, resp, idx, body;
    {
        sndPutReq:
            idx := 1;
        sndPutReqLoop:
            if ((idx) <= (NUM_REPLICAS)) {
                sndPutMsg:
                    fdRead0 := fd[idx];
                    if ((fdRead0) = (TRUE)) {
                        body := [key |-> KEY1, value |-> VALUE1];
                        req := [from |-> self, to |-> idx, body |-> body, srcTyp |-> CLIENT_SRC, typ |-> PUT_REQ, id |-> 1];
                        await (Len(network[<<(req).to, (req).typ>>])) < (BUFFER_SIZE);
                        netWrite6 := [network EXCEPT ![<<(req).to, (req).typ>>] = Append(network[<<(req).to, (req).typ>>], req)];
                        netWrite7 := netWrite6;
                        network := netWrite7;
                        goto rcvPutResp;
                    } else {
                        netWrite7 := network;
                        network := netWrite7;
                        goto sndPutReqLoop;
                    };

            } else {
                netWrite8 := network;
                network := netWrite8;
            };
        rcvPutResp:
            fdRead0 := fd[idx];
            if ((fdRead0) = (TRUE)) {
                await (Len(network[<<self, PUT_RESP>>])) > (0);
                with (msg3 = Head(network[<<self, PUT_RESP>>])) {
                    netWrite6 := [network EXCEPT ![<<self, PUT_RESP>>] = Tail(network[<<self, PUT_RESP>>])];
                    netRead1 := msg3;
                };
                resp := netRead1;
                assert ((resp).to) = (self);
                assert ((resp).body) = (ACK_MSG);
                assert ((resp).srcTyp) = (PRIMARY_SRC);
                assert ((resp).typ) = (PUT_RESP);
                assert ((resp).id) = (1);
                print <<"PUT RESP: ", resp>>;
                netWrite9 := netWrite6;
                network := netWrite9;
            } else {
                netWrite9 := network;
                network := netWrite9;
                goto sndPutReq;
            };
        sndGetReq:
            idx := 1;
        sndGetReqLoop:
            if ((idx) <= (NUM_REPLICAS)) {
                sndGetMsg:
                    fdRead0 := fd[idx];
                    if ((fdRead0) = (TRUE)) {
                        body := [key |-> KEY1];
                        req := [from |-> self, to |-> idx, body |-> body, srcTyp |-> CLIENT_SRC, typ |-> GET_REQ, id |-> 2];
                        await (Len(network[<<(req).to, (req).typ>>])) < (BUFFER_SIZE);
                        netWrite6 := [network EXCEPT ![<<(req).to, (req).typ>>] = Append(network[<<(req).to, (req).typ>>], req)];
                        netWrite10 := netWrite6;
                        network := netWrite10;
                        goto rcvGetResp;
                    } else {
                        netWrite10 := network;
                        network := netWrite10;
                        goto sndGetReqLoop;
                    };

            } else {
                netWrite11 := network;
                network := netWrite11;
            };
        rcvGetResp:
            fdRead0 := fd[idx];
            if ((fdRead0) = (TRUE)) {
                await (Len(network[<<self, GET_RESP>>])) > (0);
                with (msg4 = Head(network[<<self, GET_RESP>>])) {
                    netWrite6 := [network EXCEPT ![<<self, GET_RESP>>] = Tail(network[<<self, GET_RESP>>])];
                    netRead1 := msg4;
                };
                resp := netRead1;
                assert ((resp).to) = (self);
                assert ((resp).body) = (VALUE1);
                assert ((resp).typ) = (GET_RESP);
                assert ((resp).id) = (2);
                print <<"GET RESP: ", resp>>;
                netWrite12 := netWrite6;
                network := netWrite12;
            } else {
                netWrite12 := network;
                network := netWrite12;
                goto sndGetReq;
            };

    }
}
\* END PLUSCAL TRANSLATION


************************)
\* BEGIN TRANSLATION (chksum(pcal) = "cd8a5a17" /\ chksum(tla) = "945ffca")
\* Process variable idx of process Replica at line 252 col 39 changed to idx_
\* Process variable resp of process Replica at line 252 col 57 changed to resp_
CONSTANT defaultInitValue
VARIABLES network, fd, fs, netRead, netWrite, netRead0, netWrite0, fsRead,
          fsWrite, fsWrite0, fsWrite1, fsWrite2, fsWrite3, fdRead, netWrite1,
          netWrite2, netWrite3, netWrite4, netWrite5, fsWrite4, fdWrite,
          fdRead0, netWrite6, netWrite7, netWrite8, netRead1, netWrite9,
          netWrite10, netWrite11, netWrite12, pc

(* define statement *)
NUM_NODES == (NUM_REPLICAS) + (NUM_CLIENTS)
CLIENT_SRC == 1
PRIMARY_SRC == 2
BACKUP_SRC == 3
GET_REQ == 1
GET_RESP == 2
PUT_REQ == 3
PUT_RESP == 4
ACK_MSG == 1
KEY1 == "KEY1"
VALUE1 == "VALUE1"

VARIABLES msg, respBody, respTyp, idx_, repMsg, rep, resp_, req, resp, idx,
          body

vars == << network, fd, fs, netRead, netWrite, netRead0, netWrite0, fsRead,
           fsWrite, fsWrite0, fsWrite1, fsWrite2, fsWrite3, fdRead, netWrite1,
           netWrite2, netWrite3, netWrite4, netWrite5, fsWrite4, fdWrite,
           fdRead0, netWrite6, netWrite7, netWrite8, netRead1, netWrite9,
           netWrite10, netWrite11, netWrite12, pc, msg, respBody, respTyp,
           idx_, repMsg, rep, resp_, req, resp, idx, body >>

ProcSet == ((1) .. (NUM_REPLICAS)) \cup (((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)))

Init == (* Global variables *)
        /\ network = [id \in (1) .. (NUM_NODES), typ \in (1) .. (4) |-> <<>>]
        /\ fd = [id \in (1) .. (NUM_NODES) |-> TRUE]
        /\ fs = [id \in (1) .. (NUM_NODES), key \in {KEY1} |-> <<>>]
        /\ netRead = defaultInitValue
        /\ netWrite = defaultInitValue
        /\ netRead0 = defaultInitValue
        /\ netWrite0 = defaultInitValue
        /\ fsRead = defaultInitValue
        /\ fsWrite = defaultInitValue
        /\ fsWrite0 = defaultInitValue
        /\ fsWrite1 = defaultInitValue
        /\ fsWrite2 = defaultInitValue
        /\ fsWrite3 = defaultInitValue
        /\ fdRead = defaultInitValue
        /\ netWrite1 = defaultInitValue
        /\ netWrite2 = defaultInitValue
        /\ netWrite3 = defaultInitValue
        /\ netWrite4 = defaultInitValue
        /\ netWrite5 = defaultInitValue
        /\ fsWrite4 = defaultInitValue
        /\ fdWrite = defaultInitValue
        /\ fdRead0 = defaultInitValue
        /\ netWrite6 = defaultInitValue
        /\ netWrite7 = defaultInitValue
        /\ netWrite8 = defaultInitValue
        /\ netRead1 = defaultInitValue
        /\ netWrite9 = defaultInitValue
        /\ netWrite10 = defaultInitValue
        /\ netWrite11 = defaultInitValue
        /\ netWrite12 = defaultInitValue
        (* Process Replica *)
        /\ msg = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ respBody = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ respTyp = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ idx_ = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ repMsg = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ rep = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        /\ resp_ = [self \in (1) .. (NUM_REPLICAS) |-> defaultInitValue]
        (* Process Client *)
        /\ req = [self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) |-> defaultInitValue]
        /\ resp = [self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) |-> defaultInitValue]
        /\ idx = [self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) |-> defaultInitValue]
        /\ body = [self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) |-> defaultInitValue]
        /\ pc = [self \in ProcSet |-> CASE self \in (1) .. (NUM_REPLICAS) -> "replicaLoop"
                                        [] self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) -> "sndPutReq"]

replicaLoop(self) == /\ pc[self] = "replicaLoop"
                     /\ IF TRUE
                           THEN /\ pc' = [pc EXCEPT ![self] = "rcvMsg"]
                                /\ UNCHANGED << network, fs, netWrite5,
                                                fsWrite4 >>
                           ELSE /\ netWrite5' = network
                                /\ fsWrite4' = fs
                                /\ network' = netWrite5'
                                /\ fs' = fsWrite4'
                                /\ pc' = [pc EXCEPT ![self] = "failLabel"]
                     /\ UNCHANGED << fd, netRead, netWrite, netRead0,
                                     netWrite0, fsRead, fsWrite, fsWrite0,
                                     fsWrite1, fsWrite2, fsWrite3, fdRead,
                                     netWrite1, netWrite2, netWrite3,
                                     netWrite4, fdWrite, fdRead0, netWrite6,
                                     netWrite7, netWrite8, netRead1, netWrite9,
                                     netWrite10, netWrite11, netWrite12, msg,
                                     respBody, respTyp, idx_, repMsg, rep,
                                     resp_, req, resp, idx, body >>

rcvMsg(self) == /\ pc[self] = "rcvMsg"
                /\ \/ /\ (Len(network[<<self, GET_REQ>>])) > (0)
                      /\ LET msg0 == Head(network[<<self, GET_REQ>>]) IN
                           /\ netWrite' = [network EXCEPT ![<<self, GET_REQ>>] = Tail(network[<<self, GET_REQ>>])]
                           /\ netRead' = msg0
                      /\ msg' = [msg EXCEPT ![self] = netRead']
                      /\ netWrite0' = netWrite'
                      /\ UNCHANGED netRead0
                   \/ /\ (Len(network[<<self, PUT_REQ>>])) > (0)
                      /\ LET msg1 == Head(network[<<self, PUT_REQ>>]) IN
                           /\ netWrite' = [network EXCEPT ![<<self, PUT_REQ>>] = Tail(network[<<self, PUT_REQ>>])]
                           /\ netRead0' = msg1
                      /\ msg' = [msg EXCEPT ![self] = netRead0']
                      /\ netWrite0' = netWrite'
                      /\ UNCHANGED netRead
                /\ Assert(((msg'[self]).to) = (self),
                          "Failure of assertion at line 274, column 21.")
                /\ IF ((msg'[self]).srcTyp) = (CLIENT_SRC)
                      THEN /\ network' = netWrite0'
                           /\ pc' = [pc EXCEPT ![self] = "handlePrimary"]
                      ELSE /\ IF ((msg'[self]).srcTyp) = (PRIMARY_SRC)
                                 THEN /\ network' = netWrite0'
                                      /\ pc' = [pc EXCEPT ![self] = "handleBackup"]
                                 ELSE /\ network' = netWrite0'
                                      /\ pc' = [pc EXCEPT ![self] = "handleBackup"]
                /\ UNCHANGED << fd, fs, fsRead, fsWrite, fsWrite0, fsWrite1,
                                fsWrite2, fsWrite3, fdRead, netWrite1,
                                netWrite2, netWrite3, netWrite4, netWrite5,
                                fsWrite4, fdWrite, fdRead0, netWrite6,
                                netWrite7, netWrite8, netRead1, netWrite9,
                                netWrite10, netWrite11, netWrite12, respBody,
                                respTyp, idx_, repMsg, rep, resp_, req, resp,
                                idx, body >>

handleBackup(self) == /\ pc[self] = "handleBackup"
                      /\ IF ((msg[self]).typ) = (GET_REQ)
                            THEN /\ fsRead' = fs[<<self, ((msg[self]).body).key>>]
                                 /\ respBody' = [respBody EXCEPT ![self] = fsRead']
                                 /\ respTyp' = [respTyp EXCEPT ![self] = GET_RESP]
                                 /\ fsWrite1' = fs
                                 /\ UNCHANGED << fsWrite, fsWrite0 >>
                            ELSE /\ IF ((msg[self]).typ) = (PUT_REQ)
                                       THEN /\ fsWrite' = [fs EXCEPT ![<<self, ((msg[self]).body).key>>] = ((msg[self]).body).value]
                                            /\ respBody' = [respBody EXCEPT ![self] = ACK_MSG]
                                            /\ respTyp' = [respTyp EXCEPT ![self] = PUT_RESP]
                                            /\ fsWrite0' = fsWrite'
                                            /\ fsWrite1' = fsWrite0'
                                       ELSE /\ fsWrite0' = fs
                                            /\ fsWrite1' = fsWrite0'
                                            /\ UNCHANGED << fsWrite, respBody,
                                                            respTyp >>
                                 /\ UNCHANGED fsRead
                      /\ resp_' = [resp_ EXCEPT ![self] = [from |-> self, to |-> (msg[self]).from, body |-> respBody'[self], srcTyp |-> BACKUP_SRC, typ |-> respTyp'[self], id |-> (msg[self]).id]]
                      /\ (Len(network[<<(resp_'[self]).to, (resp_'[self]).typ>>])) < (BUFFER_SIZE)
                      /\ netWrite' = [network EXCEPT ![<<(resp_'[self]).to, (resp_'[self]).typ>>] = Append(network[<<(resp_'[self]).to, (resp_'[self]).typ>>], resp_'[self])]
                      /\ network' = netWrite'
                      /\ fs' = fsWrite1'
                      /\ pc' = [pc EXCEPT ![self] = "replicaLoop"]
                      /\ UNCHANGED << fd, netRead, netRead0, netWrite0,
                                      fsWrite2, fsWrite3, fdRead, netWrite1,
                                      netWrite2, netWrite3, netWrite4,
                                      netWrite5, fsWrite4, fdWrite, fdRead0,
                                      netWrite6, netWrite7, netWrite8,
                                      netRead1, netWrite9, netWrite10,
                                      netWrite11, netWrite12, msg, idx_,
                                      repMsg, rep, req, resp, idx, body >>

handlePrimary(self) == /\ pc[self] = "handlePrimary"
                       /\ IF ((msg[self]).typ) = (GET_REQ)
                             THEN /\ fsRead' = fs[<<self, ((msg[self]).body).key>>]
                                  /\ respBody' = [respBody EXCEPT ![self] = fsRead']
                                  /\ respTyp' = [respTyp EXCEPT ![self] = GET_RESP]
                                  /\ fsWrite3' = fs
                                  /\ fs' = fsWrite3'
                                  /\ pc' = [pc EXCEPT ![self] = "sndResp"]
                                  /\ UNCHANGED << fsWrite, fsWrite2 >>
                             ELSE /\ IF ((msg[self]).typ) = (PUT_REQ)
                                        THEN /\ fsWrite' = [fs EXCEPT ![<<self, ((msg[self]).body).key>>] = ((msg[self]).body).value]
                                             /\ respBody' = [respBody EXCEPT ![self] = ACK_MSG]
                                             /\ respTyp' = [respTyp EXCEPT ![self] = PUT_RESP]
                                             /\ fsWrite2' = fsWrite'
                                             /\ fsWrite3' = fsWrite2'
                                             /\ fs' = fsWrite3'
                                             /\ pc' = [pc EXCEPT ![self] = "sndReplicaMsg"]
                                        ELSE /\ fsWrite2' = fs
                                             /\ fsWrite3' = fsWrite2'
                                             /\ fs' = fsWrite3'
                                             /\ pc' = [pc EXCEPT ![self] = "sndReplicaMsg"]
                                             /\ UNCHANGED << fsWrite, respBody,
                                                             respTyp >>
                                  /\ UNCHANGED fsRead
                       /\ UNCHANGED << network, fd, netRead, netWrite,
                                       netRead0, netWrite0, fsWrite0, fsWrite1,
                                       fdRead, netWrite1, netWrite2, netWrite3,
                                       netWrite4, netWrite5, fsWrite4, fdWrite,
                                       fdRead0, netWrite6, netWrite7,
                                       netWrite8, netRead1, netWrite9,
                                       netWrite10, netWrite11, netWrite12, msg,
                                       idx_, repMsg, rep, resp_, req, resp,
                                       idx, body >>

sndReplicaMsg(self) == /\ pc[self] = "sndReplicaMsg"
                       /\ idx_' = [idx_ EXCEPT ![self] = 1]
                       /\ pc' = [pc EXCEPT ![self] = "sndMsgLoop"]
                       /\ UNCHANGED << network, fd, fs, netRead, netWrite,
                                       netRead0, netWrite0, fsRead, fsWrite,
                                       fsWrite0, fsWrite1, fsWrite2, fsWrite3,
                                       fdRead, netWrite1, netWrite2, netWrite3,
                                       netWrite4, netWrite5, fsWrite4, fdWrite,
                                       fdRead0, netWrite6, netWrite7,
                                       netWrite8, netRead1, netWrite9,
                                       netWrite10, netWrite11, netWrite12, msg,
                                       respBody, respTyp, repMsg, rep, resp_,
                                       req, resp, idx, body >>

sndMsgLoop(self) == /\ pc[self] = "sndMsgLoop"
                    /\ IF (idx_[self]) <= (NUM_REPLICAS)
                          THEN /\ pc' = [pc EXCEPT ![self] = "sndMsg"]
                               /\ UNCHANGED << network, netWrite2 >>
                          ELSE /\ netWrite2' = network
                               /\ network' = netWrite2'
                               /\ pc' = [pc EXCEPT ![self] = "rcvReplicaMsg"]
                    /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                    netWrite0, fsRead, fsWrite, fsWrite0,
                                    fsWrite1, fsWrite2, fsWrite3, fdRead,
                                    netWrite1, netWrite3, netWrite4, netWrite5,
                                    fsWrite4, fdWrite, fdRead0, netWrite6,
                                    netWrite7, netWrite8, netRead1, netWrite9,
                                    netWrite10, netWrite11, netWrite12, msg,
                                    respBody, respTyp, idx_, repMsg, rep,
                                    resp_, req, resp, idx, body >>

sndMsg(self) == /\ pc[self] = "sndMsg"
                /\ fdRead' = fd[idx_[self]]
                /\ IF ((fdRead') = (TRUE)) /\ ((idx_[self]) # (self))
                      THEN /\ repMsg' = [repMsg EXCEPT ![self] = [from |-> self, to |-> idx_[self], body |-> (msg[self]).body, srcTyp |-> PRIMARY_SRC, typ |-> PUT_REQ, id |-> (msg[self]).id]]
                           /\ (Len(network[<<idx_[self], PUT_REQ>>])) < (BUFFER_SIZE)
                           /\ netWrite' = [network EXCEPT ![<<idx_[self], PUT_REQ>>] = Append(network[<<idx_[self], PUT_REQ>>], repMsg'[self])]
                           /\ netWrite1' = netWrite'
                      ELSE /\ netWrite1' = network
                           /\ UNCHANGED << netWrite, repMsg >>
                /\ idx_' = [idx_ EXCEPT ![self] = (idx_[self]) + (1)]
                /\ network' = netWrite1'
                /\ pc' = [pc EXCEPT ![self] = "sndMsgLoop"]
                /\ UNCHANGED << fd, fs, netRead, netRead0, netWrite0, fsRead,
                                fsWrite, fsWrite0, fsWrite1, fsWrite2,
                                fsWrite3, netWrite2, netWrite3, netWrite4,
                                netWrite5, fsWrite4, fdWrite, fdRead0,
                                netWrite6, netWrite7, netWrite8, netRead1,
                                netWrite9, netWrite10, netWrite11, netWrite12,
                                msg, respBody, respTyp, rep, resp_, req, resp,
                                idx, body >>

rcvReplicaMsg(self) == /\ pc[self] = "rcvReplicaMsg"
                       /\ idx_' = [idx_ EXCEPT ![self] = 1]
                       /\ pc' = [pc EXCEPT ![self] = "rcvMsgLoop"]
                       /\ UNCHANGED << network, fd, fs, netRead, netWrite,
                                       netRead0, netWrite0, fsRead, fsWrite,
                                       fsWrite0, fsWrite1, fsWrite2, fsWrite3,
                                       fdRead, netWrite1, netWrite2, netWrite3,
                                       netWrite4, netWrite5, fsWrite4, fdWrite,
                                       fdRead0, netWrite6, netWrite7,
                                       netWrite8, netRead1, netWrite9,
                                       netWrite10, netWrite11, netWrite12, msg,
                                       respBody, respTyp, repMsg, rep, resp_,
                                       req, resp, idx, body >>

rcvMsgLoop(self) == /\ pc[self] = "rcvMsgLoop"
                    /\ IF (idx_[self]) <= (NUM_REPLICAS)
                          THEN /\ pc' = [pc EXCEPT ![self] = "rcvMsgFromReplica"]
                               /\ UNCHANGED << network, netWrite4 >>
                          ELSE /\ netWrite4' = network
                               /\ network' = netWrite4'
                               /\ pc' = [pc EXCEPT ![self] = "sndResp"]
                    /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                    netWrite0, fsRead, fsWrite, fsWrite0,
                                    fsWrite1, fsWrite2, fsWrite3, fdRead,
                                    netWrite1, netWrite2, netWrite3, netWrite5,
                                    fsWrite4, fdWrite, fdRead0, netWrite6,
                                    netWrite7, netWrite8, netRead1, netWrite9,
                                    netWrite10, netWrite11, netWrite12, msg,
                                    respBody, respTyp, idx_, repMsg, rep,
                                    resp_, req, resp, idx, body >>

rcvMsgFromReplica(self) == /\ pc[self] = "rcvMsgFromReplica"
                           /\ fdRead' = fd[idx_[self]]
                           /\ IF ((fdRead') = (TRUE)) /\ ((idx_[self]) # (self))
                                 THEN /\ (Len(network[<<self, PUT_RESP>>])) > (0)
                                      /\ LET msg2 == Head(network[<<self, PUT_RESP>>]) IN
                                           /\ netWrite' = [network EXCEPT ![<<self, PUT_RESP>>] = Tail(network[<<self, PUT_RESP>>])]
                                           /\ netRead' = msg2
                                      /\ rep' = [rep EXCEPT ![self] = netRead']
                                      /\ Assert(((rep'[self]).from) = (idx_[self]),
                                                "Failure of assertion at line 374, column 33.")
                                      /\ Assert(((rep'[self]).to) = (self),
                                                "Failure of assertion at line 375, column 33.")
                                      /\ Assert(((rep'[self]).body) = (ACK_MSG),
                                                "Failure of assertion at line 376, column 33.")
                                      /\ Assert(((rep'[self]).srcTyp) = (BACKUP_SRC),
                                                "Failure of assertion at line 377, column 33.")
                                      /\ Assert(((rep'[self]).typ) = (PUT_RESP),
                                                "Failure of assertion at line 378, column 33.")
                                      /\ Assert(((rep'[self]).id) = ((msg[self]).id),
                                                "Failure of assertion at line 379, column 33.")
                                      /\ netWrite3' = netWrite'
                                 ELSE /\ netWrite3' = network
                                      /\ UNCHANGED << netRead, netWrite, rep >>
                           /\ idx_' = [idx_ EXCEPT ![self] = (idx_[self]) + (1)]
                           /\ network' = netWrite3'
                           /\ pc' = [pc EXCEPT ![self] = "rcvMsgLoop"]
                           /\ UNCHANGED << fd, fs, netRead0, netWrite0, fsRead,
                                           fsWrite, fsWrite0, fsWrite1,
                                           fsWrite2, fsWrite3, netWrite1,
                                           netWrite2, netWrite4, netWrite5,
                                           fsWrite4, fdWrite, fdRead0,
                                           netWrite6, netWrite7, netWrite8,
                                           netRead1, netWrite9, netWrite10,
                                           netWrite11, netWrite12, msg,
                                           respBody, respTyp, repMsg, resp_,
                                           req, resp, idx, body >>

sndResp(self) == /\ pc[self] = "sndResp"
                 /\ resp_' = [resp_ EXCEPT ![self] = [from |-> self, to |-> (msg[self]).from, body |-> respBody[self], srcTyp |-> PRIMARY_SRC, typ |-> respTyp[self], id |-> (msg[self]).id]]
                 /\ (Len(network[<<(resp_'[self]).to, (resp_'[self]).typ>>])) < (BUFFER_SIZE)
                 /\ netWrite' = [network EXCEPT ![<<(resp_'[self]).to, (resp_'[self]).typ>>] = Append(network[<<(resp_'[self]).to, (resp_'[self]).typ>>], resp_'[self])]
                 /\ network' = netWrite'
                 /\ pc' = [pc EXCEPT ![self] = "replicaLoop"]
                 /\ UNCHANGED << fd, fs, netRead, netRead0, netWrite0, fsRead,
                                 fsWrite, fsWrite0, fsWrite1, fsWrite2,
                                 fsWrite3, fdRead, netWrite1, netWrite2,
                                 netWrite3, netWrite4, netWrite5, fsWrite4,
                                 fdWrite, fdRead0, netWrite6, netWrite7,
                                 netWrite8, netRead1, netWrite9, netWrite10,
                                 netWrite11, netWrite12, msg, respBody,
                                 respTyp, idx_, repMsg, rep, req, resp, idx,
                                 body >>

failLabel(self) == /\ pc[self] = "failLabel"
                   /\ fdWrite' = [fd EXCEPT ![self] = FALSE]
                   /\ fd' = fdWrite'
                   /\ pc' = [pc EXCEPT ![self] = "Done"]
                   /\ UNCHANGED << network, fs, netRead, netWrite, netRead0,
                                   netWrite0, fsRead, fsWrite, fsWrite0,
                                   fsWrite1, fsWrite2, fsWrite3, fdRead,
                                   netWrite1, netWrite2, netWrite3, netWrite4,
                                   netWrite5, fsWrite4, fdRead0, netWrite6,
                                   netWrite7, netWrite8, netRead1, netWrite9,
                                   netWrite10, netWrite11, netWrite12, msg,
                                   respBody, respTyp, idx_, repMsg, rep, resp_,
                                   req, resp, idx, body >>

Replica(self) == replicaLoop(self) \/ rcvMsg(self) \/ handleBackup(self)
                    \/ handlePrimary(self) \/ sndReplicaMsg(self)
                    \/ sndMsgLoop(self) \/ sndMsg(self)
                    \/ rcvReplicaMsg(self) \/ rcvMsgLoop(self)
                    \/ rcvMsgFromReplica(self) \/ sndResp(self)
                    \/ failLabel(self)

sndPutReq(self) == /\ pc[self] = "sndPutReq"
                   /\ idx' = [idx EXCEPT ![self] = 1]
                   /\ pc' = [pc EXCEPT ![self] = "sndPutReqLoop"]
                   /\ UNCHANGED << network, fd, fs, netRead, netWrite,
                                   netRead0, netWrite0, fsRead, fsWrite,
                                   fsWrite0, fsWrite1, fsWrite2, fsWrite3,
                                   fdRead, netWrite1, netWrite2, netWrite3,
                                   netWrite4, netWrite5, fsWrite4, fdWrite,
                                   fdRead0, netWrite6, netWrite7, netWrite8,
                                   netRead1, netWrite9, netWrite10, netWrite11,
                                   netWrite12, msg, respBody, respTyp, idx_,
                                   repMsg, rep, resp_, req, resp, body >>

sndPutReqLoop(self) == /\ pc[self] = "sndPutReqLoop"
                       /\ IF (idx[self]) <= (NUM_REPLICAS)
                             THEN /\ pc' = [pc EXCEPT ![self] = "sndPutMsg"]
                                  /\ UNCHANGED << network, netWrite8 >>
                             ELSE /\ netWrite8' = network
                                  /\ network' = netWrite8'
                                  /\ pc' = [pc EXCEPT ![self] = "rcvPutResp"]
                       /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                       netWrite0, fsRead, fsWrite, fsWrite0,
                                       fsWrite1, fsWrite2, fsWrite3, fdRead,
                                       netWrite1, netWrite2, netWrite3,
                                       netWrite4, netWrite5, fsWrite4, fdWrite,
                                       fdRead0, netWrite6, netWrite7, netRead1,
                                       netWrite9, netWrite10, netWrite11,
                                       netWrite12, msg, respBody, respTyp,
                                       idx_, repMsg, rep, resp_, req, resp,
                                       idx, body >>

sndPutMsg(self) == /\ pc[self] = "sndPutMsg"
                   /\ fdRead0' = fd[idx[self]]
                   /\ IF (fdRead0') = (TRUE)
                         THEN /\ body' = [body EXCEPT ![self] = [key |-> KEY1, value |-> VALUE1]]
                              /\ req' = [req EXCEPT ![self] = [from |-> self, to |-> idx[self], body |-> body'[self], srcTyp |-> CLIENT_SRC, typ |-> PUT_REQ, id |-> 1]]
                              /\ (Len(network[<<(req'[self]).to, (req'[self]).typ>>])) < (BUFFER_SIZE)
                              /\ netWrite6' = [network EXCEPT ![<<(req'[self]).to, (req'[self]).typ>>] = Append(network[<<(req'[self]).to, (req'[self]).typ>>], req'[self])]
                              /\ netWrite7' = netWrite6'
                              /\ network' = netWrite7'
                              /\ pc' = [pc EXCEPT ![self] = "rcvPutResp"]
                         ELSE /\ netWrite7' = network
                              /\ network' = netWrite7'
                              /\ pc' = [pc EXCEPT ![self] = "sndPutReqLoop"]
                              /\ UNCHANGED << netWrite6, req, body >>
                   /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                   netWrite0, fsRead, fsWrite, fsWrite0,
                                   fsWrite1, fsWrite2, fsWrite3, fdRead,
                                   netWrite1, netWrite2, netWrite3, netWrite4,
                                   netWrite5, fsWrite4, fdWrite, netWrite8,
                                   netRead1, netWrite9, netWrite10, netWrite11,
                                   netWrite12, msg, respBody, respTyp, idx_,
                                   repMsg, rep, resp_, resp, idx >>

rcvPutResp(self) == /\ pc[self] = "rcvPutResp"
                    /\ fdRead0' = fd[idx[self]]
                    /\ IF (fdRead0') = (TRUE)
                          THEN /\ (Len(network[<<self, PUT_RESP>>])) > (0)
                               /\ LET msg3 == Head(network[<<self, PUT_RESP>>]) IN
                                    /\ netWrite6' = [network EXCEPT ![<<self, PUT_RESP>>] = Tail(network[<<self, PUT_RESP>>])]
                                    /\ netRead1' = msg3
                               /\ resp' = [resp EXCEPT ![self] = netRead1']
                               /\ Assert(((resp'[self]).to) = (self),
                                         "Failure of assertion at line 447, column 17.")
                               /\ Assert(((resp'[self]).body) = (ACK_MSG),
                                         "Failure of assertion at line 448, column 17.")
                               /\ Assert(((resp'[self]).srcTyp) = (PRIMARY_SRC),
                                         "Failure of assertion at line 449, column 17.")
                               /\ Assert(((resp'[self]).typ) = (PUT_RESP),
                                         "Failure of assertion at line 450, column 17.")
                               /\ Assert(((resp'[self]).id) = (1),
                                         "Failure of assertion at line 451, column 17.")
                               /\ PrintT(<<"PUT RESP: ", resp'[self]>>)
                               /\ netWrite9' = netWrite6'
                               /\ network' = netWrite9'
                               /\ pc' = [pc EXCEPT ![self] = "sndGetReq"]
                          ELSE /\ netWrite9' = network
                               /\ network' = netWrite9'
                               /\ pc' = [pc EXCEPT ![self] = "sndPutReq"]
                               /\ UNCHANGED << netWrite6, netRead1, resp >>
                    /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                    netWrite0, fsRead, fsWrite, fsWrite0,
                                    fsWrite1, fsWrite2, fsWrite3, fdRead,
                                    netWrite1, netWrite2, netWrite3, netWrite4,
                                    netWrite5, fsWrite4, fdWrite, netWrite7,
                                    netWrite8, netWrite10, netWrite11,
                                    netWrite12, msg, respBody, respTyp, idx_,
                                    repMsg, rep, resp_, req, idx, body >>

sndGetReq(self) == /\ pc[self] = "sndGetReq"
                   /\ idx' = [idx EXCEPT ![self] = 1]
                   /\ pc' = [pc EXCEPT ![self] = "sndGetReqLoop"]
                   /\ UNCHANGED << network, fd, fs, netRead, netWrite,
                                   netRead0, netWrite0, fsRead, fsWrite,
                                   fsWrite0, fsWrite1, fsWrite2, fsWrite3,
                                   fdRead, netWrite1, netWrite2, netWrite3,
                                   netWrite4, netWrite5, fsWrite4, fdWrite,
                                   fdRead0, netWrite6, netWrite7, netWrite8,
                                   netRead1, netWrite9, netWrite10, netWrite11,
                                   netWrite12, msg, respBody, respTyp, idx_,
                                   repMsg, rep, resp_, req, resp, body >>

sndGetReqLoop(self) == /\ pc[self] = "sndGetReqLoop"
                       /\ IF (idx[self]) <= (NUM_REPLICAS)
                             THEN /\ pc' = [pc EXCEPT ![self] = "sndGetMsg"]
                                  /\ UNCHANGED << network, netWrite11 >>
                             ELSE /\ netWrite11' = network
                                  /\ network' = netWrite11'
                                  /\ pc' = [pc EXCEPT ![self] = "rcvGetResp"]
                       /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                       netWrite0, fsRead, fsWrite, fsWrite0,
                                       fsWrite1, fsWrite2, fsWrite3, fdRead,
                                       netWrite1, netWrite2, netWrite3,
                                       netWrite4, netWrite5, fsWrite4, fdWrite,
                                       fdRead0, netWrite6, netWrite7,
                                       netWrite8, netRead1, netWrite9,
                                       netWrite10, netWrite12, msg, respBody,
                                       respTyp, idx_, repMsg, rep, resp_, req,
                                       resp, idx, body >>

sndGetMsg(self) == /\ pc[self] = "sndGetMsg"
                   /\ fdRead0' = fd[idx[self]]
                   /\ IF (fdRead0') = (TRUE)
                         THEN /\ body' = [body EXCEPT ![self] = [key |-> KEY1]]
                              /\ req' = [req EXCEPT ![self] = [from |-> self, to |-> idx[self], body |-> body'[self], srcTyp |-> CLIENT_SRC, typ |-> GET_REQ, id |-> 2]]
                              /\ (Len(network[<<(req'[self]).to, (req'[self]).typ>>])) < (BUFFER_SIZE)
                              /\ netWrite6' = [network EXCEPT ![<<(req'[self]).to, (req'[self]).typ>>] = Append(network[<<(req'[self]).to, (req'[self]).typ>>], req'[self])]
                              /\ netWrite10' = netWrite6'
                              /\ network' = netWrite10'
                              /\ pc' = [pc EXCEPT ![self] = "rcvGetResp"]
                         ELSE /\ netWrite10' = network
                              /\ network' = netWrite10'
                              /\ pc' = [pc EXCEPT ![self] = "sndGetReqLoop"]
                              /\ UNCHANGED << netWrite6, req, body >>
                   /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                   netWrite0, fsRead, fsWrite, fsWrite0,
                                   fsWrite1, fsWrite2, fsWrite3, fdRead,
                                   netWrite1, netWrite2, netWrite3, netWrite4,
                                   netWrite5, fsWrite4, fdWrite, netWrite7,
                                   netWrite8, netRead1, netWrite9, netWrite11,
                                   netWrite12, msg, respBody, respTyp, idx_,
                                   repMsg, rep, resp_, resp, idx >>

rcvGetResp(self) == /\ pc[self] = "rcvGetResp"
                    /\ fdRead0' = fd[idx[self]]
                    /\ IF (fdRead0') = (TRUE)
                          THEN /\ (Len(network[<<self, GET_RESP>>])) > (0)
                               /\ LET msg4 == Head(network[<<self, GET_RESP>>]) IN
                                    /\ netWrite6' = [network EXCEPT ![<<self, GET_RESP>>] = Tail(network[<<self, GET_RESP>>])]
                                    /\ netRead1' = msg4
                               /\ resp' = [resp EXCEPT ![self] = netRead1']
                               /\ Assert(((resp'[self]).to) = (self),
                                         "Failure of assertion at line 493, column 17.")
                               /\ Assert(((resp'[self]).body) = (VALUE1),
                                         "Failure of assertion at line 494, column 17.")
                               /\ Assert(((resp'[self]).typ) = (GET_RESP),
                                         "Failure of assertion at line 495, column 17.")
                               /\ Assert(((resp'[self]).id) = (2),
                                         "Failure of assertion at line 496, column 17.")
                               /\ PrintT(<<"GET RESP: ", resp'[self]>>)
                               /\ netWrite12' = netWrite6'
                               /\ network' = netWrite12'
                               /\ pc' = [pc EXCEPT ![self] = "Done"]
                          ELSE /\ netWrite12' = network
                               /\ network' = netWrite12'
                               /\ pc' = [pc EXCEPT ![self] = "sndGetReq"]
                               /\ UNCHANGED << netWrite6, netRead1, resp >>
                    /\ UNCHANGED << fd, fs, netRead, netWrite, netRead0,
                                    netWrite0, fsRead, fsWrite, fsWrite0,
                                    fsWrite1, fsWrite2, fsWrite3, fdRead,
                                    netWrite1, netWrite2, netWrite3, netWrite4,
                                    netWrite5, fsWrite4, fdWrite, netWrite7,
                                    netWrite8, netWrite9, netWrite10,
                                    netWrite11, msg, respBody, respTyp, idx_,
                                    repMsg, rep, resp_, req, idx, body >>

Client(self) == sndPutReq(self) \/ sndPutReqLoop(self) \/ sndPutMsg(self)
                   \/ rcvPutResp(self) \/ sndGetReq(self)
                   \/ sndGetReqLoop(self) \/ sndGetMsg(self)
                   \/ rcvGetResp(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in (1) .. (NUM_REPLICAS): Replica(self))
           \/ (\E self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)): Client(self))
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in (1) .. (NUM_REPLICAS) : WF_vars(Replica(self))
        /\ \A self \in ((NUM_REPLICAS) + (1)) .. ((NUM_REPLICAS) + (NUM_CLIENTS)) : WF_vars(Client(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION


=============================================================================
\* Modification History
\* Last modified Thu Apr 29 00:22:21 PDT 2021 by shayan
\* Created Sat Apr 03 22:41:02 PDT 2021 by shayan
