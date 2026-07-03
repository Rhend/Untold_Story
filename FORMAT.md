# Format narratif `.untold` — spécification (L0)

Format texte maison, **source unique** lue par le jeu (runtime) ET, plus tard,
par le plugin de visualisation (Phase 2). Conçu pour couvrir le périmètre réel
de l'ancien projet Ink, sans en hériter la complexité inutile.

## Principes
- Un fichier `.untold` = une **histoire**, composée de **nœuds**.
- Lecture **ligne par ligne**, espaces de début/fin ignorés (indentation libre).
- Encodage **UTF-8** (accents et signes cunéiformes acceptés).

## Syntaxe

| Élément | Syntaxe | Exemple |
|---|---|---|
| Commentaire | `// ...` | `// aiguillage initial` |
| Variable globale | `@var nom = valeur` | `@var character = ""` |
| Nœud | `:: id` | `:: prologue2` |
| Tags | `#Tag #Tag` | `#Nadîtum #Soldat` |
| Texte narratif | toute autre ligne | `Les flots emportent la barque.` |
| Choix | `* [Texte] -> cible` | `* [Le dieu lunaire] -> prologue2` |
| Saut | `-> cible` | `-> fin` / `-> END` |
| Saut conditionnel | `{ var == "valeur" -> cible }` | `{ type == "Mystique" -> route_myst }` |
| Garde | `{ cond } instruction` | `{ character == "Soldat" } Tu dégaines.` |
| Affectation | `@set nom = valeur` | `@set visible = "true"` |
| Commande moteur | `@nom("arg", ...)` | `@illustration("Statue de Sîn")` |
| Glue | `<>` en début/fin de ligne | `Tu as dormi <>` |

## Gardes (conditions sur une ligne)
Toute instruction (texte, choix, saut, commande, affectation) peut être
préfixée d'une **garde** : `{ cond } instruction`. Si la condition est fausse,
la ligne est ignorée. Conditions disponibles :
- `var == "valeur"` / `var != "valeur"` — comparaison de variable ;
- `visited(id)` / `!visited(id)` — le joueur a (ou non) déjà traversé le nœud ;
- combinaisons : `and` lie des conditions, `or` sépare des groupes
  (précédence usuelle : `a or b and c` = `a ou (b et c)`, pas de parenthèses).

Exemple : `{ character == "Prêtresse" and visited(chapelle) } * [Prier] -> rite`

## Glue
Une ligne de texte terminée (ou commencée) par `<>` se colle à la ligne de
texte suivante (resp. précédente) **sans saut de ligne**. Combinée aux gardes,
elle permet de composer une phrase à partir de fragments conditionnels :
```
Tu as dormi <>
{ character == "Nadîtum" } longtemps, tes gens empaquettent tes affaires.
{ character != "Nadîtum" } peu, l'auberge était bruyante.
```

## Sémantique d'exécution
- Le moteur entre dans le nœud d'entrée (`start` par défaut) et exécute ses
  instructions de haut en bas.
- Le **texte s'accumule** ; en suivant un saut (`->`) ou un saut conditionnel
  vrai, le moteur **enchaîne sur le nœud cible sans rcompter le texte**
  (comportement "glue" : plusieurs nœuds peuvent composer un même écran).
- L'accumulation s'arrête à un **point de choix** (`*`) ou à une **fin**
  (`-> END`, ou nœud sans suite).
- Dès qu'au moins un choix est ouvert, les sauts suivants sont **ignorés**
  (sémantique Ink : le flux s'arrête aux choix).
- `END` est un nœud réservé qui termine l'histoire.
- Le moteur retient les nœuds traversés → conditions `visited(id)`.

## Correspondance avec l'ancien projet Ink
| Ink | `.untold` |
|---|---|
| `=== knot ===` | `:: id` |
| `-> knot` / `-> END` | `-> id` / `-> END` |
| `+ [texte] -> knot` | `* [texte] -> id` |
| `{var: - "x": -> a - else: -> b}` | suite de `{ var == "x" -> a }` puis `-> b` |
| `{var: - "x": texte}` (texte conditionnel) | `{ var == "x" } texte` |
| `{knot: ...}` (compte de lectures) | `{ visited(knot) } ...` |
| `*{cond} [texte] -> a` (choix conditionnel) | `{ cond } * [texte] -> a` |
| `<>` (glue) | `<>` |
| `#tag` | `#tag` |
| `VAR x = ...` | `@var x = ...` |
| `EXTERNAL f(...)` | `@f(...)` (commande moteur) |

La conversion est automatisée par `tools/ink2untold.mjs` :
`node tools/ink2untold.mjs entrée.ink sortie.untold`. Les appels
`-> minigame("Nom", succès, échec)` deviennent des nœuds relais qui émettent
`@minigame(...)` puis enchaînent sur la branche succès (mécanique à venir).

## Limites actuelles (à étendre)
- Pas encore : parenthèses dans les gardes, variables numériques,
  texte conditionnel inline (le convertisseur les expanse en lignes gardées).
  À ajouter selon les besoins réels.
