module AutoEnv.Bind where

import AutoEnv.Classes
import AutoEnv.Lib
import AutoEnv.Env

----------------------------------------------------------------
-- Single binders
----------------------------------------------------------------

-- | Type for a single binders
-- includes an delayed substitution plus a term with an
-- extra free variable for the binder
-- n is the number of free variables in the term
data Bind v c (n :: Nat) where
  Bind :: Env v m n -> c (S m) -> Bind v c n

-- | The substitution operation composes the explicit
-- substitution with the one stored at the binder
instance (Subst v v) => Subst v (Bind v c) where
  applyE :: (Subst v v) => Env v n m -> Bind v c n -> Bind v c m
  applyE env1 (Bind env2 m) = Bind (env2 .>> env1) m

-- TODO: more effiencient implmentation that looks at the env??
instance (Subst v v, Subst v c, FV c) => FV (Bind v c) where
  appearsFree n b = appearsFree (FS n) (unbind b)

-- | create a single binder
bind :: (Subst v c) => c (S n) -> Bind v c n
bind = Bind idE

-- | access the body of the binder  (inverse of bind)
unbind :: forall v c n. (Subst v v, Subst v c) => Bind v c n -> c (S n)
unbind (Bind r t) = applyE (up r) t

-- | unbind a binder and apply the function to the argument and subterm
unbindWith ::
  Bind v c n ->
  (forall m. Env v m n -> c (S m) -> d) ->
  d
unbindWith (Bind r t) f = f r t

-- | instantiate a binder with a term
instantiate :: (Subst v c) => Bind v c n -> v n -> c n
instantiate b v = unbindWith b (\r e -> applyE (v .: r) e)

-- | apply an environment-parameterized function while
-- instantiating
instantiateWith ::
  Bind v c n ->
  v n ->
  (forall m n. Env v m n -> c m -> d n) ->
  d n
instantiateWith b v f = unbindWith b (\r e -> f (v .: r) e)

instantiateWithEnv ::
  (Subst v v) =>
  Bind v c m ->
  Env v m n ->
  v n ->
  (forall m n. Env v m n -> c m -> d n) ->
  d n
instantiateWithEnv b r2 v f =
  unbindWith b (\r1 e -> f (v .: (r1 .>> r2)) e)

-- | apply an environment-parameterized function & environment
-- underneath a binder
applyUnder ::
  (Subst v v, Subst v c) =>
  (forall m n. Env v m n -> c m -> c n) ->
  Env v n1 n2 ->
  Bind v c n1 ->
  Bind v c n2
applyUnder f r2 b =
  bind $ unbindWith b (\r1 t -> f (up (r1 .>> r2)) t)

-- TODO: this implementation of strengthening for binders is rather inefficient
-- maybe there is a better way to do it???
instance (SubstVar v, Subst v v, Subst v c, Strengthen c) => Strengthen (Bind v c) where
  strengthen' (m :: SNat m) (n :: SNat n) b =
    case axiom @m @n of
      Refl -> bind <$> strengthen' m (SS n) (unbind b)

-- | Create a substitution that instantiates a binder
-- with `a` and shifts at the same time. This is useful for
-- opening a pi-type after n-ary binding in pattern matching
-- TODO: better name?
-- TODO: more efficient implementation?
instantiateWeakenEnv ::
  forall p n v c.
  (SubstVar v, Subst v v) =>
  SNat p ->
  SNat n ->
  v (Plus p n) ->
  Env v (S n) (Plus p n)
instantiateWeakenEnv p n a =
  shiftNE @v p
    .>> Env
      ( \(x :: Fin (Plus p (S n))) ->
          case checkBound @p @(S n) p x of
            Left pf -> var (weakenFinRight n pf)
            Right pf -> case pf of
              FZ -> a
              FS (f :: Fin n) -> var (shiftN p f)
      )

-- | instantiate a single binder with a term from a larger scope
-- this simultaneously shifts the body of the bind to that scope
-- TODO: add a version of instantiateShift for pattern binding
instantiateShift ::
  forall p n v c.
  (SubstVar v, Subst v v, Subst v c, SNatI n) =>
  SNat p ->
  Bind v c n ->
  v (Plus p n) ->
  c (Plus p n)
instantiateShift p b a =
  let r :: Env v (S n) (Plus p n)
      r = instantiateWeakenEnv p (snat @n) a
   in applyE r (unbind b)