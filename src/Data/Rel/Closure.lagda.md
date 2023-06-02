<!--
```agda
open import 1Lab.Prelude
open import Data.Sum

import Data.Nat as Nat
import Data.Nat.Order as Nat
```
-->

```agda
module Data.Rel.Closure where
```

<!--
```agda
private variable
  ℓ ℓ' ℓ'' : Level
  A B X : Type ℓ
  R S : A → A → Type ℓ
```
-->

# Closures of relations

A **closure operator** $-^{+}$ on relations takes a relation $R$ on a type
$A$ to a new relation $R^{+}$ on $A$, where $R^{+}$ is the smallest
relation containing $R$ that satisfies some property.

<!-- [TODO: Reed M, 01/06/2023] Talk about monads here. -->

## Reflexive Closure

The reflexive closure of a relation $R$ is the smallest reflexive
relation $R^{=}$ that contains $R$.

```agda
data Refl {A : Type ℓ} (R : A → A → Type ℓ') (x : A) : A → Type (ℓ ⊔ ℓ') where
  reflexive : Refl R x x
  [_] : ∀ {y} → R x y → Refl R x y
  trunc : ∀ {y} → is-prop (Refl R x y)
```

<!--
```agda
instance
  Refl-H-Level : ∀ {x y} {n} → H-Level (Refl R x y) (suc n)
  Refl-H-Level = prop-instance trunc

Refl-elim
  : (P : ∀ (x y : A) → Refl R x y → Type ℓ'')
  → (∀ {x y} → (r : R x y) → P x y [ r ])
  → (∀ x → P x x reflexive)
  → (∀ {x y} → (r+ : Refl R x y) → is-prop (P x y r+))
  → ∀ {x y} → (r+ : Refl R x y) → P x y r+
Refl-elim {R = R} P prel prefl pprop r+ = go r+ where
  go : ∀ {x y} → (r+ : Refl R x y) → P x y r+
  go reflexive = prefl _
  go [ x ] = prel x
  go (trunc r+ r+' i) =
    is-prop→pathp (λ i → pprop (trunc r+ r+' i)) (go r+) (go r+') i
```
-->

The recursion principle for the reflexive closure of a relation witnesses
the aforementioned universal property: it is the smallest reflexive
relation containing $R$.

```agda
Refl-rec
  : (S : A → A → Type ℓ)
  → (∀ {x y} → R x y → S x y)
  → (∀ x → S x x)
  → (∀ {x y} → is-prop (S x y))
  → ∀ {x y} → Refl R x y → S x y
Refl-rec {R = R} S prel prefl pprop r+ = go r+ where
  go : ∀ {x y} → Refl R x y → S x y
  go reflexive = prefl _
  go [ r ] = prel r
  go (trunc r+ r+' i) = pprop (go r+) (go r+') i
```

If the original relation is symmetric or transitive, then so is the
reflexive closure.

```agda
refl-clo-symmetric
  : (∀ {x y} → R x y → R y x)
  → ∀ {x y} → Refl R x y → Refl R y x
refl-clo-symmetric {R = R} is-sym =
  Refl-rec (λ x y → Refl R y x)
    (λ r → [ is-sym r ])
    (λ _ → reflexive)
    trunc

refl-clo-transitive
  : (∀ {x y z} → R x y → R y z → R x z)
  → ∀ {x y z} → Refl R x y → Refl R y z → Refl R x z
refl-clo-transitive is-trans reflexive s+ = s+
refl-clo-transitive is-trans [ r ] reflexive = [ r ]
refl-clo-transitive is-trans [ r ] [ s ] = [ is-trans r s ]
refl-clo-transitive is-trans [ r ] (trunc s+ s+' i) =
  trunc
    (refl-clo-transitive is-trans [ r ] s+)
    (refl-clo-transitive is-trans [ r ] s+') i
refl-clo-transitive is-trans (trunc r+ r+' i) s+ =
  trunc
    (refl-clo-transitive is-trans r+ s+)
    (refl-clo-transitive is-trans r+' s+) i
```


## Symmetric Closure

The symmetric closure of a relation $R$ is the smallest reflexive
relation $R^{\leftrightarrow}$ that contains $R$.

```agda
data Sym {A : Type ℓ} (R : A → A → Type ℓ') (x y : A) : Type (ℓ ⊔ ℓ') where
  symmetric : R y x → Sym R x y
  [_] : R x y → Sym R x y
  trunc : is-prop (Sym R x y)
```

<!--
```agda
instance
  Sym-H-Level : ∀ {x y} {n} → H-Level (Refl R x y) (suc n)
  Sym-H-Level = prop-instance trunc

Sym-elim
  : (P : ∀ (x y : A) → Sym R x y → Type ℓ'')
  → (∀ {x y} → (r : R x y) → P x y [ r ])
  → (∀ {x y} → (r : R y x) → P x y (symmetric r))
  → (∀ {x y} → (r+ : Sym R x y) → is-prop (P x y r+))
  → ∀ {x y} → (r+ : Sym R x y) → P x y r+
Sym-elim {R = R} P prel psym pprop r+ = go r+ where
  go : ∀ {x y} → (r+ : Sym R x y) → P x y r+
  go (symmetric x) = psym x
  go [ x ] = prel x
  go (trunc r+ r+' i) =
    is-prop→pathp (λ i → pprop (trunc r+ r+' i)) (go r+) (go r+') i
```
-->

```agda
Sym-rec
  : (S : A → A → Type ℓ)
  → (∀ {x y} → R x y → S x y)
  → (∀ {x y} → R y x → S x y)
  → (∀ {x y} → is-prop (S x y))
  → ∀ {x y} → Sym R x y → S x y
Sym-rec {R = R} S prel psym pprop r+ = go r+ where
  go : ∀ {x y} → Sym R x y → S x y
  go (symmetric r) = psym r
  go [ r ] = prel r
  go (trunc r+ r+' i) = pprop (go r+) (go r+') i
```

If two elements $x$ and $y$ are related in the symmetric closure, then
either $R x y$ or $R y x$ in the original relation.

```agda
sym-clo-rel
  : ∀ {x y} → Sym R x y → ∥ (R x y) ⊎ (R y x) ∥
sym-clo-rel {R = R} =
  Sym-rec (λ x y → ∥ (R x y) ⊎ (R y x) ∥)
    (λ r → inc (inl r))
    (λ r → inc (inr r))
    squash
```



If the original relation is reflexive, then so is the symmetric closure.

```agda
sym-clo-reflexive
  : (∀ x → R x x)
  → ∀ x → Sym R x x
sym-clo-reflexive is-refl x = [ is-refl x ]
```

Note that this is *not* true for transitivity! To see why, consider an
irreflexive transitive relation on a type with at least related 2
elements $R x y$ . If the symmetric closure of this relation was
transitive, we'd be able to create a loop $R^{\leftrightarrow} x x$ in
the symmetric closure by composing the relations $R^{\leftrightarrow} x
y$ and $R^{\leftrightarrow} y x$.  However, if two elements are related
in the symmetric closure, then they must be related in the original
relation, which leads directly to a contradiction, as the original
relation is irreflexive.

For simplicity, we show this for the strict ordering on the natural
numbers.

```agda
private
  ¬sym-clo-transitive
    : ¬ (∀ {x y z} → Sym Nat._<_ x y → Sym Nat._<_ y z → Sym Nat._<_ x z)
  ¬sym-clo-transitive sym-clo-trans =
    ∥-∥-rec! (⊎-rec (Nat.<-irrefl refl) (Nat.<-irrefl refl))
      (sym-clo-rel (sym-clo-trans [ 0<1 ] (symmetric 0<1)))
    where
      0<1 : 0 Nat.< 1
      0<1 = Nat.s≤s Nat.0≤x
```


## Transitive Closure

```agda
data Trans {A : Type ℓ} (_~_ : A → A → Type ℓ') (x z : A) : Type (ℓ ⊔ ℓ') where
  [_] : x ~ z → Trans _~_ x z
  transitive : ∀ {y} → Trans _~_ x y → Trans _~_ y z → Trans _~_ x z
  trunc : is-prop (Trans _~_ x z)
```

<!--
```agda
instance
  Trans-H-Level : ∀ {x y} {n} → H-Level (Trans R x y) (suc n)
  Trans-H-Level = prop-instance trunc
```
-->

```agda
Trans-elim
  : (P : ∀ (x y : A) → Trans R x y → Type ℓ'')
  → (∀ {x y} → (r : R x y) → P x y [ r ])
  → (∀ {x y z} → (r+ : Trans R x y) → (s+ : Trans R y z)
     → P x y r+ → P y z s+
     → P x z (transitive r+ s+))
  → (∀ {x y} → (r+ : Trans R x y) → is-prop (P x y r+))
  → ∀ {x y} → (r+ : Trans R x y) → P x y r+
Trans-elim {R = R} P prel ptrans pprop r+ = go r+ where
  go : ∀ {x y} → (r+ : Trans R x y) → P x y r+
  go [ r ] = prel r
  go (transitive r+ s+) = ptrans r+ s+ (go r+) (go s+)
  go (trunc r+ r+' i) =
    is-prop→pathp (λ i → pprop (trunc r+ r+' i)) (go r+) (go r+') i

Trans-rec
  : (∀ {x y} → (r : R x y) → X)
  → (X → X → X)
  → is-prop X
  → ∀ {x y} → Trans R x y → X
Trans-rec {R = R} {X = X} prel ptrans pprop r+ = go r+ where
  go : ∀ {x y} → Trans R x y → X
  go [ r ] = prel r
  go (transitive r+ s+) = ptrans (go r+) (go s+)
  go (trunc r+ r+' i) = pprop (go r+) (go r+') i
```

If the original relation is reflexive or symmetric, then so is the
transitive closure.

```agda
trans-clo-reflexive
  : (∀ x → R x x)
  → ∀ x → Trans R x x
trans-clo-reflexive is-refl x = [ is-refl x ]

trans-clo-symmetric
  : (∀ {x y} → R x y → R y x)
  → ∀ {x y} → Trans R x y → Trans R y x
trans-clo-symmetric is-sym [ r ] =
  [ is-sym r ]
trans-clo-symmetric is-sym (transitive r+ r+') =
  transitive (trans-clo-symmetric is-sym r+') (trans-clo-symmetric is-sym r+)
trans-clo-symmetric is-sym (trunc r+ r+' i) =
  trunc (trans-clo-symmetric is-sym r+) (trans-clo-symmetric is-sym r+') i
```