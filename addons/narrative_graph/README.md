# Guide de l'outil narratif — à l'intention de l'autrice

Ce guide t'explique, pas à pas, comment écrire et organiser toute une histoire
**sans quitter Godot** et **sans jamais ouvrir un fichier texte à la main**.
Aucune connaissance de code n'est requise. Prends-le dans l'ordre la première
fois : chaque section s'appuie sur la précédente.

> En cas de doute à n'importe quel moment : le bouton **↶** (en haut) annule ta
> dernière modification. Tu ne peux rien casser définitivement.

---

## 1. Ouvrir l'outil

1. Lance **Godot** et ouvre le projet Untold.
2. Regarde tout en haut au **centre** de la fenêtre : à côté de `2D`, `3D` et
   `Script`, il y a un onglet **`Narratif`**. Clique dessus.
3. L'outil s'ouvre : un grand **graphe** à gauche, un **inspecteur** à droite
   (vide pour l'instant), et deux barres de boutons en haut.
4. Dans le menu déroulant **« Histoire : »**, choisis le fichier sur lequel tu
   veux travailler :
   - `demo_format.untold` — une petite histoire d'exemple, **hors jeu**,
     parfaite pour t'entraîner sans risque ;
   - `act1_sc1.untold` — le vrai acte 1 de Mésopotamia.

**Pour tout ce guide, ouvre `demo_format.untold`** : tu pourras y faire
n'importe quoi, elle ne fait pas partie du jeu.

---

## 2. Lire le graphe

Chaque **boîte** du graphe est un **nœud** : un passage de l'histoire (quelques
lignes de texte que le joueur lit d'un coup). Les **fils** entre les boîtes
sont les chemins possibles.

Dans la barre de titre d'un nœud, tu peux voir :

| Élément | Sens |
|---|---|
| Le nom (ex. `prologue2`) | L'identifiant du nœud — son « nom de code » |
| Une petite **image** | Ce nœud affiche une illustration |
| **⊘** | Ce nœud est exclu de la carte de progression du jeu |
| **▾ / ▸** | Replie ou déplie tout ce qui dépend de ce nœud |

Sous le titre : la première ligne de texte du passage, puis **une ligne par
sortie**. La couleur du petit rond à droite t'indique la nature de la sortie :

- **jaune** — un choix proposé au joueur (`▸ Le dieu lunaire`) ;
- **gris-bleu** — un saut automatique vers un autre nœud ;
- **violet** — un saut conditionnel (le moteur y va seulement si une condition
  est vraie). Le préfixe `{…}` signale une condition.

**Pour te déplacer** : molette = défiler (Maj + molette = horizontal),
Ctrl + molette = zoomer, et maintiens le **clic du milieu** pour déplacer la
vue. La mini-carte en bas à droite montre où tu es.

**Déplace les nœuds** en les faisant glisser : la disposition est enregistrée
toute seule, et c'est la **même** que celle de la carte de progression que le
joueur voit en jeu — ranger ton graphe, c'est aussi ranger sa carte.

---

## 3. Ta première modification (5 minutes)

1. Clique sur le nœud **`fin`**. L'inspecteur de droite se remplit.
2. Repère le volet **« Contenu (source .untold) »** : c'est le texte réel du
   passage, tel qu'écrit dans le fichier.
3. Change une phrase, par exemple ajoute une ligne
   `Le soleil se couche sur l'Euphrate.`
4. Clique **« Enregistrer le contenu »**. C'est écrit dans le fichier, et le
   graphe se met à jour.
5. Maintenant clique **↶** en haut : ta modification est annulée, le fichier
   est revenu exactement à son état d'avant. **↷** la rétablit.

C'est le cycle de travail de base : *cliquer un nœud → écrire → Enregistrer*.

---

## 4. Créer une scène de A à Z

Objectif : ajouter un nœud « taverne » accessible depuis `prologue3`.

1. Clique **« + Nouveau nœud »** dans la barre du haut.
2. Donne-lui un id : `taverne`. Les règles : **lettres, chiffres et `_`
   uniquement, pas d'espace ni d'accent** (c'est un nom de code, pas le titre —
   le joueur ne le verra jamais si tu lui donnes un titre, voir §5).
3. Clique **Créer** : le nœud apparaît au centre de ta vue, déjà sélectionné.
4. Dans **« Contenu »**, remplace `Texte à écrire…` par ton passage, puis
   **Enregistrer le contenu**.
5. Il faut maintenant **y mener**. Clique sur `prologue3`, va dans le volet
   **« Sorties »**, section **« Ajouter une sortie »** :
   - écris le texte du choix, ex. `Entrer dans la taverne` ;
   - choisis la cible `taverne` dans le menu déroulant ;
   - clique **Ajouter**. Le fil apparaît dans le graphe.
6. Enfin, donne une **suite** à ta taverne : sélectionne `taverne`, volet
   **Sorties → Ajouter une sortie**, laisse le texte **vide** (= saut
   automatique) et choisis `fin` comme cible.

Ta scène est jouable. Deux autres façons de créer/modifier des liens :

- **À la souris** : attrape le petit rond d'une sortie (à droite d'un nœud) et
  tire-le jusque sur un autre nœud — le lien est redirigé dans le fichier.
- **Au clavier** : dans le volet Sorties, chaque sortie a un champ avec le nom
  de sa cible. Tape un autre nom et appuie sur Entrée.

---

## 5. L'inspecteur, volet par volet

Tout ce qui suit apparaît à droite quand un nœud est sélectionné, de haut en
bas.

### Nœud
- **Le champ du nom** : tape un nouveau nom + **Renommer** — tous les liens qui
  pointaient vers lui, toutes les conditions `visited(...)`, la position, le
  commentaire… tout suit automatiquement.
- **« Titre affiché au joueur »** : le joli nom montré en jeu (carte, en-tête de
  page) à la place de l'id technique. Ex. : id `taverne`, titre
  `La taverne du port`. Optionnel.
- Les **tags** et l'extrait du texte, pour se repérer.
- **« Retirer de la carte (#hors_carte) »** : le nœud ne s'affichera jamais sur
  la carte de progression du joueur (pour les nœuds techniques). Sans effet sur
  le récit.
- **« Supprimer ce nœud »** : demande confirmation et t'indique quels nœuds
  pointaient vers lui — leurs liens resteront à corriger (l'outil te les liste).

### Contenu (source .untold)
Le passage lui-même. **Une ligne = une instruction.** L'essentiel :

| Tu écris… | Ça donne… |
|---|---|
| `Le vent se lève.` | Du texte que le joueur lit |
| `* [Ouvrir la porte] -> cave` | Un choix proposé au joueur |
| `-> cave` | Un saut automatique vers le nœud `cave` |
| `-> END` | La fin de l'histoire |
| `// à relire demain` | Un commentaire ignoré par le jeu |

Et pour les systèmes de jeu (compétences, réputation…) :

| Tu écris… | Ça fait… |
|---|---|
| `@set courage = 2` | Pose la valeur d'une variable |
| `@set reputation += 1` | Ajoute 1 (ou `-= 1` pour retirer) |
| `{ courage >= 3 } * [Forcer la porte] -> cave` | Le choix n'apparaît que si `courage` vaut au moins 3 |
| `{ reputation >= 5 -> palais }` | Saute vers `palais` si la condition est vraie, sinon continue |
| `{ visited(temple) } Tu reconnais les lieux.` | Cette ligne ne s'affiche que si le joueur a déjà traversé le nœud `temple` |

Les conditions se combinent avec `and` / `or`, et il existe aussi
`zone_clicked("id")` (le joueur a cliqué une zone d'illustration) et
`has_item("id")` (il possède un objet). La référence complète du langage est
dans **`FORMAT.md`** à la racine du projet.

### Sorties
Chaque sortie du nœud avec sa cible modifiable, plus le formulaire d'ajout vu
au §4.

### Illustration
L'image affichée sur la page de gauche quand le joueur arrive sur ce nœud.
Pour en associer une : ouvre le dock **Système de fichiers** de Godot (en bas à
gauche), trouve le dossier de l'illustration dans
`data/stories/<histoire>/illustrations/`, et **glisse-dépose** une de ses
images (ou le dossier entier) sur la zone prévue du volet. **Retirer** enlève
la commande du nœud. L'aperçu te confirme la bonne image.

### Zones interactives
Pour rendre des endroits d'une illustration **cliquables** par le joueur :
choisis le calque, **clique dans l'aperçu** pour poser les points d'un contour
(3 minimum), **« Terminer la zone »**, donne-lui un id, éventuellement des
lignes de dialogue et/ou un objet à donner, **« Ajouter la zone »**… et
n'oublie pas **« Enregistrer les zones de ce calque »** à la fin.

### Events (commandes moteur)
Volet avancé : les commandes `@...` du nœud. Tu n'en auras normalement pas
besoin — l'illustration a son propre volet.

### Commentaire (privé à l'outil)
Tes notes de travail sur ce nœud (« à réécrire », « demander à Ben »…). Elles
ne sont **jamais** visibles en jeu ni dans le fichier de l'histoire.

---

## 6. Les boutons du haut

**Rangée « Histoire »** :

| Bouton | Effet |
|---|---|
| Recharger | Relit le fichier depuis le disque (si tu l'as modifié ailleurs) |
| + Nouveau nœud | Crée un nœud (§4) |
| **↶ / ↷** | Annuler / rétablir les modifications du fichier (30 niveaux) |
| **Vérifier** | Le check-up complet : liens cassés, nœuds injoignables, noms en double, illustrations inconnues. **Fais-le souvent**, et toujours avant de fermer. |
| Rechercher | Tape un mot (nom de nœud ou bout de texte) + Entrée. Entrée à nouveau = résultat suivant. |

**Rangée « Disposition »** :

| Bouton | Effet |
|---|---|
| Auto | Range tout le graphe en colonnes, du début vers la fin |
| Appliquer l'ordre au .untold | Réordonne les blocs **dans le fichier** selon ta disposition (contenu intact) — pour garder un fichier lisible |
| Replier / Déplier tout | Masque ou révèle les branches (le ▾ de chaque nœud fait pareil localement) |

> Un nœud introuvable ? Il est sûrement replié : **Déplier tout**, ou passe par
> la recherche (elle déplie automatiquement).

---

## 7. Tester ton histoire

1. Appuie sur **F5** (ou le bouton ▶ en haut à droite de Godot).
2. Le jeu s'ouvre sur la bibliothèque : clique la couverture de l'histoire,
   puis **« Commencer l'histoire »** sur la fiche du personnage.
3. Joue jusqu'au passage qui t'intéresse. La touche **M** (ou le bouton 🗺)
   ouvre la carte de progression.
4. Quitte quand tu veux : le jeu **reprend automatiquement** au dernier point
   de choix. Pour repartir de zéro : fiche du personnage →
   **« Recommencer depuis le début »**.

Astuce : ce que le mode **Vérifier** te signale comme « nœud injoignable
depuis le début » est du contenu que le joueur ne pourra **jamais** voir —
c'est soit un oubli de lien, soit du contenu à recycler.

---

## 8. Ce qu'il y a derrière (juste pour comprendre)

Chaque histoire vit dans `data/stories/<son_dossier>/` :

- `act1_sc1.untold` — **la source de vérité** : tout ton récit, en texte. C'est
  ce fichier que l'outil lit et écrit. Tu n'as jamais besoin de l'ouvrir, mais
  tu peux : il reste propre et lisible.
- `act1_sc1.meta.json` — les à-côtés de l'outil (positions du graphe, titres,
  commentaires privés). **Ne l'édite pas à la main.**
- `manifest.json` — titre, auteur et pitch affichés dans la bibliothèque.
- `characters/`, `illustrations/`, `illustrations_defs.json`, `items_defs.json`
  — le personnage, les images et les objets.

---

## 9. Petits pépins courants

| Symptôme | Cause et remède |
|---|---|
| « Id invalide » à la création | Espaces ou accents dans le nom : `grande_salle` ✔, `Grande salle` ✘ |
| « cible inconnue » dans Vérifier | Un lien pointe vers un nœud renommé à la main ou supprimé → clique le nœud fautif et corrige la cible dans Sorties |
| Un choix n'apparaît pas en jeu | Il est sous condition `{ … }` non remplie — vérifie la ligne dans Contenu |
| L'histoire ne démarre pas | Il faut un nœud nommé exactement `start` — Vérifier te le dira |
| « id déclaré plusieurs fois » | Deux nœuds portent le même nom dans le fichier — renomme l'un des deux |
| J'ai tout cassé | **↶**, autant de fois que nécessaire. Et le projet est sous git : rien n'est jamais vraiment perdu. |

Bonne écriture ! Et si l'outil te gêne quelque part — un clic de trop, une
info qui manque — note-le : il est fait pour être adapté à ta façon de
travailler.
