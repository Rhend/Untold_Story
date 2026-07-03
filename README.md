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
- [x] **L3 — Sélection de personnages** : écran de choix (type + attribut), pilote
  le filtrage par tags.
- [x] **L4 — Illustrations à calques + parallaxe** — ⚠ la parallaxe n'est pas
  encore fidèle à la référence (cadrage trop zoomé), à retravailler.
- ~~L5 — Mini-jeux~~ : **abandonné** (hors périmètre).
- [x] **L6 — Progression narrative persistante** (autoload `Progress`,
  `user://progress.json`) : pour chaque nœud, quels personnages l'ont visité et,
  pour chaque point de choix, quelles réponses ont déjà été choisies (et par qui)
  ou pas encore. Affiché en jeu : compteur de nœuds découverts, mention
  « déjà lu / lu par X », réponses déjà choisies cochées et atténuées.
- [ ] L7 — Plugin de visualisation de l'histoire (Phase 2, lit le `.untold`)
  — **prochaine étape**.

## Lancer
Ouvrir le dossier du projet dans Godot 4.x et lancer (F5).
La scène principale est `scenes/character_selection.tscn` (choix du personnage
et de l'attribut), qui enchaîne sur `scenes/story.tscn` jouant
`data/stories/act1_sc1.untold`.

## Architecture
```
core/
  narrative/     story.gd, story_node.gd, story_choice.gd  (modèle de données)
                 story_parser.gd                           (.untold -> Story)
                 story_runner.gd                           (moteur d'exécution)
  game/          game_state.gd        (autoload GameState : état global)
                 progress_tracker.gd  (autoload Progress : progression persistante)
                 settings_menu.gd     (autoload SettingsMenu : menu Échap)
                 character_data.gd    (données d'un personnage jouable)
  illustration/  illustration_*.gd    (calques, parallaxe, bibliothèque)
data/
  stories/       act1_sc1.untold, sample.untold            (contenu)
scenes/
  character_selection.tscn / story.tscn                    (jeu)
```

Découplage strict : le moteur ne connaît pas l'UI, il ne fait qu'émettre des
signaux (`display_text`, `present_choices`, `command`, `story_ended`).

## Branches git
`main` (stable) ← `preprod` (pré-production) ← `dev` (travail courant).
Tout le développement se fait sur `dev`.
