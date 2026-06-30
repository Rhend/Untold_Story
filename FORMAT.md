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
| Affectation | `@set nom = valeur` | `@set visible = "true"` |
| Commande moteur | `@nom("arg", ...)` | `@illustration("Statue de Sîn")` |

## Sémantique d'exécution
- Le moteur entre dans le nœud d'entrée (`start` par défaut) et exécute ses
  instructions de haut en bas.
- Le **texte s'accumule** ; en suivant un saut (`->`) ou un saut conditionnel
  vrai, le moteur **enchaîne sur le nœud cible sans rcompter le texte**
  (comportement "glue" : plusieurs nœuds peuvent composer un même écran).
- L'accumulation s'arrête à un **point de choix** (`*`) ou à une **fin**
  (`-> END`, ou nœud sans suite).
- `END` est un nœud réservé qui termine l'histoire.

## Correspondance avec l'ancien projet Ink
| Ink | `.untold` |
|---|---|
| `=== knot ===` | `:: id` |
| `-> knot` / `-> END` | `-> id` / `-> END` |
| `+ [texte] -> knot` | `* [texte] -> id` |
| `{var: - "x": -> a - else: -> b}` | suite de `{ var == "x" -> a }` puis `-> b` |
| `#tag` | `#tag` |
| `VAR x = ...` | `@var x = ...` |
| `EXTERNAL f(...)` | `@f(...)` (commande moteur) |

## Limites actuelles (à étendre)
- Conditions : uniquement l'égalité `==` sur une variable.
- Pas encore : opérateurs `!=`/`and`/`or`, texte conditionnel inline,
  choix conditionnels, variables numériques. À ajouter selon les besoins réels.
