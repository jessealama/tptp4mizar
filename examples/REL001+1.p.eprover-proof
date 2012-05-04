fof(1,axiom,(
    ! [X1,X2] : join(X1,X2) = join(X2,X1) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',maddux1_join_commutativity)).

fof(2,axiom,(
    ! [X1,X2,X3] : join(X1,join(X2,X3)) = join(join(X1,X2),X3) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',maddux2_join_associativity)).

fof(3,axiom,(
    ! [X1,X2] : X1 = join(complement(join(complement(X1),complement(X2))),complement(join(complement(X1),X2))) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',maddux3_a_kind_of_de_Morgan)).

fof(4,axiom,(
    ! [X1,X2] : meet(X1,X2) = complement(join(complement(X1),complement(X2))) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',maddux4_definiton_of_meet)).

fof(6,axiom,(
    ! [X1] : composition(X1,one) = X1 ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',composition_identity)).

fof(8,axiom,(
    ! [X1] : converse(converse(X1)) = X1 ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',converse_idempotence)).

fof(10,axiom,(
    ! [X1,X2] : converse(composition(X1,X2)) = composition(converse(X2),converse(X1)) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',converse_multiplicativity)).

fof(11,axiom,(
    ! [X1,X2] : join(composition(converse(X1),complement(composition(X1,X2))),complement(X2)) = complement(X2) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',converse_cancellativity)).

fof(12,axiom,(
    ! [X1] : top = join(X1,complement(X1)) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',def_top)).

fof(13,axiom,(
    ! [X1] : zero = meet(X1,complement(X1)) ),
    file('/Users/alama/sources/TPTP-v5.3.0/Axioms/REL001+0.ax',def_zero)).

fof(14,conjecture,(
    ! [X1] : join(zero,X1) = X1 ),
    file('REL001+1.p',goals)).

fof(15,negated_conjecture,(
    ~ ! [X1] : join(zero,X1) = X1 ),
    inference(assume_negation,[status(cth)],[14])).

fof(16,plain,(
    ! [X3,X4] : join(X3,X4) = join(X4,X3) ),
    inference(variable_rename,[status(thm)],[1])).

fof(17,plain,(
    ! [X1,X2] : join(X1,X2) = join(X2,X1) ),
    inference(split_conjunct,[status(thm)],[16])).

fof(18,plain,(
    ! [X4,X5,X6] : join(X4,join(X5,X6)) = join(join(X4,X5),X6) ),
    inference(variable_rename,[status(thm)],[2])).

fof(19,plain,(
    ! [X1,X2,X3] : join(X1,join(X2,X3)) = join(join(X1,X2),X3) ),
    inference(split_conjunct,[status(thm)],[18])).

fof(20,plain,(
    ! [X3,X4] : X3 = join(complement(join(complement(X3),complement(X4))),complement(join(complement(X3),X4))) ),
    inference(variable_rename,[status(thm)],[3])).

fof(21,plain,(
    ! [X1,X2] : X1 = join(complement(join(complement(X1),complement(X2))),complement(join(complement(X1),X2))) ),
    inference(split_conjunct,[status(thm)],[20])).

fof(22,plain,(
    ! [X3,X4] : meet(X3,X4) = complement(join(complement(X3),complement(X4))) ),
    inference(variable_rename,[status(thm)],[4])).

fof(23,plain,(
    ! [X1,X2] : meet(X1,X2) = complement(join(complement(X1),complement(X2))) ),
    inference(split_conjunct,[status(thm)],[22])).

fof(26,plain,(
    ! [X2] : composition(X2,one) = X2 ),
    inference(variable_rename,[status(thm)],[6])).

fof(27,plain,(
    ! [X1] : composition(X1,one) = X1 ),
    inference(split_conjunct,[status(thm)],[26])).

fof(30,plain,(
    ! [X2] : converse(converse(X2)) = X2 ),
    inference(variable_rename,[status(thm)],[8])).

fof(31,plain,(
    ! [X1] : converse(converse(X1)) = X1 ),
    inference(split_conjunct,[status(thm)],[30])).

fof(34,plain,(
    ! [X3,X4] : converse(composition(X3,X4)) = composition(converse(X4),converse(X3)) ),
    inference(variable_rename,[status(thm)],[10])).

fof(35,plain,(
    ! [X1,X2] : converse(composition(X1,X2)) = composition(converse(X2),converse(X1)) ),
    inference(split_conjunct,[status(thm)],[34])).

fof(36,plain,(
    ! [X3,X4] : join(composition(converse(X3),complement(composition(X3,X4))),complement(X4)) = complement(X4) ),
    inference(variable_rename,[status(thm)],[11])).

fof(37,plain,(
    ! [X1,X2] : join(composition(converse(X1),complement(composition(X1,X2))),complement(X2)) = complement(X2) ),
    inference(split_conjunct,[status(thm)],[36])).

fof(38,plain,(
    ! [X2] : top = join(X2,complement(X2)) ),
    inference(variable_rename,[status(thm)],[12])).

fof(39,plain,(
    ! [X1] : top = join(X1,complement(X1)) ),
    inference(split_conjunct,[status(thm)],[38])).

fof(40,plain,(
    ! [X2] : zero = meet(X2,complement(X2)) ),
    inference(variable_rename,[status(thm)],[13])).

fof(41,plain,(
    ! [X1] : zero = meet(X1,complement(X1)) ),
    inference(split_conjunct,[status(thm)],[40])).

fof(42,negated_conjecture,(
    ? [X1] : join(zero,X1) != X1 ),
    inference(fof_nnf,[status(thm)],[15])).

fof(43,negated_conjecture,(
    ? [X2] : join(zero,X2) != X2 ),
    inference(variable_rename,[status(thm)],[42])).

fof(44,negated_conjecture,(
    join(zero,esk1_0) != esk1_0 ),
    inference(skolemize,[status(esa)],[43])).

fof(45,negated_conjecture,(
    join(zero,esk1_0) != esk1_0 ),
    inference(split_conjunct,[status(thm)],[44])).

fof(46,plain,(
    ! [X1] : complement(join(complement(X1),complement(complement(X1)))) = zero ),
    inference(rw,[status(thm)],[41,23,theory(equality)]),
    [unfolding]).

fof(47,plain,(
    complement(top) = zero ),
    inference(rw,[status(thm)],[46,39,theory(equality)])).

fof(48,plain,(
    ! [X2,X1] : join(complement(X2),composition(converse(X1),complement(composition(X1,X2)))) = complement(X2) ),
    inference(rw,[status(thm)],[37,17,theory(equality)])).

fof(49,plain,(
    ! [X1,X2] : join(complement(join(complement(X1),X2)),complement(join(complement(X1),complement(X2)))) = X1 ),
    inference(rw,[status(thm)],[21,17,theory(equality)])).

fof(53,plain,(
    ! [X1,X2] : composition(converse(X1),X2) = converse(composition(converse(X2),X1)) ),
    inference(spm,[status(thm)],[35,31,theory(equality)])).

fof(193,plain,(
    ! [X1] : converse(converse(X1)) = composition(converse(one),X1) ),
    inference(spm,[status(thm)],[53,27,theory(equality)])).

fof(201,plain,(
    ! [X1] : X1 = composition(converse(one),X1) ),
    inference(rw,[status(thm)],[193,31,theory(equality)])).

fof(204,plain,(
    one = converse(one) ),
    inference(spm,[status(thm)],[27,201,theory(equality)])).

fof(225,plain,(
    ! [X1] : composition(one,X1) = X1 ),
    inference(rw,[status(thm)],[201,204,theory(equality)])).

fof(232,plain,(
    ! [X1] : join(complement(X1),composition(converse(one),complement(X1))) = complement(X1) ),
    inference(spm,[status(thm)],[48,225,theory(equality)])).

fof(235,plain,(
    ! [X1] : join(complement(X1),complement(X1)) = complement(X1) ),
    inference(rw,[status(thm)],[inference(rw,[status(thm)],[232,204,theory(equality)]),225,theory(equality)])).

fof(325,plain,(
    ! [X1] : join(complement(complement(X1)),complement(join(complement(X1),complement(complement(X1))))) = X1 ),
    inference(spm,[status(thm)],[49,235,theory(equality)])).

fof(327,plain,(
    join(zero,zero) = zero ),
    inference(spm,[status(thm)],[235,47,theory(equality)])).

fof(331,plain,(
    ! [X1] : join(complement(complement(X1)),zero) = X1 ),
    inference(rw,[status(thm)],[inference(rw,[status(thm)],[325,39,theory(equality)]),47,theory(equality)])).

fof(333,plain,(
    ! [X1] : join(zero,X1) = join(zero,join(zero,X1)) ),
    inference(spm,[status(thm)],[19,327,theory(equality)])).

fof(467,plain,(
    ! [X1] : join(zero,complement(complement(X1))) = X1 ),
    inference(rw,[status(thm)],[331,17,theory(equality)])).

fof(470,plain,(
    ! [X1] : join(zero,X1) = X1 ),
    inference(spm,[status(thm)],[333,467,theory(equality)])).

fof(488,negated_conjecture,(
    $false ),
    inference(rw,[status(thm)],[45,470,theory(equality)])).

fof(489,negated_conjecture,(
    $false ),
    inference(cn,[status(thm)],[488,theory(equality)])).

fof(490,negated_conjecture,(
    $false ),
    489,
    [proof]).
