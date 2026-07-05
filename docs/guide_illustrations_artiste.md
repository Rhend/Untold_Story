# Guide illustrations — à l'intention de l'artiste

Ce document explique comment sont construites les illustrations à **parallaxe**
(effet de profondeur quand la souris bouge) et surtout **quelle marge de
sécurité prévoir** dans tes images. Aucune connaissance de code n'est requise.

## 1. Le principe : un décor en 9 plans

Une illustration animée est découpée en **calques** superposés, numérotés de
**1 à 9**. Chaque calque est un plan de profondeur :

- Le calque **5** est le **pivot** : il ne bouge jamais, c'est le plan de
  référence sur lequel la scène est cadrée.
- Les calques **1 à 4** sont **devant** le pivot (premiers plans).
- Les calques **6 à 9** sont **derrière** le pivot (arrière-plans).

Quand le joueur déplace la souris, les calques glissent : **plus un calque est
loin du pivot, plus il bouge**. Les plans devant et les plans derrière glissent
en sens opposés — c'est ce qui donne l'impression de relief.

> Le numéro du calque sert donc à deux choses à la fois : l'ordre d'empilement
> (1 devant, 9 derrière) **et** l'amplitude de son mouvement.

Tu n'es pas obligé·e d'utiliser les 9 numéros : une illustration peut n'avoir
que les calques 4, 5 et 6, par exemple. Ce qui compte, c'est **l'écart entre le
calque le plus éloigné et le pivot** (voir plus bas).

## 2. Deux types de cadrage

- **Cover / paysage (Landscape)** : l'image **remplit tout l'écran**, quitte à
  déborder. Le parallaxe puise dans ce débordement, donc **aucune perte de
  cadrage** : tu n'as pas de marge particulière à prévoir.
- **Contain / portrait (Portrait)** : l'image est affichée **en entier**,
  cadrée dans sa zone (mise en page « livre », demi-page). C'est ici que la
  marge de sécurité ci-dessous s'applique **si** le parallaxe est activé.

## 3. La marge de sécurité (uniquement en cadrage *contain* + parallaxe)

Quand une illustration en cadrage **contain** a le **parallaxe activé**, le
moteur agrandit légèrement les calques pour que, même au décalage maximum de la
souris, aucun **bord vide** n'apparaisse. Conséquence : un **léger zoom** et un
**petit rognage** des bords de l'image. C'est **normal et assumé** (c'est le
prix du parallaxe combiné au cadrage « image entière »), ce n'est pas un défaut.

Il faut donc **éloigner les éléments importants des bords** de cette marge, afin
qu'ils ne soient jamais rognés. Voici comment la calculer.

### La formule

```
marge (px, par bord) = distance_max_au_pivot × gain + marge_fixe
```

- **distance_max_au_pivot** = le plus grand écart, en numéros de calque, entre
  ton calque le plus éloigné et le pivot (5).
  Exemple : si tes calques vont de 1 à 9, la distance max est 4 (de 5 à 1, ou de
  5 à 9).
- **gain** = amplitude globale du parallaxe. Valeur par défaut : **9,0**
  (réglable dans les paramètres du jeu).
- **marge_fixe** = petite sécurité supplémentaire. Valeur actuelle : **8 px**.

Les distances sont exprimées sur la **résolution de référence : 1920 px de
large**.

### Exemples chiffrés (avec les valeurs par défaut : pivot 5, gain 9,0, marge fixe 8)

| Calques utilisés | Distance max au pivot | Marge de sécurité par bord |
|---|---|---|
| 1 à 9 | 4 | 4 × 9,0 + 8 = **~44 px** |
| 4 à 6 | 1 | 1 × 9,0 + 8 = **~17 px** |
| 3 à 7 | 2 | 2 × 9,0 + 8 = **~26 px** |

> ⚠️ **Il n'y a pas un seul chiffre universel.** La marge dépend de
> l'**étalement réel des calques de chaque illustration**. Une illustration très
> profonde (calques 1 à 9) a besoin de ~44 px ; une illustration peu profonde
> (calques 4 à 6) n'a besoin que de ~17 px. Calcule-la illustration par
> illustration avec la formule ci-dessus.

## 4. En résumé

- Illustration **paysage / cover** → **aucune marge** à prévoir, le parallaxe
  est « gratuit » côté cadrage.
- Illustration **portrait / contain avec parallaxe** → prévois la **marge de
  sécurité** calculée avec la formule, sur **chaque bord**, à 1920 px de
  référence. Les éléments importants doivent rester à l'intérieur de cette marge.
- Illustration **portrait / contain sans parallaxe** (illustration figée) →
  **aucune marge**, aucun rognage : l'image est montrée à 100 %. C'est le
  réglage actuel des portraits existants (Démon, Orante, Statue de Sîn,
  Halî-Ammi), pour lesquels on a préféré un cadrage intégral sans mouvement.

> Le choix « parallaxe activé ou non » pour une illustration se décide avec la
> personne qui intègre l'illustration au jeu. Ce guide sert à savoir **quelle
> marge laisser dans ton image** une fois ce choix fait.
