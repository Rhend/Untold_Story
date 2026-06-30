# Untold — version Godot

Réécriture native (GDScript, Godot 4.x) du jeu narratif « Untold », initialement
fait sous Unity avec Ink. **Aucun plugin tiers** : tout est reconstruit nativement.

> La version Unity d'origine sert de **spécification de référence** et de **banque
> de contenu**, pas de code à porter. Voir `../ANALYSE_PORTAGE_GODOT.md`.

## État d'avancement
- [x] **L0 — Format narratif maison** (`FORMAT.md`) : langage `.untold`, source unique.
- [x] **L1 — Runtime narratif** : parser + moteur (nœuds, choix, variables,
  sauts conditionnels, tags, commandes). Source unique jeu + future visualisation.
- [x] **L2 (amorce) — UI dialogue** : affichage texte avec effet machine à écrire,
  boutons de choix, en-tête de nœud.
- [ ] L3 — Sélection de personnages (pilote le filtrage par tags)
- [ ] L4 — Illustrations à calques + parallaxe + zones interactives
- [ ] L5 — (mini-jeux : hors périmètre pour l'instant, simple hook prévu)
- [ ] L6 — Sauvegarde
- [ ] L7 — Plugin de visualisation de l'histoire (Phase 2, lit le `.untold`)

## Lancer
Ouvrir le dossier `Godot_Untold/` dans Godot 4.x et lancer (F5).
La scène `scenes/main.tscn` joue `data/stories/sample.untold`.

Pour tester les embranchements, modifier dans `core/game/game_state.gd` :
`character_type` (`"Nadîtum"`, `"Soldat"`, `"Prêtresse"`) et
`character_attribute` (`"Physique"`, `"Social"`, `"Mystique"`).

## Architecture
```
core/
  narrative/   story.gd, story_node.gd, story_choice.gd  (modèle de données)
               story_parser.gd                           (.untold -> Story)
               story_runner.gd                           (moteur d'exécution)
  game/        game_state.gd                              (autoload état global)
data/
  stories/     sample.untold                              (contenu)
scenes/
  main.tscn / main.gd                                     (démo jouable)
```

Découplage strict : le moteur ne connaît pas l'UI, il ne fait qu'émettre des
signaux (`display_text`, `present_choices`, `command`, `story_ended`).

## Branches git
`main` (stable) ← `preprod` (pré-production) ← `dev` (travail courant).
Tout le développement se fait sur `dev`.
