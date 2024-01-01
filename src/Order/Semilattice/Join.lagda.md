<!--
```agda
open import Cat.Functor.Subcategory
open import Cat.Prelude

open import Data.Fin.Indexed
open import Data.Fin.Finite
open import Data.Fin.Base hiding (_≤_)

open import Order.Diagram.Bottom
open import Order.Diagram.Join
open import Order.Diagram.Lub
open import Order.Base

import Cat.Reasoning

import Order.Diagram.Join.Reasoning as Joins
import Order.Reasoning
```
-->

```agda
module Order.Semilattice.Join where
```

# Join semilattices {defines=join-semilattice}

```agda
record is-join-semilattice {o ℓ} (P : Poset o ℓ) : Type (o ⊔ ℓ) where
  field
    has-joins  : Has-joins P
    has-bottom : Bottom P

  open Order.Reasoning P
  open Joins has-joins public
  open Bottom has-bottom using (bot; ¡) public

  ⋃ᶠ : ∀ {n} (f : Fin n → Ob) → Ob
  ⋃ᶠ {0}     f = bot
  ⋃ᶠ {1}     f = f fzero
  ⋃ᶠ {suc n} f = f fzero ∪ ⋃ᶠ (λ i → f (fsuc i))

  ⋃ᶠ-inj : ∀ {n} {f : Fin n → Ob} → (i : Fin n) → f i ≤ ⋃ᶠ f
  ⋃ᶠ-inj {1}           fzero    = ≤-refl
  ⋃ᶠ-inj {suc (suc n)} fzero    = l≤∪
  ⋃ᶠ-inj {suc (suc n)} (fsuc i) = ≤-trans (⋃ᶠ-inj i) r≤∪

  ⋃ᶠ-universal
    : ∀ {n} {f : Fin n → Ob} (x : Ob)
    → (∀ i → f i ≤ x) → ⋃ᶠ f ≤ x
  ⋃ᶠ-universal {0} x p = ¡
  ⋃ᶠ-universal {1} x p = p fzero
  ⋃ᶠ-universal {suc (suc n)} x p =
    ∪-universal _ (p fzero) (⋃ᶠ-universal x (p ⊙ fsuc))

  Finite-lubs : ∀ {n} (f : Fin n → Ob) → Lub P f
  Finite-lubs f .Lub.lub = ⋃ᶠ f
  Finite-lubs f .Lub.has-lub .is-lub.fam≤lub = ⋃ᶠ-inj
  Finite-lubs f .Lub.has-lub .is-lub.least = ⋃ᶠ-universal
```

```agda
abstract
  is-join-semilattice-is-prop
    : ∀ {o ℓ} {P : Poset o ℓ}
    → is-prop (is-join-semilattice P)
  is-join-semilattice-is-prop {P = P} = Iso→is-hlevel 1 eqv hlevel! where
    open Order.Diagram.Join P using (H-Level-Join)
    open Order.Diagram.Bottom P using (H-Level-Bottom)
    unquoteDecl eqv = declare-record-iso eqv (quote is-join-semilattice)
```

<!--
```agda
private
  variable
    o ℓ o' ℓ' : Level
    P Q R : Poset o ℓ

instance
  H-Level-is-join-semilattice : ∀ {n} → H-Level (is-join-semilattice P) (suc n)
  H-Level-is-join-semilattice = prop-instance is-join-semilattice-is-prop
```
-->

```agda
record is-join-slat-hom
  {P : Poset o ℓ} {Q : Poset o' ℓ'}
  (f : Monotone P Q)
  (P-slat : is-join-semilattice P)
  (Q-slat : is-join-semilattice Q)
  : Type (o ⊔ ℓ')
  where
  no-eta-equality
  private
    module P = Poset P
    module Pₗ = is-join-semilattice P-slat
    module Q = Order.Reasoning Q
    module Qₗ = is-join-semilattice Q-slat
    open is-join
  field
    ∪-≤ : ∀ x y → f # (x Pₗ.∪ y) Q.≤ (f # x) Qₗ.∪ (f # y)
    bot-≤ : f # Pₗ.bot Q.≤ Qₗ.bot

  pres-∪ : ∀ x y → f # (x Pₗ.∪ y) ≡ (f # x) Qₗ.∪ (f # y)
  pres-∪ x y =
    Q.≤-antisym
      (∪-≤ x y)
      (Qₗ.∪-universal (f # (x Pₗ.∪ y))
        (f .pres-≤ Pₗ.l≤∪)
        (f .pres-≤ Pₗ.r≤∪))

  pres-bot : f # Pₗ.bot ≡ Qₗ.bot
  pres-bot = Q.≤-antisym bot-≤ Qₗ.¡

  pres-joins
    : ∀ {x y m}
    → is-join P x y m
    → is-join Q (f # x) (f # y) (f # m)
  pres-joins join .is-join.l≤join = f .pres-≤ (join .l≤join)
  pres-joins join .is-join.r≤join = f .pres-≤ (join .r≤join)
  pres-joins {x = x} {y = y} {m = m} join .is-join.least lb fx≤lb fy≤lb =
    f # m            Q.≤⟨ f .pres-≤ (join .least (x Pₗ.∪ y) Pₗ.l≤∪ Pₗ.r≤∪) ⟩
    f # (x Pₗ.∪ y)   Q.≤⟨ ∪-≤ x y ⟩
    f # x Qₗ.∪ f # y Q.≤⟨ Qₗ.∪-universal lb fx≤lb fy≤lb ⟩
    lb               Q.≤∎

  pres-bottoms
    : ∀ {b}
    → is-bottom P b
    → is-bottom Q (f # b)
  pres-bottoms {b = b} b-bot x =
    f # b      Q.≤⟨ f .pres-≤ (b-bot Pₗ.bot) ⟩
    f # Pₗ.bot Q.≤⟨ bot-≤ ⟩
    Qₗ.bot     Q.≤⟨ Qₗ.¡ ⟩
    x          Q.≤∎

  pres-⋃ᶠ : ∀ {n} (k : Fin n → ⌞ P ⌟) → f # (Pₗ.⋃ᶠ k) ≡ Qₗ.⋃ᶠ (apply f ⊙ k)
  pres-⋃ᶠ {n = 0} k = pres-bot
  pres-⋃ᶠ {n = 1} k = refl
  pres-⋃ᶠ {n = suc (suc n)} k =
    f # (k fzero Pₗ.∪ Pₗ.⋃ᶠ (k ⊙ fsuc))       ≡⟨ pres-∪ _ _ ⟩
    f # (k fzero) Qₗ.∪ f # (Pₗ.⋃ᶠ (k ⊙ fsuc)) ≡⟨ ap₂ Qₗ._∪_ refl (pres-⋃ᶠ (k ⊙ fsuc)) ⟩
    Qₗ.⋃ᶠ (apply f ⊙ k)                       ∎

  pres-fin-lub
    : ∀ {n} (k : Fin n → ⌞ P ⌟) (x : ⌞ P ⌟)
    → is-lub P k x
    → is-lub Q (λ x → f # (k x)) (f # x)
  pres-fin-lub k x P-lub .is-lub.fam≤lub i =
    f .pres-≤ (is-lub.fam≤lub P-lub i)
  pres-fin-lub k x P-lub .is-lub.least ub' fk≤ub =
    f # x               Q.≤⟨ f .pres-≤ (is-lub.least P-lub (Pₗ.⋃ᶠ k) Pₗ.⋃ᶠ-inj) ⟩
    f # Pₗ.⋃ᶠ k         Q.=⟨ pres-⋃ᶠ k ⟩
    Qₗ.⋃ᶠ (apply f ⊙ k) Q.≤⟨ Qₗ.⋃ᶠ-universal ub' fk≤ub ⟩
    ub'                 Q.≤∎

  pres-finite-lub
    : ∀ {ℓᵢ} {I : Type ℓᵢ}
    → Finite I
    → (k : I → ⌞ P ⌟)
    → (x : ⌞ P ⌟)
    → is-lub P k x
    → is-lub Q (λ x → f # (k x)) (f # x)
  pres-finite-lub I-finite k x P-lub =
    ∥-∥-rec (is-lub-is-prop Q)
      (λ enum →
        cast-is-lub Q (enum e⁻¹) (λ _ → refl) $
        pres-fin-lub (k ⊙ Equiv.from enum) x $
        cast-is-lub P enum (λ x → sym (ap k (Equiv.η enum x))) P-lub)
      (I-finite .enumeration)

  pres-finitely-indexed-lub
    : ∀ {ℓᵢ} {I : Type ℓᵢ}
    → is-finitely-indexed I
    → (k : I → ⌞ P ⌟)
    → (x : ⌞ P ⌟)
    → is-lub P k x
    → is-lub Q (λ x → f # (k x)) (f # x)
  pres-finitely-indexed-lub I-fin-indexed k x P-lub =
    □-rec! {pa = is-lub-is-prop Q}
      (λ cov →
        cover-reflects-is-lub Q (Finite-cover.is-cover cov) $
        pres-fin-lub (k ⊙ Finite-cover.cover cov) x $
        cover-preserves-is-lub P (Finite-cover.is-cover cov) P-lub)
      I-fin-indexed

open is-join-slat-hom
```

<!--
```agda
abstract
  is-join-slat-hom-is-prop
    : ∀ {P : Poset o ℓ} {Q : Poset o' ℓ'} {f : Monotone P Q} {P-slat Q-slat}
    → is-prop (is-join-slat-hom f P-slat Q-slat)
  is-join-slat-hom-is-prop =
    Iso→is-hlevel 1 eqv hlevel!
    where unquoteDecl eqv = declare-record-iso eqv (quote is-join-slat-hom)

instance
  H-Level-is-join-slat-hom
    : ∀ {f : Monotone P Q} {P-slat Q-slat n}
    → H-Level (is-join-slat-hom f P-slat Q-slat) (suc n)
  H-Level-is-join-slat-hom = prop-instance is-join-slat-hom-is-prop
```
-->

## The category of join-semilattices

```agda
id-join-slat-hom
  : ∀ (Pₗ : is-join-semilattice P)
  → is-join-slat-hom idₘ Pₗ Pₗ
id-join-slat-hom {P = P} _ .∪-≤ _ _ = Poset.≤-refl P
id-join-slat-hom {P = P} _ .bot-≤ = Poset.≤-refl P

∘-join-slat-hom
  : ∀ {Pₗ Qₗ Rₗ} {f : Monotone Q R} {g : Monotone P Q}
  → is-join-slat-hom f Qₗ Rₗ
  → is-join-slat-hom g Pₗ Qₗ
  → is-join-slat-hom (f ∘ₘ g) Pₗ Rₗ
∘-join-slat-hom {R = R} {f = f} {g = g} f-pres g-pres .∪-≤ x y =
  R .Poset.≤-trans (f .pres-≤ (g-pres .∪-≤ x y)) (f-pres .∪-≤ (g # x) (g # y))
∘-join-slat-hom {R = R} {f = f} {g = g} f-pres g-pres .bot-≤ =
  R .Poset.≤-trans (f .pres-≤ (g-pres .bot-≤)) (f-pres .bot-≤)
```

```agda
Join-slats-subcat : ∀ o ℓ → Subcat (Posets o ℓ) (o ⊔ ℓ) (o ⊔ ℓ)
Join-slats-subcat o ℓ .Subcat.is-ob = is-join-semilattice
Join-slats-subcat o ℓ .Subcat.is-hom = is-join-slat-hom
Join-slats-subcat o ℓ .Subcat.is-hom-prop = hlevel!
Join-slats-subcat o ℓ .Subcat.is-hom-id = id-join-slat-hom
Join-slats-subcat o ℓ .Subcat.is-hom-∘ = ∘-join-slat-hom

Join-slats : ∀ o ℓ → Precategory (lsuc o ⊔ lsuc ℓ) (o ⊔ ℓ)
Join-slats o ℓ = Subcategory (Join-slats-subcat o ℓ)
```

```agda
module Join-slats {o} {ℓ} = Cat.Reasoning (Join-slats o ℓ)

Forget-join-slat : ∀ {o ℓ} → Functor (Join-slats o ℓ) (Posets o ℓ)
Forget-join-slat = Forget-subcat

Join-semilattice : ∀ o ℓ → Type _
Join-semilattice o ℓ = Join-slats.Ob {o} {ℓ}
```