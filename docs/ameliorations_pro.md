# Améliorations pour rendre le jeu plus pro

État des lieux réalisé le 16 juillet 2026, par ordre d'impact décroissant.
L'ordre d'attaque recommandé est en fin de document.

## 1. Le son — le plus gros manque, de loin

Il n'y a **aucun audio dans tout le projet** : pas une note, pas un bruitage.
C'est ce qui sépare le plus une démo d'un jeu pro, surtout pour un jeu
d'ambiance comme celui-ci. Le minimum transformateur :

- bruit de **page tournée** (l'animation existe déjà, elle est muette) ;
- **grattement de plume** discret pendant la machine à écrire ;
- **nappe d'ambiance** par contexte (fleuve, village, cérémonie — les
  illustrations donnent déjà le découpage) ;
- feedback léger sur les choix et les clics de zones.

## 2. Les zones interactives sont invisibles

Un joueur ne peut pas deviner qu'on peut cliquer dans les illustrations :
rien ne le signale. Un **curseur qui change au survol** + une **lueur
subtile** sur la zone (ou un scintillement ponctuel à l'apparition de la
planche) rendrait la mécanique découvrable sans la spoiler. C'est du polish
à fort effet de levier : c'est la mécanique la plus originale du jeu.

## 3. Livrer de vrais builds

Pas d'`export_presets.cfg`, le projet s'appelle encore « Untold (Godot) »
et l'icône est celle par défaut de Godot. Pour être pro :

- préset **Windows + Web** (le format s'y prête très bien) ;
- icône et nom définitifs ;
- export automatisé.

Le build Web est aussi le meilleur outil de playtest — un lien à envoyer.

## 4. CI sur GitHub

Une belle batterie de tests headless existe déjà (`tools/test_*.tscn`,
`validate_story.gd`) mais rien ne les lance automatiquement. Une GitHub
Action qui exécute les tests + la validation d'histoire à chaque push sur
`dev`, c'est une matinée de travail et ça évite les régressions
silencieuses (deux ont été corrigées sur la seule reprise de partie).

## 5. Robustesse de la sauvegarde

`user://progress.json` est réécrit en entier à chaque événement, sans
écriture atomique : un crash pendant l'écriture = sauvegarde corrompue =
tout perdu (le code repart de zéro en silence). À faire :

- écrire dans un fichier temporaire puis renommer, plus une copie `.bak` —
  trivial et standard pro ;
- persister les variables `@set` à la reprise (l'histoire n'en utilise pas
  encore, mais le jour où elle en utilisera, elles seront perdues au
  checkpoint).

## 6. Confort et accessibilité

Vitesse de frappe et parallaxe sont déjà réglables — il manque :

- **taille du texte** ;
- plein écran / fenêtré ;
- un **mode « tout afficher »** pour ceux qui ne veulent pas de machine à
  écrire ;
- sliders de volume (quand l'audio existera).

C'est le genre d'options dont l'absence se remarque immédiatement dans les
reviews.

## 7. Habillage des entrées/sorties

- un **écran titre** (même sobre : le bureau, le logo, « appuyez pour
  ouvrir la bibliothèque ») ;
- des **crédits** (auteur, développeur, artistes des illustrations) ;
- une confirmation avant « Recommencer ».

Le hub-bibliothèque est déjà réussi ; il manque juste ce qui l'encadre.

## Mention honorable : la localisation

Tout le texte moteur est en français en dur. Si un jour le jeu vise plus
large, passer l'UI par `tr()` coûte peu maintenant et beaucoup plus tard.

## Ordre d'attaque recommandé

1. **Le son** — impact émotionnel immédiat.
2. **Les signifiants de zones** — la mécanique phare mérite d'être vue.
3. **Sauvegarde atomique + CI** — filet de sécurité.
