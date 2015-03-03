(** * SystemFProp: Properties of System F *)

Require Export SystemF.
Require Export Coq.Logic.Decidable.

Module SYSTEMFPROP.
Import SYSTEMF.

(** In this chapter, we develop the fundamental theory of the Simply
    Typed Lambda Calculus -- in particular, the type safety
    theorem. *)

(* ###################################################################### *)
(** * Canonical Forms *)

Lemma canonical_forms_fun : forall t T1 T2,
  empty |- t \in (TArrow T1 T2) ->
  value t ->
  exists x u, t = tabs x T1 u.
Proof.
  intros t T1 T2 HT HVal.
  inversion HVal; intros; subst; try inversion HT; subst; auto.
  exists x. exists t0.  auto.
Qed.

Lemma canonical_forms_tabs : forall t T,
  empty |- t \in TUniv T ->
  value t ->
  exists t', t = ttabs t'.
Proof.
  intros. inversion H0; subst.
  inversion H; subst.
  exists t0. reflexivity.
Qed.

(* ###################################################################### *)
(** * Progress *)

(** As before, the _progress_ theorem tells us that closed, well-typed
    terms are not stuck: either a well-typed term is a value, or it
    can take an evaluation step.  The proof is a relatively
    straightforward extension of the progress proof we saw in the
    [Types] chapter. *)

Theorem progress : forall t T, 
     empty |- t \in T ->
     value t \/ exists t', t ==> t'.

(** _Proof_: by induction on the derivation of [|- t \in T].

    - The last rule of the derivation cannot be [T_Var], since a
      variable is never well typed in an empty context.

    - The [T_True], [T_False], and [T_Abs] cases are trivial, since in
      each of these cases we know immediately that [t] is a value.

    - If the last rule of the derivation was [T_App], then [t = t1
      t2], and we know that [t1] and [t2] are also well typed in the
      empty context; in particular, there exists a type [T2] such that
      [|- t1 \in T2 -> T] and [|- t2 \in T2].  By the induction
      hypothesis, either [t1] is a value or it can take an evaluation
      step.

        - If [t1] is a value, we now consider [t2], which by the other
          induction hypothesis must also either be a value or take an
          evaluation step.

            - Suppose [t2] is a value.  Since [t1] is a value with an
              arrow type, it must be a lambda abstraction; hence [t1
              t2] can take a step by [ST_AppAbs].

            - Otherwise, [t2] can take a step, and hence so can [t1
              t2] by [ST_App2].

        - If [t1] can take a step, then so can [t1 t2] by [ST_App1].

    - If the last rule of the derivation was [T_If], then [t = if t1
      then t2 else t3], where [t1] has type [Bool].  By the IH, [t1]
      either is a value or takes a step.

        - If [t1] is a value, then since it has type [Bool] it must be
          either [true] or [false].  If it is [true], then [t] steps
          to [t2]; otherwise it steps to [t3].

        - Otherwise, [t1] takes a step, and therefore so does [t] (by
          [ST_If]).
*)

Proof with eauto.
  intros t T Ht.
  remember (@empty) as Gamma.
  has_type_cases (induction Ht) Case; subst Gamma...
  Case "T_Var".
    (* contradictory: variables cannot be typed in an 
       empty context *)
    inversion H0. 

  Case "T_App". 
    (* [t] = [t1 t2].  Proceed by cases on whether [t1] is a 
       value or steps... *)
    right. destruct IHHt1...
    SCase "t1 is a value".
      destruct IHHt2...
      SSCase "t2 is also a value".
        assert (exists x0 t0, t1 = tabs x0 T11 t0).
        eapply canonical_forms_fun; eauto.
        destruct H1 as [x0 [t0 Heq]]. subst.
        exists ([x0:=t2]t0)...

      SSCase "t2 steps".
        inversion H0 as [t2' Hstp]. exists (tapp t1 t2')...

    SCase "t1 steps".
      inversion H as [t1' Hstp]. exists (tapp t1' t2)...
      
  Case "T_TApp".
    right. destruct IHHt...    
    SCase "t1 is a value".
      assert (exists t0, t1 = ttabs t0).
      eapply canonical_forms_tabs; eauto.
      destruct H0; subst.
      exists ([0 := T2] x)...
    SCase "t1 also steps".
      inversion H. exists (ttapp x T2)...
Qed.

(* [] *)

(* ###################################################################### *)
(** * Preservation *)

(** The other half of the type soundness property is the preservation
    of types during reduction.  For this, we need to develop some
    technical machinery for reasoning about variables and
    substitution.  Working from top to bottom (the high-level property
    we are actually interested in to the lowest-level technical lemmas
    that are needed by various cases of the more interesting proofs),
    the story goes like this:

      - The _preservation theorem_ is proved by induction on a typing
        derivation, pretty much as we did in the [Types] chapter.  The
        one case that is significantly different is the one for the
        [ST_AppAbs] rule, which is defined using the substitution
        operation.  To see that this step preserves typing, we need to
        know that the substitution itself does.  So we prove a...

      - _substitution lemma_, stating that substituting a (closed)
        term [s] for a variable [x] in a term [t] preserves the type
        of [t].  The proof goes by induction on the form of [t] and
        requires looking at all the different cases in the definition
        of substitition.  This time, the tricky cases are the ones for
        variables and for function abstractions.  In both cases, we
        discover that we need to take a term [s] that has been shown
        to be well-typed in some context [Gamma] and consider the same
        term [s] in a slightly different context [Gamma'].  For this
        we prove a...

      - _context invariance_ lemma, showing that typing is preserved
        under "inessential changes" to the context [Gamma] -- in
        particular, changes that do not affect any of the free
        variables of the term.  For this, we need a careful definition
        of

      - the _free variables_ of a term -- i.e., the variables occuring
        in the term that are not in the scope of a function
        abstraction that binds them.
*)

(* ###################################################################### *)
(** ** Free Occurrences *)

(** A variable [x] _appears free in_ a term _t_ if [t] contains some
    occurrence of [x] that is not under an abstraction labeled [x].  For example: 
      - [y] appears free, but [x] does not, in [\x:T->U. x y] 
      - both [x] and [y] appear free in [(\x:T->U. x y) x] 
      - no variables appear free in [\x:T->U. \y:T. x y]  *)

Inductive term_appears_free_in_term : id -> tm -> Prop :=
  | afi_var : forall x,
      term_appears_free_in_term x (tvar x)
  | afi_app1 : forall x t1 t2,
      term_appears_free_in_term x t1 -> term_appears_free_in_term x (tapp t1 t2)
  | afi_app2 : forall x t1 t2,
      term_appears_free_in_term x t2 -> term_appears_free_in_term x (tapp t1 t2)
  | afi_abs : forall x y T11 t12,
      y <> x ->
      term_appears_free_in_term x t12 ->
      term_appears_free_in_term x (tabs y T11 t12)
  | afi_tapp : forall x t T,
      term_appears_free_in_term x t ->
      term_appears_free_in_term x (ttapp t T)
  | afi_tabs : forall x t,
      term_appears_free_in_term x t ->
      term_appears_free_in_term x (ttabs t).



Tactic Notation "afi_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "afi_var"
  | Case_aux c "afi_app1" | Case_aux c "afi_app2" 
  | Case_aux c "afi_abs" 
  | Case_aux c "afi_tapp"
  | Case_aux c "afi_tabs" ].

Hint Constructors term_appears_free_in_term.

(** A term in which no variables appear free is said to be _closed_. *)

Definition closed (t:tm) :=
  forall x, ~ term_appears_free_in_term x t.


(* ###################################################################### *)
(** ** Substitution *)

(** We first need a technical lemma connecting free variables and
    typing contexts.  If a variable [x] appears free in a term [t],
    and if we know [t] is well typed in context [Gamma], then it must
    be the case that [Gamma] assigns a type to [x]. *)

Lemma wf_empty_implies_wf : forall Gamma U,
  well_formed_type empty U ->
  well_formed_type Gamma U.
Proof.
  intros. generalize dependent Gamma. induction U; inversion H; subst.
  Case "TVar".
    inversion H1.
  Case "TArrow".
    constructor. apply IHU1. trivial.
    apply IHU2. trivial.
  Case "TUniv".
    constructor. apply IHU. admit.
Qed.    

Lemma context_subst_ge : forall Gamma Gamma' X X' T,
  X' < X ->
  subst_context T X' Gamma Gamma' ->
  get_tvar Gamma' (X - 1) = get_tvar Gamma X. 
Proof.
  intros. generalize dependent X. induction H0; intros.
    simpl. apply IHsubst_context. trivial.
    induction X. inversion H1.
      simpl. assert (X - 0 = X) by omega. rewrite H2.
      trivial.
    inversion H; subst. simpl. 
    assert (get_tvar Gamma' (S n - 1) = get_tvar Gamma (S n)).
      apply IHsubst_context. omega.
    assert (S n - 1 = n) by omega. rewrite H2 in H1.
    trivial.
    simpl. destruct m. inversion H1.
    simpl. assert (get_tvar Gamma' (S m - 1) = get_tvar Gamma (S m)).
      apply IHsubst_context. omega. assert (S m - 1 = m) by omega.
      rewrite H3 in H2. trivial.
Qed.

Lemma context_subst_lt : forall Gamma Gamma' X X' T,
  X' > X ->
  subst_context T X' Gamma Gamma' ->
  get_tvar Gamma' X = get_tvar Gamma X. 
Proof.
  intros. generalize dependent X. induction H0; intros.
    simpl. apply IHsubst_context. trivial.
    inversion H1.
    induction X. simpl. trivial.
    simpl. apply IHsubst_context. omega.
Qed.


Lemma wf_type_context_weaken : forall T Gamma Gamma',
  (forall X, get_tvar Gamma' X = false -> get_tvar Gamma X = false) ->
  well_formed_type Gamma T -> well_formed_type Gamma' T.
Proof.
  intro T. induction T; intros.
  Case "TVar".
    constructor. inversion H0; subst.
    assert (get_tvar Gamma' n = false -> get_tvar Gamma n = false) by apply H.
    rewrite <- contrapositive in H1. 
  apply not_false_is_true. intro. apply not_false_iff_true in H2. apply H1.
  apply H2. apply H3. right. apply not_false_iff_true. trivial.
  Case "TArrow T1 T2".
    constructor; inversion H0. eapply IHT1. intros. apply H. trivial. trivial.
    eapply IHT2. intros. apply H. trivial. trivial.
  Case "TUniv".
    constructor; inversion H0. apply IHT with (ext_tvar Gamma). intros. 
    induction X. simpl in H3. inversion H3.
      simpl in H3. simpl. apply H. trivial.
    trivial.
Qed.

Lemma context_invariance_types : forall T Gamma Gamma',
  (forall X, get_tvar Gamma' X = get_tvar Gamma X) ->
  well_formed_type Gamma T -> well_formed_type Gamma' T.
Proof.
  intros T Gamma Gamma' H. eapply wf_type_context_weaken. intros.
  rewrite <- H. trivial. 
Qed.    

Lemma wf_weakening_var : forall Gamma U x T,
  well_formed_type Gamma U ->
  well_formed_type (ext_var Gamma x T) U.
Proof.  
  intros. eapply context_invariance_types with Gamma. intros. 
  simpl. trivial. trivial.
Qed.

Lemma wf_strengthening_var : forall Gamma U x T,
  well_formed_type (ext_var Gamma x T) U ->
  well_formed_type Gamma U.
Proof.
  intros. apply context_invariance_types with (ext_var Gamma x T). intros.
  simpl. trivial. trivial.
Qed.

Lemma larger_context_true : forall Gamma X,
  get_tvar Gamma X = true ->
  get_tvar (ext_tvar Gamma) X = true.
Proof.
  intros. generalize dependent X. induction Gamma; intros.
    inversion H.
    assert ((get_tvar (ext_tvar (ext_var Gamma i t)) X = true) =
            (get_tvar (ext_tvar Gamma) X = true)) by trivial.
    rewrite H0. apply IHGamma. simpl in H. trivial.
    destruct X. trivial.
    apply IHGamma. simpl in H. trivial.
Qed.

Lemma wf_weakening_tvar : forall Gamma U,
  well_formed_type Gamma U ->
  well_formed_type (ext_tvar Gamma) (tshift 0 U).
Proof.
  intros. generalize 0. generalize dependent Gamma. induction U; intros;
    inversion H. constructor. destruct (le_gt_dec n0 n).
      simpl. trivial.
      apply larger_context_true. trivial.
    simpl. constructor. apply IHU1. trivial.
      apply IHU2. trivial.
    simpl. constructor. apply IHU. trivial.
Qed.

Lemma wf_str_tuniv : forall Gamma U X,
  well_formed_type (ext_tvar Gamma) (tshift X (TUniv U)) ->
  well_formed_type Gamma (TUniv U).
Proof.
  intros. generalize dependent X. admit.
Admitted.

Lemma wf_strengthening_tvar : forall Gamma U,
  well_formed_type (ext_tvar Gamma) (tshift 0 U) ->
  well_formed_type Gamma U.
Proof.
  intros. generalize dependent Gamma. 
  induction U; intros; inversion H; subst; constructor.
  Case "TVar".
    simpl in H1. trivial. 
  Case "TArrow".
    apply IHU1; trivial.
    apply IHU2; trivial.
  Case "TUniv".
    apply IHU. 
    admit.
Admitted.

Lemma context_subst_wf : forall Gamma Gamma' X U,
  subst_context U X Gamma Gamma'       ->
  well_formed_context Gamma' ->
  well_formed_type Gamma' U.
Proof with auto.
  intros Gamma Gamma' X U Hs. induction Hs; intros.
    apply wf_weakening_var. apply IHHs.
      inversion H0; subst. trivial.
    trivial.
    apply wf_weakening_tvar. apply IHHs.
      inversion H; subst.
      trivial.
Qed.            


Lemma subst_preserves_well_formed_type : forall X Gamma Gamma' U T,
  subst_context U X Gamma Gamma'    ->
  well_formed_type Gamma T          ->
  well_formed_context Gamma'        ->
  well_formed_type Gamma' ([X := U] T).
Proof.
  intros. generalize dependent U. generalize dependent Gamma.
  generalize dependent Gamma'. generalize dependent X.
  induction T; intros.
  Case "TVar".
    simpl. inversion H0; subst. 
    destruct (eq_nat_dec X n).
    SCase "X = n".
      eapply context_subst_wf. apply H. trivial.
    SCase "X <> n".
      inversion H0; subst. destruct (le_lt_dec X n).
      SSCase "X < n".
        constructor. rewrite <- H3. apply context_subst_ge with X U.
        omega. trivial.
      SSCase "X > n".
        constructor. rewrite <- H3. apply context_subst_lt with X U.
        omega. trivial.
  Case "TArrow".
    inversion H0; subst. simpl. constructor. eapply IHT1; trivial.
    apply H4. trivial.
    eapply IHT2; trivial. apply H5. trivial.
  Case "TUniv".
    simpl. constructor. eapply IHT. constructor. trivial. 
    inversion H0. apply H3.
    assert (X + 1 = S X) by omega. rewrite H2. constructor.
    trivial.
Qed.

(** WOOOOOOO!!! *)

Lemma subst_context_wf : forall Gamma Gamma' X U,
  subst_context U X Gamma Gamma' ->
  well_formed_context Gamma      ->
  well_formed_context Gamma'.
Proof.
  intros Gamma Gamma' X U H. induction H; intros.
    constructor. apply subst_type_in_type_correct in H0. 
    rewrite <- H0. eapply subst_preserves_well_formed_type.
    apply H. inversion H1; subst. trivial.
    
    apply IHsubst_context. inversion H1; subst. trivial.
    apply IHsubst_context. inversion H1; subst. trivial.

    trivial. constructor. apply IHsubst_context. inversion H0; trivial.
Qed.

Ltac tvar_case :=
  unfold tshift; unfold do_subst; fold tshift; fold do_subst;
  match goal with
  | |- ?x =>
      match x with
      | context [le_gt_dec ?n ?n'] =>
          case (le_gt_dec n n')
      | context C [(lt_eq_lt_dec ?n ?n')] =>
          case (lt_eq_lt_dec n n'); [intro s; case s; clear s | idtac ]
      end
  end.

Ltac common_cases n T :=
  simpl; generalize n; clear n; induction T; intros n''; intros;
    [ repeat tvar_case;
      simpl; trivial; try (intros; apply f_equal with (f := tvar); omega);
      try (intros; assert False; [ omega | contradiction ])
    | simpl; try (apply f_equal2 with (f := TArrow); trivial)
    | simpl ].
(* ; apply f_equal2 with (f := TUniv); trivial ]. *)

Lemma subst_shift_same : forall X T U,
  T = [X := U] (tshift X T).
Proof.
  intros. generalize dependent X. generalize dependent U.
  induction T; intros.
    simpl. destruct (le_gt_dec X n).
      destruct (eq_nat_dec X (S n)).
        omega.
      destruct (le_lt_dec X (S n)). assert (n = S n - 1) by omega. auto.
        omega.
      destruct (eq_nat_dec X n).
        omega.
        destruct (le_lt_dec X n). omega. trivial.
    simpl. simpl in IHT1. rewrite <- IHT1. simpl in IHT2; rewrite <- IHT2. trivial.
    simpl. simpl in IHT. assert (S X = X + 1) by omega. rewrite H.
      rewrite <- IHT. trivial.
Qed.

Lemma tshift_tshift_prop : forall X Y T,
  tshift X (tshift (X + Y) T) = tshift (1 + X + Y) (tshift X T).
Proof.
  intros. common_cases X T.
  rewrite IHT. trivial.
Qed.

Lemma tshift_subst_prop : forall X Y T U,
  tshift X ([X + Y := U] T) =
  [S (X + Y) := tshift X U] (tshift X T).
Proof.
  intros. generalize dependent U. common_cases X T. intros.
  simpl. destruct (eq_nat_dec (n'' + Y) n). simpl. trivial.
  destruct (le_lt_dec (n'' + Y) n). simpl.
  destruct (le_gt_dec n'' (n - 1)). assert (S (n - 1) = n - 0) by omega.
    rewrite H. trivial. omega. 
    simpl. destruct (le_gt_dec n'' n). trivial. omega.
  intros. destruct (eq_nat_dec (n'' + Y) n). omega.
    destruct (le_lt_dec (n'' + Y) n). omega.
    simpl. destruct (le_gt_dec n'' n). omega.
    destruct
      (match n as n1 return ({S (n'' + Y) = n1} + {S (n'' + Y) <> n1}) with
         | 0 => right (not_eq_sym (O_S (n'' + Y)))                           
         | S m =>                                                     
           sumbool_rec                                                     
             (fun _ : {n'' + Y = m} + {n'' + Y <> m} =>                    
                {S (n'' + Y) = S m} + {S (n'' + Y) <> S m})                  
             (fun a : n'' + Y = m => left (f_equal S a))                   
             (fun b : n'' + Y <> m => right (not_eq_S (n'' + Y) m b))      
             (eq_nat_dec (n'' + Y) m)                                      
       end). omega. 
    destruct (le_gt_dec (S (n'' + Y)) n). omega.
    destruct n. trivial. simpl. unfold sumbool_rec. unfold sumbool_rect.
    destruct (le_lt_dec (n'' + Y) n). omega. trivial.
    apply f_equal. assert (n'' + Y + 1 = S n'' + Y) by omega. rewrite H.
    assert (tshift 0 (tshift (0 + n'') U) = tshift (1 + 0 + n'') (tshift 0 U))
      by (apply tshift_tshift_prop).
    simpl in H0. rewrite H0.
    rewrite IHT. trivial.
Qed.


Lemma context_subst_get_var : forall X Y Gamma Gamma' U,
  subst_context U Y Gamma Gamma' ->
  get_var Gamma' X = opt_map (fun T => [Y := U] T) (get_var Gamma X).
Proof.
  intros. generalize dependent X. induction H; intros. 
    simpl. destruct (eq_id_dec X x).
      simpl. apply subst_type_in_type_correct in H0. rewrite <- H0. trivial.
      apply IHsubst_context.
    simpl. induction (get_var Gamma X).
      simpl. apply f_equal. apply subst_shift_same. trivial.
    simpl. rewrite IHsubst_context. induction (get_var Gamma X).
      simpl. apply f_equal. assert (S n = S (0 + n)) by omega. rewrite H0.
      assert (subst_type_in_type_fix n T a = [0 + n := T] a) by trivial.
      rewrite H1. apply tshift_subst_prop. trivial.
Qed.

Lemma tsubst_tsubst_prop : forall X Y (T U V : ty),
  [X + Y := V] ([X := U] T) =
  [X := [X + Y := V] U] ([1 + X + Y := tshift X V] T).
Proof.
  intros X Y T. common_cases X T. 
  destruct (eq_nat_dec n'' n). 
  destruct n. simpl. destruct (eq_nat_dec n'' 0).
  trivial. omega.
  unfold sumbool_rec. unfold sumbool_rect.
  destruct (eq_nat_dec (n'' + Y) n). omega.
  destruct (le_lt_dec (n'' + Y) n). omega. simpl.
  destruct (eq_nat_dec n'' (S n)).
  trivial. omega.
  destruct (le_lt_dec n'' n). simpl.
  destruct (eq_nat_dec (n'' + Y) (n - 1)). destruct n.
  omega. unfold sumbool_rec. unfold sumbool_rect.
  destruct (eq_nat_dec (n'' + Y) n). subst.
  admit. admit. admit. admit. admit.
Qed.

Lemma ty_substitution_preserves_typing : forall Gamma Gamma' X t T U,
  subst_context U X Gamma Gamma' ->
  Gamma |- t \in T               ->
  Gamma' |- [X := U] t \in [X := U] T.
Proof.
  intros. generalize dependent X. generalize dependent Gamma'.
  generalize dependent U. has_type_cases (induction H0) Case;
  intros.
  Case "T_Var".
    simpl. constructor. eapply subst_context_wf.
    apply H1. trivial.
    rewrite context_subst_get_var with (1 := H1). rewrite H0.
    trivial.
  Case "T_Abs".
    simpl. constructor. apply IHhas_type. constructor. trivial.
    apply subst_type_in_type_correct. trivial.
  Case "T_App".
    simpl. econstructor. simpl in IHhas_type1. apply IHhas_type1. trivial.
    apply IHhas_type2. trivial.
  Case "T_TAbs".
    simpl. constructor. apply IHhas_type. assert (X + 1 = S X) by omega.
    rewrite H1. constructor. trivial.
  Case "T_TApp".
    simpl. 
    assert (subst_type_fix X U t1 = [X := U] t1) by trivial. rewrite H1; clear H1.
    assert (subst_type_in_type_fix X U T2 = [X := U] T2) by trivial.
      rewrite H1; clear H1.
    assert (subst_type_in_type_fix 0 T2 T12 = [0 := T2] T12) by trivial.
      rewrite H1; clear H1.
    assert (subst_type_in_type_fix X U ([0:=T2]T12) = [X := U]([0:=T2]T12))
        by trivial. rewrite H1; clear H1.
    assert (X = 0 + X) by trivial. rewrite H1.  
    rewrite tsubst_tsubst_prop. constructor. 
    assert (TUniv ([1 + 0 + X := tshift 0 U]T12) = [X := U](TUniv T12)).
      simpl. assert (S X = X + 1) by omega. rewrite H2. trivial.
    rewrite H2. apply IHhas_type. trivial.
Qed.

Lemma type_in_context_wf : forall x T Gamma,
  well_formed_context Gamma ->
  get_var Gamma x = Some T  ->
  well_formed_type Gamma T.
Proof.
  intros. induction Gamma. 
    inversion H0.
    inversion H0; subst. destruct (eq_id_dec i x). subst.
      
    apply wf_weakening_var. apply IHGamma. inversion H; subst. trivial.
      inversion H0. destruct (eq_id_dec x x). inversion H2; subst. 

    inversion H; subst.
    admit. admit. admit. admit.
Qed.

Lemma free_in_context : forall x t T Gamma,
   term_appears_free_in_term x t ->
   Gamma |- t \in T ->
   exists T', get_var Gamma x = Some T' /\ well_formed_type Gamma T'.

(** _Proof_: We show, by induction on the proof that [x] appears free
      in [t], that, for all contexts [Gamma], if [t] is well typed
      under [Gamma], then [Gamma] assigns some type to [x].

      - If the last rule used was [afi_var], then [t = x], and from
        the assumption that [t] is well typed under [Gamma] we have
        immediately that [Gamma] assigns a type to [x].

      - If the last rule used was [afi_app1], then [t = t1 t2] and [x]
        appears free in [t1].  Since [t] is well typed under [Gamma],
        we can see from the typing rules that [t1] must also be, and
        the IH then tells us that [Gamma] assigns [x] a type.

      - Almost all the other cases are similar: [x] appears free in a
        subterm of [t], and since [t] is well typed under [Gamma], we
        know the subterm of [t] in which [x] appears is well typed
        under [Gamma] as well, and the IH gives us exactly the
        conclusion we want.

      - The only remaining case is [afi_abs].  In this case [t =
        \y:T11.t12], and [x] appears free in [t12]; we also know that
        [x] is different from [y].  The difference from the previous
        cases is that whereas [t] is well typed under [Gamma], its
        body [t12] is well typed under [(Gamma, y:T11)], so the IH
        allows us to conclude that [x] is assigned some type by the
        extended context [(Gamma, y:T11)].  To conclude that [Gamma]
        assigns a type to [x], we appeal to lemma [extend_neq], noting
        that [x] and [y] are different variables. *)

Proof.
  intros x t T Gamma H H0. generalize dependent Gamma. 
  generalize dependent T. 
  afi_cases (induction H) Case; 
         intros; try solve [inversion H0; eauto].
  Case "afi_var".
    inversion H0; subst. exists T. split. trivial.
    eapply type_in_context_wf. assumption. eassumption.
  Case "afi_abs".
    inversion H1; subst.
    apply IHterm_appears_free_in_term in H7.
    inversion H7. exists x0. simpl in H2. rewrite neq_id in H2.
    inversion H2. split. assumption. eapply wf_strengthening_var.
    eassumption. unfold not. intros. apply H. symmetry. trivial.
  Case "afi_tabs".
    inversion H0; subst. apply IHterm_appears_free_in_term in H3.
    inversion H3. simpl in H1. unfold opt_map in H1.
    destruct (get_var Gamma x).
      inversion H1. induction t0. 
        SCase "TVar". exists (TVar n). split.
          trivial. inversion H2. subst. constructor. inversion H4.
          inversion H6. trivial.
        SCase "TArrow". exists (TArrow t0_1 t0_2). split. 
          trivial. admit.
        SCase "TUniv". exists (TUniv t0). admit.
      inversion H1. inversion H2.
Qed.

(** Next, we'll need the fact that any term [t] which is well typed in
    the empty context is closed -- that is, it has no free variables. *)

(** **** Exercise: 2 stars, optional (typable_empty__closed) *)
Corollary typable_empty__closed : forall t T, 
    empty |- t \in T  ->
    closed t.
Proof.
  unfold closed, not. intros t.
  t_cases (induction t) Case; intros T H x Hc; inversion H; subst.
  Case "tvar".
    inversion H. inversion H5.
  Case "tapp".
    inversion Hc; subst.
    SCase "afi t1".
      eapply IHt1. apply H3. apply H2. 
    SCase "afi t2".
      eapply IHt2. apply H5. apply H2.
  Case "tabs".
    admit.
  Case "ttapp".
    eapply IHt. apply H4. inversion Hc; subst. apply H2.
  Case "ttabs".
    admit.
Qed.
(** [] *)



(** Sometimes, when we have a proof [Gamma |- t : T], we will need to
    replace [Gamma] by a different context [Gamma'].  When is it safe
    to do this?  Intuitively, it must at least be the case that
    [Gamma'] assigns the same types as [Gamma] to all the variables
    that appear free in [t]. In fact, this is the only condition that
    is needed. *)

Lemma context_invariance_term : forall Gamma Gamma' t T,
     Gamma |- t \in T  ->
     (forall x, term_appears_free_in_term x t ->
                get_var Gamma x = get_var Gamma' x) ->
     Gamma' |- t \in T.

(** _Proof_: By induction on the derivation of [Gamma |- t \in T].

      - If the last rule in the derivation was [T_Var], then [t = x]
        and [Gamma x = T].  By assumption, [Gamma' x = T] as well, and
        hence [Gamma' |- t \in T] by [T_Var].

      - If the last rule was [T_Abs], then [t = \y:T11. t12], with [T
        = T11 -> T12] and [Gamma, y:T11 |- t12 \in T12].  The induction
        hypothesis is that for any context [Gamma''], if [Gamma,
        y:T11] and [Gamma''] assign the same types to all the free
        variables in [t12], then [t12] has type [T12] under [Gamma''].
        Let [Gamma'] be a context which agrees with [Gamma] on the
        free variables in [t]; we must show [Gamma' |- \y:T11. t12 \in
        T11 -> T12].

        By [T_Abs], it suffices to show that [Gamma', y:T11 |- t12 \in
        T12].  By the IH (setting [Gamma'' = Gamma', y:T11]), it
        suffices to show that [Gamma, y:T11] and [Gamma', y:T11] agree
        on all the variables that appear free in [t12].  

        Any variable occurring free in [t12] must either be [y], or
        some other variable.  [Gamma, y:T11] and [Gamma', y:T11]
        clearly agree on [y].  Otherwise, we note that any variable
        other than [y] which occurs free in [t12] also occurs free in
        [t = \y:T11. t12], and by assumption [Gamma] and [Gamma']
        agree on all such variables, and hence so do [Gamma, y:T11]
        and [Gamma', y:T11].

      - If the last rule was [T_App], then [t = t1 t2], with [Gamma |-
        t1 \in T2 -> T] and [Gamma |- t2 \in T2].  One induction
        hypothesis states that for all contexts [Gamma'], if [Gamma']
        agrees with [Gamma] on the free variables in [t1], then [t1]
        has type [T2 -> T] under [Gamma']; there is a similar IH for
        [t2].  We must show that [t1 t2] also has type [T] under
        [Gamma'], given the assumption that [Gamma'] agrees with
        [Gamma] on all the free variables in [t1 t2].  By [T_App], it
        suffices to show that [t1] and [t2] each have the same type
        under [Gamma'] as under [Gamma].  However, we note that all
        free variables in [t1] are also free in [t1 t2], and similarly
        for free variables in [t2]; hence the desired result follows
        by the two IHs.
*)

Proof with eauto.
  intros. 
  generalize dependent Gamma'.
  has_type_cases (induction H) Case; intros; auto.
  Case "T_Var".
    apply T_Var. assert (well_formed_context Gamma') by admit.
    apply H2. rewrite <- H0. symmetry...
  Case "T_Abs".
    apply T_Abs.
    apply IHhas_type. intros x1 Hafi.
    (* the only tricky step... the [Gamma'] we use to  *)
(*        instantiate is [extend Gamma x T11] *)
    destruct (eq_id_dec x x1); subst; simpl.
    SCase "x0 = x1".
      repeat (rewrite eq_id)...
    SCase "x0 <> x1".
      repeat (rewrite neq_id)...
  Case "T_App".
    apply T_App with T11. apply IHhas_type1. intros. apply H1.
    constructor. trivial.
    apply IHhas_type2. intros. apply H1.
    apply afi_app2. trivial.
  Case "T_TAbs".
    apply T_TAbs.
    apply IHhas_type. intros x1 Hafi. simpl.
    rewrite H0. reflexivity.
    apply afi_tabs...
Qed.


Lemma typing_weakening : forall Gamma v U,
  Gamma |- v \in U ->
  Gamma |- shift_typ 0 v \in tshift 0 U.
Proof.
Admitted.

Lemma substitution_preserves_typing_term_term : forall Gamma x U t v T,
     ext_var Gamma x U |- t \in T ->
     empty |- v \in U   ->
     Gamma |- [x:=v]t \in T.
(** One technical subtlety in the statement of the lemma is that we
    assign [v] the type [U] in the _empty_ context -- in other words,
    we assume [v] is closed.  This assumption considerably simplifies
    the [T_Abs] case of the proof (compared to assuming [Gamma |- v \in
    U], which would be the other reasonable assumption at this point)
    because the context invariance lemma then tells us that [v] has
    type [U] in any context at all -- we don't have to worry about
    free variables in [v] clashing with the variable being introduced
    into the context by [T_Abs].

    _Proof_: We prove, by induction on [t], that, for all [T] and
    [Gamma], if [Gamma,x:U |- t \in T] and [|- v \in U], then [Gamma |-
    [x:=v]t \in T].
 
      - If [t] is a variable, there are two cases to consider, depending
        on whether [t] is [x] or some other variable.

          - If [t = x], then from the fact that [Gamma, x:U |- x \in T] we
            conclude that [U = T].  We must show that [[x:=v]x = v] has
            type [T] under [Gamma], given the assumption that [v] has
            type [U = T] under the empty context.  This follows from
            context invariance: if a closed term has type [T] in the
            empty context, it has that type in any context.

          - If [t] is some variable [y] that is not equal to [x], then
            we need only note that [y] has the same type under [Gamma,
            x:U] as under [Gamma].

      - If [t] is an abstraction [\y:T11. t12], then the IH tells us,
        for all [Gamma'] and [T'], that if [Gamma',x:U |- t12 \in T']
        and [|- v \in U], then [Gamma' |- [x:=v]t12 \in T'].

        The substitution in the conclusion behaves differently,
        depending on whether [x] and [y] are the same variable name.

        First, suppose [x = y].  Then, by the definition of
        substitution, [[x:=v]t = t], so we just need to show [Gamma |-
        t \in T].  But we know [Gamma,x:U |- t : T], and since the
        variable [y] does not appear free in [\y:T11. t12], the
        context invariance lemma yields [Gamma |- t \in T].

        Second, suppose [x <> y].  We know [Gamma,x:U,y:T11 |- t12 \in
        T12] by inversion of the typing relation, and [Gamma,y:T11,x:U
        |- t12 \in T12] follows from this by the context invariance
        lemma, so the IH applies, giving us [Gamma,y:T11 |- [x:=v]t12 \in
        T12].  By [T_Abs], [Gamma |- \y:T11. [x:=v]t12 \in T11->T12], and
        by the definition of substitution (noting that [x <> y]),
        [Gamma |- \y:T11. [x:=v]t12 \in T11->T12] as required.

      - If [t] is an application [t1 t2], the result follows
        straightforwardly from the definition of substitution and the
        induction hypotheses.

      - The remaining cases are similar to the application case.

    Another technical note: This proof is a rare case where an
    induction on terms, rather than typing derivations, yields a
    simpler argument.  The reason for this is that the assumption
    [extend Gamma x U |- t \in T] is not completely generic, in
    the sense that one of the "slots" in the typing relation -- namely
    the context -- is not just a variable, and this means that Coq's
    native induction tactic does not give us the induction hypothesis
    that we want.  It is possible to work around this, but the needed
    generalization is a little tricky.  The term [t], on the other
    hand, _is_ completely generic. *)

Proof with auto.
  intros Gamma x U t v T Ht Ht'.
  generalize dependent Gamma. generalize dependent T.
  generalize dependent U. generalize dependent v. 
  t_cases (induction t) Case; intros v U Ht T Gamma H;
    (* in each case, we'll want to get at the derivation of H *)
    inversion H; subst; simpl...
  Case "tvar".
    rename i into y. destruct (eq_id_dec x y).
    SCase "x=y".
      subst. simpl in H3; rewrite eq_id in H3; inversion H3; subst.
      eapply context_invariance_term with empty. apply Ht. intros x Hcontra.
      destruct (free_in_context _ _ T empty Hcontra) as [T' HT']...
      inversion HT'. inversion H0.
    SCase "x<>y".
      apply T_Var. inversion H1; subst.
      trivial. simpl in H3. rewrite neq_id in H3. trivial.
      intro; apply n; symmetry; trivial.
  Case "tapp".
    apply T_App with T11. apply IHt1 with U. trivial. apply H3.
    apply IHt2 with U. trivial. trivial.
  Case "tabs".
    rename i into y. apply T_Abs.
    destruct (eq_id_dec x y).
    SCase "x=y".
      apply context_invariance_term with (ext_var (ext_var Gamma x U) y t).
      apply H5. subst. intros x Hafi. unfold extend.
      destruct (eq_id_dec y x); subst.
      simpl; repeat (rewrite eq_id)...
      simpl; repeat (rewrite neq_id)...
    SCase "x<>y".
      apply IHt with U. apply Ht.
      apply context_invariance_term with (ext_var (ext_var Gamma x U) y t).
      apply H5. intros z Hafi. destruct (eq_id_dec y z); subst.
        simpl; repeat (rewrite eq_id); rewrite neq_id...
        destruct (eq_id_dec x z); subst.
          simpl; repeat (rewrite eq_id); rewrite neq_id...
          simpl; repeat (rewrite neq_id)...
  Case "ttapp".        
    econstructor. apply IHt with U. trivial. trivial.
  Case "ttabs".
    apply T_TAbs. apply IHt with (tshift 0 U).
    apply typing_weakening. assumption.
    apply context_invariance_term with (ext_tvar (ext_var Gamma x U)).
    apply H2. intros. simpl. destruct (eq_id_dec x0 x). trivial.
    trivial.
Qed.

(*
Lemma tvar_subst : forall Gamma Gamma' n T1 T2 x,
  [n := T1] Gamma = Gamma' ->
  get_var Gamma x = Some T2 ->
  get_var Gamma' x = Some ([n := T1] T2).
Proof with auto.
  intros. generalize dependent x. apply subst_context_correct in H.
  induction H; intros; subst.
  Case "1".
    simpl. inversion H0.
  Case "2".
    simpl. destruct (eq_id_dec x0 x1).
    SCase "x0 = x1".
      simpl in H0; subst. rewrite eq_id in H0. inversion H0.
      subst. apply subst_type_in_type_correct in H1.
      subst. trivial.
    SCase "x0 <> i".
      apply IHsubst_context. inversion H0.
      rewrite neq_id. trivial. assumption. assumption.
  Case "3".
    admit.
  Case "4".
    simpl. simpl in IHsubst_context.
    assert (type_appears_free_in_term n (tvar x0)).

destruct n.
    SCase "n = 0".
      assert ([0 := T1]ext_tvar Gamma = ext_tvar Gamma) by trivial.
      assert ([0 := T1] T2 = T2).
        
      rewrite H1. simpl. simpl in H0. trivial.

      rewrite <- H in H0.
    SCase "n = S n'".
      apply IHGamma. auto.

      simpl in H0. 
        trivial.
      rewrite H. eapply IHGamma with ([0 := T1]Gamma) in H0.
      simpl in H0. rewrite <- H0. 
      
eapply IHGamma in H0. apply H0.
    SCase "n = S n'".
      simpl. 

apply IHGamma. inversion H0. trivial.
*)

Lemma substitution_preserves_typing_ind : forall Gamma Gamma' t U T n,
  subst_context T n Gamma Gamma' ->
  Gamma |- t \in U ->
  Gamma' |- [n := T]t \in [n := T]U.
Proof.
  intros Gamma Gamma' t U T n H1 H2. generalize dependent Gamma'.
  generalize dependent n. generalize dependent T.
  has_type_cases (induction H2) Case; intros; admit.
Admitted.

Lemma substitution_preserves_typing_type : forall t T T' Gamma,
  ext_tvar Gamma |- t \in T ->
  Gamma |- [0 := T'] t \in [0 := T'] T.
Proof.
Admitted.


(*  Intros. generalize dependent Gamma.
  induction T; intros Gamma H; subst.
  Case "TVar".
    destruct n.
    SCase "n = 0".
      simpl. inversion H; subst. constructor. inversion H0; subst.

  t_cases (induction T) Case. Gamma H;
  inversion H; subst; simpl...
  Case "tvar".
    admit.
  Case "tapp".
    eapply T_App.

remember (subst_type_in_type_fix 0 T' T) as T0.
    symmetry in HeqT0. rewrite subst_type_in_type_correct in HeqT0.
    inversion HeqT0; subst.*)

(** The substitution lemma can be viewed as a kind of "commutation"
    property.  Intuitively, it says that substitution and typing can
    be done in either order: we can either assign types to the terms
    [t] and [v] separately (under suitable contexts) and then combine
    them using substitution, or we can substitute first and then
    assign a type to [ [x:=v] t ] -- the result is the same either
    way. *)

(* ###################################################################### *)
(** ** Main Theorem *)

(** We now have the tools we need to prove preservation: if a closed
    term [t] has type [T], and takes an evaluation step to [t'], then [t']
    is also a closed term with type [T].  In other words, the small-step
    evaluation relation preserves types.
*)

Theorem preservation : forall t t' T,
     empty |- t \in T  ->
     t ==> t'  ->
     empty |- t' \in T.

(** _Proof_: by induction on the derivation of [|- t \in T].

    - We can immediately rule out [T_Var], [T_Abs], [T_True], and
      [T_False] as the final rules in the derivation, since in each of
      these cases [t] cannot take a step.

    - If the last rule in the derivation was [T_App], then [t = t1
      t2].  There are three cases to consider, one for each rule that
      could have been used to show that [t1 t2] takes a step to [t'].

        - If [t1 t2] takes a step by [ST_App1], with [t1] stepping to
          [t1'], then by the IH [t1'] has the same type as [t1], and
          hence [t1' t2] has the same type as [t1 t2].

        - The [ST_App2] case is similar.

        - If [t1 t2] takes a step by [ST_AppAbs], then [t1 =
          \x:T11.t12] and [t1 t2] steps to [[x:=t2]t12]; the
          desired result now follows from the fact that substitution
          preserves types.

    - If the last rule in the derivation was [T_If], then [t = if t1
      then t2 else t3], and there are again three cases depending on
      how [t] steps.

        - If [t] steps to [t2] or [t3], the result is immediate, since
          [t2] and [t3] have the same type as [t].

        - Otherwise, [t] steps by [ST_If], and the desired conclusion
          follows directly from the induction hypothesis.
*)

Proof with eauto.
  remember (@empty) as Gamma. 
  intros t t' T HT. generalize dependent t'.   
  has_type_cases (induction HT) Case;
       intros t' HE; subst Gamma; subst; 
       try solve [inversion HE; subst; auto].
  Case "T_App".
    inversion HE; subst...
    (* Most of the cases are immediate by induction, 
       and [eauto] takes care of them *)
    SCase "ST_AppAbs".
      apply substitution_preserves_typing_term_term with T11...
      inversion HT1... 
  Case "T_TApp".
    inversion HE; subst...
    inversion HT; subst. apply substitution_preserves_typing_type.
    assumption.
Qed.

(** **** Exercise: 2 stars (subject_expansion_stlc) *)
(** An exercise in the [Types] chapter asked about the subject
    expansion property for the simple language of arithmetic and
    boolean expressions.  Does this property hold for STLC?  That is,
    is it always the case that, if [t ==> t'] and [has_type t' T],
    then [empty |- t \in T]?  If so, prove it.  If not, give a
    counter-example not involving conditionals. *)

Theorem not_subject_expansion_stlc : exists t t' T,
  ~(t ==> t' ->
  empty |- t' \in T ->
  empty |- t \in T).
Proof.
  exists (tapp (tabs x (TArrow TBool TBool) ttrue) tfalse).
  exists ([x:=tfalse]ttrue). exists TBool.
  unfold not; intros contra.
  assert (H: \empty |- tapp (tabs x (TArrow TBool TBool) ttrue) tfalse \in
           TBool).
    apply contra. constructor. constructor. constructor.
  inversion H; subst. inversion H3; subst. inversion H5.
Qed.

(** [] *)


(* ###################################################################### *)
(** * Type Soundness *)

(** **** Exercise: 2 stars, optional (type_soundness) *)

(** Put progress and preservation together and show that a well-typed
    term can _never_ reach a stuck state.  *)

Definition stuck (t:tm) : Prop :=
  (normal_form step) t /\ ~ value t.

Corollary soundness : forall t t' T,
  empty |- t \in T -> 
  t ==>* t' ->
  ~(stuck t').
Proof.
  intros t t' T Hhas_type Hmulti. unfold stuck.
  intros [Hnf Hnot_val]. unfold normal_form in Hnf.
  induction Hmulti.
  assert (value x0 \/ exists t', x0 ==> t')
    by (eapply progress; apply Hhas_type); inversion H.
  Case "Hmulti 1".
    apply Hnot_val. assumption.
    apply Hnf; assumption.
  Case "Hmulti 2".
    apply IHHmulti. eapply preservation. apply Hhas_type.
    assumption. assumption. assumption.
Qed.

(* ###################################################################### *)
(** * Uniqueness of Types *)

(** **** Exercise: 3 stars (types_unique) *)
(** Another pleasant property of the STLC is that types are
    unique: a given term (in a given context) has at most one
    type. *)
(** Formalize this statement and prove it. *)

Theorem types_unique : forall t Gamma T T',
  Gamma |- t \in T ->
  Gamma |- t \in T' ->
  T = T'.
Proof.
  intros t. t_cases (induction t) Case; intros Gamma T T' HT HT';
    inversion HT; inversion HT'; subst.
  Case "tvar".
    rewrite -> H5 in H1. inversion H1. reflexivity.
  Case "tapp".
    assert (Ht1:TArrow T11 T=TArrow T0 T')
           by (apply IHt1 with Gamma; assumption; assumption).
    inversion Ht1. reflexivity.
  Case "tabs".
    assert (Ht:T12=T1).
    SCase "Proof of Assertion".
      eapply IHt. apply H4. apply H10.
    subst. reflexivity.
  Case "ttrue".
    reflexivity.
  Case "tfalse".
    reflexivity.
  Case "tif".
    eapply IHt2. apply H5. assumption.
Qed.
(** [] *)

(* ###################################################################### *)
(** * Additional Exercises *)

(** **** Exercise: 1 star (progress_preservation_statement) *)
(** Without peeking, write down the progress and preservation
    theorems for the simply typed lambda-calculus. *)

(**
Definition progress : forall t T,
  empty |- t \in T ->
  (exists t', t ==> t') \/ value t.

Definition preservation : forall t t' T,
  empty |- t \in T ->
  t ==> t' ->
  empty |- t' \in T.
*)
(** [] *)


(** **** Exercise: 2 stars (stlc_variation1) *)
(** Suppose we add a new term [zap] with the following reduction rule:
                         ---------                  (ST_Zap)
                         t ==> zap
and the following typing rule:
                      ----------------               (T_Zap)
                      Gamma |- zap : T
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]
        becomes false.
          if ttrue then ttrue else tfalse ==> ttrue
          if ttrue then ttrue else tfalse ==> zap

      - Progress
        remains true

      - Preservation
        becomes false.
          Gamma |- ttrue \in TBool
          ttrue ==> zap -> Gamma zap \in (TBool -> TBool)

[]
*)

(** **** Exercise: 2 stars (stlc_variation2) *)
(** Suppose instead that we add a new term [foo] with the following reduction rules:
                       -----------------                (ST_Foo1)
                       (\x:A. x) ==> foo 

                         ------------                   (ST_Foo2)
                         foo ==> true
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]
        remains true

      - Progress
        remains true

      - Preservation
        becomes false
          empty |- (\x:T.x) \in (T -> T)
          (\x:T.x) ==> foo
          foo ==> true
          empty |- true \in Bool

[]
*)

(** **** Exercise: 2 stars (stlc_variation3) *)
(** Suppose instead that we remove the rule [ST_App1] from the [step]
    relation. Which of the following properties of the STLC remain
    true in the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]
        remains true

      - Progress
        becomes false
          (if true then true else false) false ==> true false
          the above expression becomes stuck

      - Preservation
        remains true
[]
*)

(** **** Exercise: 2 stars, optional (stlc_variation4) *)
(** Suppose instead that we add the following new rule to the reduction relation:
            ----------------------------------        (ST_FunnyIfTrue)
            (if true then t1 else t2) ==> true
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]

      - Progress

      - Preservation

*)

(** **** Exercise: 2 stars, optional (stlc_variation5) *)
(** Suppose instead that we add the following new rule to the typing relation:
                 Gamma |- t1 \in Bool->Bool->Bool
                     Gamma |- t2 \in Bool
                 ------------------------------          (T_FunnyApp)
                    Gamma |- t1 t2 \in Bool
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]

      - Progress

      - Preservation

*)

(** **** Exercise: 2 stars, optional (stlc_variation6) *)
(** Suppose instead that we add the following new rule to the typing relation:
                     Gamma |- t1 \in Bool
                     Gamma |- t2 \in Bool
                    ---------------------               (T_FunnyApp')
                    Gamma |- t1 t2 \in Bool
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]

      - Progress

      - Preservation

*)

(** **** Exercise: 2 stars, optional (stlc_variation7) *)
(** Suppose we add the following new rule to the typing
    relation of the STLC:
                         ------------------- (T_FunnyAbs)
                         |- \x:Bool.t \in Bool
    Which of the following properties of the STLC remain true in
    the presence of this rule?  For each one, write either
    "remains true" or else "becomes false." If a property becomes
    false, give a counterexample.

      - Determinism of [step]

      - Progress

      - Preservation

[]
*)

End SYSTEMFPROP.

(* ###################################################################### *)
(* ###################################################################### *)
(** ** Exercise: STLC with Arithmetic *) 

(** To see how the STLC might function as the core of a real
    programming language, let's extend it with a concrete base
    type of numbers and some constants and primitive
    operators. *)

Module STLCArith.

(** To types, we add a base type of natural numbers (and remove
    booleans, for brevity) *)

Inductive ty : Type :=
  | TArrow : ty -> ty -> ty
  | TNat   : ty.

(** To terms, we add natural number constants, along with
    successor, predecessor, multiplication, and zero-testing... *)

Inductive tm : Type :=
  | tvar : id -> tm
  | tapp : tm -> tm -> tm
  | tabs : id -> ty -> tm -> tm
  | tnat  : nat -> tm
  | tsucc : tm -> tm
  | tpred : tm -> tm
  | tmult : tm -> tm -> tm
  | tif0  : tm -> tm -> tm -> tm.

Tactic Notation "t_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "tvar" | Case_aux c "tapp" 
  | Case_aux c "tabs" | Case_aux c "tnat" 
  | Case_aux c "tsucc" | Case_aux c "tpred"
  | Case_aux c "tmult" | Case_aux c "tif0" ].

(** **** Exercise: 4 stars (stlc_arith) *)
(** Finish formalizing the definition and properties of the STLC extended
    with arithmetic.  Specifically:

    - Copy the whole development of STLC that we went through above (from
      the definition of values through the Progress theorem), and
      paste it into the file at this point.

    - Extend the definitions of the [subst] operation and the [step]
      relation to include appropriate clauses for the arithmetic operators.

    - Extend the proofs of all the properties (up to [soundness]) of
      the original STLC to deal with the new syntactic forms.  Make
      sure Coq accepts the whole file. *)

(** *** Values *)

Inductive value : tm -> Prop :=
  | v_abs : forall x T t,
      value (tabs x T t)
  | v_nat : forall n,
      value (tnat n).

Hint Constructors value.


(* ###################################################################### *)
(** *** Substitution *)

(** Here is the definition, informally...
   [x:=s]x = s
   [x:=s]y = y                                   if x <> y
   [x:=s](\x:T11.t12)    = \x:T11. t12      
   [x:=s](\y:T11.t12)    = \y:T11. [x:=s]t12      if x <> y
   [x:=s](t1 t2)         = ([x:=s]t1) ([x:=s]t2)       
   [x:=s](tnat t)        = tnat n
   [x:=s](tsucc t)       = tsucc ([x:=s]t)
   [x:=s](tpred t)       = tpred ([x:=s]t)
   [x:=s](tmult t1 t2)   = tmult ([x:=s]t1) ([x:=s]t2)
   [x:=s](tif0 t1 t2 t3) = tif ([x:=s]t1) ([x:=s]t2) ([x:=s]t3)
]]  
*)

(**    ... and formally: *)

Reserved Notation "'[' x ':=' s ']' t" (at level 20).

Fixpoint subst (x:id) (s:tm) (t:tm) : tm :=
  match t with
  | tvar x' => 
      if eq_id_dec x x' then s else t
  | tabs x' T t1 => 
      tabs x' T (if eq_id_dec x x' then t1 else ([x:=s] t1)) 
  | tapp t1 t2 => 
      tapp ([x:=s] t1) ([x:=s] t2)
  | tnat n =>
      tnat n
  | tsucc t' =>
      tsucc ([x:=s]t')
  | tpred t' =>
      tpred ([x:=s]t')
  | tmult t1 t2 =>
      tmult ([x:=s]t1) ([x:=s]t2)
  | tif0 t1 t2 t3 =>
      tif0 ([x:=s]t1) ([x:=s]t2) ([x:=s]t3)
  end

where "'[' x ':=' s ']' t" := (subst x s t).


(* ################################### *)
(** *** Reduction *)

(** The small-step reduction relation for STLC now follows the same
    pattern as the ones we have seen before.  Intuitively, to reduce a
    function application, we first reduce its left-hand side until it
    becomes a literal function; then we reduce its right-hand
    side (the argument) until it is also a value; and finally we
    substitute the argument for the bound variable in the body of the
    function.  This last rule, written informally as
      (\x:T.t12) v2 ==> [x:=v2]t12
    is traditionally called "beta-reduction". *)

(** 
                               value v2
                     ----------------------------                   (ST_AppAbs)
                     (\x:T.t12) v2 ==> [x:=v2]t12

                              t1 ==> t1'
                           ----------------                           (ST_App1)
                           t1 t2 ==> t1' t2

                              value v1
                              t2 ==> t2'
                           ----------------                           (ST_App2)
                           v1 t2 ==> v1 t2'
*)
(** ... plus the usual rules for natural numbers:

                               t ==> t'
                         --------------------                        (ST_Succ1)
                         tsucc t ==> tsucc t'

                  -------------------------------                    (ST_Succ2)
                  tsucc (tnat n) ==> tnat (n + 1)

                               t ==> t'
                         --------------------                        (ST_Pred1)
                         tpred t ==> tpred t'

                  -------------------------------                    (ST_Pred2)
                  tpred (tnat n) ==> tnat (n - 1)

                              t1 ==> t1'
                    ----------------------------                     (ST_Mult1)
                    tmult t1 t2  ==> mult t1' t2

                              value v1
                              t2 ==> t2'
                    ----------------------------                     (ST_Mult2)
                    tmult v1 t2  ==> mult v1 t2'

                    ------------------------                          (ST_Mult)
                    tmult n1 n2  ==> n1 * n2
                    
                   ---------------------------                      (ST_IfTrue)
                   tif0 (tnat 0) t1 t2  ==> t1

                 -------------------------------                   (ST_IfFalse)
                 tif0 (tnat (S n)) t1 t2  ==> t2

                              t1 ==> t1'
                  ---------------------------------                     (ST_If)
                  tif0 t1 t2 t3  ==> tif0 t1' t2 t3
*)

Reserved Notation "t1 '==>' t2" (at level 40).

Inductive step : tm -> tm -> Prop :=
  | ST_AppAbs : forall x T t12 v2,
         value v2 ->
         (tapp (tabs x T t12) v2) ==> [x:=v2]t12
  | ST_App1 : forall t1 t1' t2,
         t1 ==> t1' ->
         tapp t1 t2 ==> tapp t1' t2
  | ST_App2 : forall v1 t2 t2',
         value v1 ->
         t2 ==> t2' -> 
         tapp v1 t2 ==> tapp v1  t2'
  | ST_Succ1 : forall t t',
         t ==> t' ->
         tsucc t ==> tsucc t'
  | ST_Succ2 : forall n,
         tsucc (tnat n) ==> tnat (n + 1)
  | ST_Pred1 : forall t t',
         t ==> t' ->
         tpred t ==> tpred t'
  | ST_Pred2 : forall n,
         tpred (tnat n) ==> tnat (n - 1)
  | ST_Mult1 : forall t1 t1' t2,
         t1 ==> t1' ->
         tmult t1 t2 ==> tmult t1' t2
  | ST_Mult2 : forall v1 t2 t2',
         value v1 ->
         t2 ==> t2' ->
         tmult v1 t2 ==> tmult v1 t2'
  | ST_Mult : forall n1 n2,
         tmult (tnat n1) (tnat n2) ==> tnat (n1 * n2)
  | ST_IfTrue : forall t1 t2,
         tif0 (tnat 0) t1 t2 ==> t1
  | ST_IfFalse : forall n t1 t2,
         tif0 (tnat (S n)) t1 t2 ==> t2
  | ST_If : forall t1 t1' t2 t3,
         t1 ==> t1' ->
         tif0 t1 t2 t3 ==> tif0 t1' t2 t3
              
where "t1 '==>' t2" := (step t1 t2).

Tactic Notation "step_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "ST_AppAbs" | Case_aux c "ST_App1" | Case_aux c "ST_App2"
  | Case_aux c "ST_Succ1"  | Case_aux c "ST_Succ2"
  | Case_aux c "ST_Pred1"  | Case_aux c "ST_Pred2"
  | Case_aux c "ST_Mult1"  | Case_aux c "ST_Mult2" | Case_aux c "ST_Mult" 
  | Case_aux c "ST_IfTrue" | Case_aux c "ST_IfFalse" | Case_aux c "ST_If"].

Hint Constructors step.

Notation multistep := (multi step).
Notation "t1 '==>*' t2" := (multistep t1 t2) (at level 40).

Definition context := partial_map ty.

(* ################################### *)
(** *** Typing Relation *)

(** 
                             Gamma x = T
                            --------------                              (T_Var)
                            Gamma |- x \in T

                      Gamma , x:T11 |- t12 \in T12
                     ----------------------------                       (T_Abs)
                     Gamma |- \x:T11.t12 \in T11->T12

                        Gamma |- t1 \in T11->T12
                          Gamma |- t2 \in T11
                        ----------------------                          (T_App)
                         Gamma |- t1 t2 \in T12

                      -------------------------                        (T_TNat)
                      Gamma |- (tnat n) \in Nat

                           Gamma |- t \in Nat
                        ------------------------                       (T_Succ)
                        Gamma |- tsucc t \in Nat

                           Gamma |- t \in Nat
                        ------------------------                       (T_Pred)
                        Gamma |- tpred t \in Nat

                           Gamma |- t1 \in Nat
                           Gamma |- t2 \in Nat
                      ----------------------------                     (T_Mult)
                      Gamma |- tmult t1 t2 \in Nat

                           Gamma |- t1 \in Nat
                           Gamma |- t2 \in T
                           Gamma |- t3 \in T
                  -------------------------------------                  (T_If)
                  Gamma |- if0 t1 then t2 else t3 \in T


    We can read the three-place relation [Gamma |- t \in T] as: 
    "to the term [t] we can assign the type [T] using as types for
    the free variables of [t] the ones specified in the context 
    [Gamma]." *)

Reserved Notation "Gamma '|-' t '\in' T" (at level 40).
    
Inductive has_type : context -> tm -> ty -> Prop :=
  | T_Var : forall Gamma x T,
      Gamma x = Some T ->
      Gamma |- tvar x \in T
  | T_Abs : forall Gamma x T11 T12 t12,
      extend Gamma x T11 |- t12 \in T12 -> 
      Gamma |- tabs x T11 t12 \in TArrow T11 T12
  | T_App : forall T11 T12 Gamma t1 t2,
      Gamma |- t1 \in TArrow T11 T12 -> 
      Gamma |- t2 \in T11 -> 
      Gamma |- tapp t1 t2 \in T12
  | T_TNat : forall Gamma n,
       Gamma |- (tnat n) \in TNat
  | T_Succ : forall Gamma t,
       Gamma |- t \in TNat ->
       Gamma |- tsucc t \in TNat
  | T_Pred : forall Gamma t,
       Gamma |- t \in TNat ->
       Gamma |- tpred t \in TNat
  | T_Mult : forall Gamma t1 t2,
       Gamma |- t1 \in TNat ->
       Gamma |- t2 \in TNat ->
       Gamma |- tmult t1 t2 \in TNat
  | T_If : forall t1 t2 t3 T Gamma,
       Gamma |- t1 \in TNat ->
       Gamma |- t2 \in T ->
       Gamma |- t3 \in T ->
       Gamma |- tif0 t1 t2 t3 \in T

where "Gamma '|-' t '\in' T" := (has_type Gamma t T).

Tactic Notation "has_type_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "T_Var"  | Case_aux c "T_Abs"  | Case_aux c "T_App" 
  | Case_aux c "T_TNat" | Case_aux c "T_Succ" | Case_aux c "T_Pred"
  | Case_aux c "T_Mult" | Case_aux c "T_If" ].

Hint Constructors has_type.

(** * Canonical Forms *)

Lemma canonical_forms_nat : forall t,
  empty |- t \in TNat ->
  value t ->
  exists n, t = tnat n.
Proof.
  intros t HT HVal.
  inversion HVal; intros; subst. inversion HT.
  exists n. reflexivity.
Qed.

Lemma canonical_forms_fun : forall t T1 T2,
  empty |- t \in (TArrow T1 T2) ->
  value t ->
  exists x u, t = tabs x T1 u.
Proof.
  intros t T1 T2 HT HVal.
  inversion HVal; intros; subst; try inversion HT; subst; auto.
  exists x. exists t0.  auto.
Qed.
   

(* ###################################################################### *)
(** * Progress *)

(** As before, the _progress_ theorem tells us that closed, well-typed
    terms are not stuck: either a well-typed term is a value, or it
    can take an evaluation step.  The proof is a relatively
    straightforward extension of the progress proof we saw in the
    [Types] chapter. *)

Theorem progress : forall t T, 
     empty |- t \in T ->
     value t \/ exists t', t ==> t'.

Proof with eauto.
  intros t T Ht.
  remember (@empty ty) as Gamma.
  has_type_cases (induction Ht) Case; subst Gamma.
  Case "T_Var".
    (* contradictory: variables cannot be typed in an 
       empty context *)
    inversion H. 
  Case "T_Abs".
    left...
  Case "T_App". 
    (* [t] = [t1 t2].  Proceed by cases on whether [t1] is a 
       value or steps... *)
    right. destruct IHHt1...
    SCase "t1 is a value".
      destruct IHHt2...
      SSCase "t2 is also a value".
        assert (exists x0 t0, t1 = tabs x0 T11 t0).
        eapply canonical_forms_fun; eauto.
        destruct H1 as [x0 [t0 Heq]]. subst.
        exists ([x0:=t2]t0)...

      SSCase "t2 steps".
        inversion H0 as [t2' Hstp]. exists (tapp t1 t2')...

    SCase "t1 steps".
      inversion H as [t1' Hstp]. exists (tapp t1' t2)...
  Case "T_TNat".
    left...
  Case "T_Succ".
    right. destruct IHHt...
    SCase "t is a value".
      inversion H; subst; inversion Ht.
      exists (tnat (n + 1))...
    SCase "t takes a step".
      inversion H. exists (tsucc x)...
  Case "T_Pred".
    right. destruct IHHt...
    SCase "t is a value".
      inversion H; subst; inversion Ht.
      exists (tnat (n - 1))...
    SCase "t takes a step".
      inversion H. exists (tpred x)...
  Case "T_Mult".
    right. destruct IHHt1...
    SCase "t1 is a value".
      destruct IHHt2...
      SSCase "t2 is a value".
        inversion H; inversion H0; subst.
        inversion Ht2. inversion Ht1. inversion Ht2.
        exists (tnat (n * n0))...
      SSCase "t2 takes a step".
        inversion H0. exists (tmult t1 x)...
    SCase "t1 takes a step".
      inversion H. exists (tmult x t2)...
  Case "T_If".
    right. destruct IHHt1.
    reflexivity. inversion H; subst.
    SCase "t1 is a value".
      inversion Ht1. destruct n.
      SSCase "n = 0". exists t2...
      SSCase "n = S n'". exists t3...
    SCase "t1 takes a step".
      inversion H. exists (tif0 x t2 t3)...
Qed.

(** * Preservation *)

(* ###################################################################### *)
(** ** Free Occurrences *)

(** A variable [x] _appears free in_ a term _t_ if [t] contains some
    occurrence of [x] that is not under an abstraction labeled [x].  For example: 
      - [y] appears free, but [x] does not, in [\x:T->U. x y] 
      - both [x] and [y] appear free in [(\x:T->U. x y) x] 
      - no variables appear free in [\x:T->U. \y:T. x y]  *)

Inductive appears_free_in : id -> tm -> Prop :=
  | afi_var : forall x,
      appears_free_in x (tvar x)
  | afi_app1 : forall x t1 t2,
      appears_free_in x t1 -> appears_free_in x (tapp t1 t2)
  | afi_app2 : forall x t1 t2,
      appears_free_in x t2 -> appears_free_in x (tapp t1 t2)
  | afi_abs : forall x y T11 t12,
      y <> x  ->
      appears_free_in x t12 ->
      appears_free_in x (tabs y T11 t12)
  | afi_succ : forall x t,
      appears_free_in x t -> appears_free_in x (tsucc t)
  | afi_pred : forall x t,
      appears_free_in x t -> appears_free_in x (tpred t)
  | afi_mult1 : forall x t1 t2,
      appears_free_in x t1 -> appears_free_in x (tmult t1 t2)
  | afi_mult2 : forall x t1 t2,
      appears_free_in x t2 -> appears_free_in x (tmult t1 t2)
  | afi_if1 : forall x t1 t2 t3,
      appears_free_in x t1 ->
      appears_free_in x (tif0 t1 t2 t3)
  | afi_if2 : forall x t1 t2 t3,
      appears_free_in x t2 ->
      appears_free_in x (tif0 t1 t2 t3)
  | afi_if3 : forall x t1 t2 t3,
      appears_free_in x t3 ->
      appears_free_in x (tif0 t1 t2 t3).

Tactic Notation "afi_cases" tactic(first) ident(c) :=
  first;
  [ Case_aux c "afi_var"
  | Case_aux c "afi_app1" | Case_aux c "afi_app2" 
  | Case_aux c "afi_abs"
  | Case_aux c "afi_succ" | Case_aux c "afi_pred"
  | Case_aux c "afi_mult1" | Case_aux c "afi_mult2" 
  | Case_aux c "afi_if1" | Case_aux c "afi_if2" 
  | Case_aux c "afi_if3" ].

Hint Constructors appears_free_in.

(** A term in which no variables appear free is said to be _closed_. *)

Definition closed (t:tm) :=
  forall x, ~ appears_free_in x t.

(* ###################################################################### *)
(** ** Substitution *)

(** We first need a technical lemma connecting free variables and
    typing contexts.  If a variable [x] appears free in a term [t],
    and if we know [t] is well typed in context [Gamma], then it must
    be the case that [Gamma] assigns a type to [x]. *)

Lemma free_in_context : forall x t T Gamma,
   appears_free_in x t ->
   Gamma |- t \in T ->
   exists T', Gamma x = Some T'.

Proof.
  intros x t T Gamma H H0. generalize dependent Gamma. 
  generalize dependent T. 
  afi_cases (induction H) Case; 
         intros; try solve [inversion H0; eauto].
  Case "afi_abs".
    inversion H1; subst.
    apply IHappears_free_in in H7.
    rewrite extend_neq in H7; assumption.
Qed.




Lemma context_invariance : forall Gamma Gamma' t T,
     Gamma |- t \in T  ->
     (forall x, appears_free_in x t -> Gamma x = Gamma' x) ->
     Gamma' |- t \in T.
Proof with eauto.
  intros. 
  generalize dependent Gamma'.
  has_type_cases (induction H) Case; intros; auto.
  Case "T_Var".
    apply T_Var. rewrite <- H0...
  Case "T_Abs".
    apply T_Abs.
    apply IHhas_type. intros x1 Hafi.
    (* the only tricky step... the [Gamma'] we use to 
       instantiate is [extend Gamma x T11] *)
    unfold extend. destruct (eq_id_dec x x1)... 
  Case "T_App".
    apply T_App with T11...  
Qed.


Lemma substitution_preserves_typing : forall Gamma x U t v T,
     extend Gamma x U |- t \in T ->
     empty |- v \in U   ->
     Gamma |- [x:=v]t \in T.
Proof with eauto.
  intros Gamma x U t v T Ht Ht'.
  generalize dependent Gamma. generalize dependent T. 
  t_cases (induction t) Case; intros T Gamma H;
    (* in each case, we'll want to get at the derivation of H *)
    inversion H; subst; simpl...
  Case "tvar".
    rename i into y. destruct (eq_id_dec x y).
    SCase "x=y".
      subst. 
      
      inversion H2; subst. clear H2.
                  eapply context_invariance... intros x Hcontra.
      destruct (free_in_context _ _ T empty Hcontra) as [T' HT']...
      inversion HT'.
    SCase "x<>y".
      apply T_Var. rewrite extend_neq in H2... 
  Case "tabs".
    rename i into y. apply T_Abs.
    destruct (eq_id_dec x y).
    SCase "x=y".
      eapply context_invariance...
      subst.
      intros x Hafi. unfold extend.
      destruct (eq_id_dec y x)...
    SCase "x<>y".
      apply IHt. eapply context_invariance...
      intros z Hafi. unfold extend.
      destruct (eq_id_dec y z)...
      subst. rewrite neq_id... 
Qed.

(** The substitution lemma can be viewed as a kind of "commutation"
    property.  Intuitively, it says that substitution and typing can
    be done in either order: we can either assign types to the terms
    [t] and [v] separately (under suitable contexts) and then combine
    them using substitution, or we can substitute first and then
    assign a type to [ [x:=v] t ] -- the result is the same either
    way. *)

(** ** Main Theorem *)

Theorem preservation : forall t t' T,
     empty |- t \in T  ->
     t ==> t'  ->
     empty |- t' \in T.
Proof with eauto.
  remember (@empty ty) as Gamma. 
  intros t t' T HT. generalize dependent t'.   
  has_type_cases (induction HT) Case;
       intros t' HE; subst Gamma; subst; 
       try solve [inversion HE; subst; auto].
  Case "T_App".
    inversion HE; subst...
    (* Most of the cases are immediate by induction, 
       and [eauto] takes care of them *)
    SCase "ST_AppAbs".
      apply substitution_preserves_typing with T11...
      inversion HT1...
Qed.

(** **** Exercise: 2 stars (subject_expansion_stlc) *)
(** An exercise in the [Types] chapter asked about the subject
    expansion property for the simple language of arithmetic and
    boolean expressions.  Does this property hold for STLC?  That is,
    is it always the case that, if [t ==> t'] and [has_type t' T],
    then [empty |- t \in T]?  If so, prove it.  If not, give a
    counter-example not involving conditionals. *)

Theorem not_subject_expansion_stlc : exists t t' T,
  ~(t ==> t' ->
  empty |- t' \in T ->
  empty |- t \in T).
Proof.
  exists (tapp (tabs X (TArrow TNat TNat) (tnat 0)) (tnat 1)).
  exists ([X:=tnat 1]tnat 0). exists TNat.
  unfold not; intros contra.
  assert (H: \empty |- tapp (tabs X (TArrow TNat TNat) (tnat 0)) (tnat 1) \in
           TNat).
    apply contra. constructor. constructor. constructor.
  inversion H; subst. inversion H3; subst. inversion H5.
Qed.

(** [] *)


(* ###################################################################### *)
(** * Type Soundness *)

(** **** Exercise: 2 stars, optional (type_soundness) *)

(** Put progress and preservation together and show that a well-typed
    term can _never_ reach a stuck state.  *)

Definition stuck (t:tm) : Prop :=
  (normal_form step) t /\ ~ value t.

Corollary soundness : forall t t' T,
  empty |- t \in T -> 
  t ==>* t' ->
  ~(stuck t').
Proof.
  intros t t' T Hhas_type Hmulti. unfold stuck.
  intros [Hnf Hnot_val]. unfold normal_form in Hnf.
  induction Hmulti.
  assert (value x \/ exists t', x ==> t')
    by (eapply progress; apply Hhas_type); inversion H.
  Case "Hmulti 1".
    apply Hnot_val. assumption.
    apply Hnf; assumption.
  Case "Hmulti 2".
    apply IHHmulti. eapply preservation. apply Hhas_type.
    assumption. assumption. assumption.
Qed.
(** [] *)

End STLCArith.

(* $Date: 2013-07-17 16:19:11 -0400 (Wed, 17 Jul 2013) $ *)

