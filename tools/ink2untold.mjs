#!/usr/bin/env node
// ============================================================
//  Convertisseur Ink → .untold
//
//  Couvre le sous-ensemble d'Ink réellement utilisé par les fichiers
//  narratifs d'Untold (voir FORMAT.md pour la cible) :
//    - knots (=== id ===), diverts (-> id, DONE), choix (*[...] -> id)
//    - switchs {character: / {type:  avec branches - "Valeur": et - else:
//    - conditions de visite {Knot:, {not Knot:, {(A or B):, {(A and B):
//    - conditionnels inline {var=="v":texte} (dupliqués en 2 lignes gardées)
//    - glue <>, gathers "- texte", tags #Tag
//    - ~addIllustration(...) → @illustration(...), ~displayNode() → supprimé
//    - -> minigame("Nom","Succès","Échec") → nœud relais @minigame(...)
//      qui enchaîne sur la branche succès (mécanique à venir côté moteur)
//
//  Usage : node tools/ink2untold.mjs <entrée.ink> <sortie.untold>
// ============================================================

import fs from "node:fs";

const [, , inPath, outPath] = process.argv;
if (!inPath || !outPath) {
  console.error("Usage: node tools/ink2untold.mjs <entrée.ink> <sortie.untold>");
  process.exit(1);
}

// Noms d'illustrations Ink → noms de la bibliothèque Godot.
const ILLUSTRATION_MAP = {
  "Statut de Sîn": "Statue de Sîn", // coquille du fichier d'origine
};

// Knots utilitaires de l'ancien moteur, sans équivalent runtime : ignorés.
const DROPPED_KNOTS = new Set(["minigame", "null"]);

// Correctifs de contenu : conditions ajoutées à une ligne d'un nœud donné.
// (Trous de la source : ex. le choix N060 → N073 est ouvert à tous mais
// N073 n'est écrit que pour la Nadîtum ; le pendant Marchand est N074.)
const PATCHES = [
  { node: "A01S01N060", match: "-> A01S01N073", addCond: 'character == "Nadîtum"' },
];

const warnings = [];
const warn = (msg) => {
  if (!warnings.includes(msg)) warnings.push(msg);
};

// ---------------------------------------------------------- lecture
let src = fs.readFileSync(inPath, "utf8");
src = src.replace(/^﻿/, "");
// Échappements unicode littéraux de l'export Unity (ex: \\u00A0).
src = src.replace(/\\{1,2}u([0-9a-fA-F]{4})/g, (_, h) =>
  String.fromCharCode(parseInt(h, 16)),
);
const srcLines = src.split(/\r?\n/);

// ---------------------------------------------------------- état
const vars = []; // ["character", ...]
const nodes = []; // {id, lines: []}
const nodeIds = new Set();
let current = null; // nœud en cours
let skipKnot = false; // knot ignoré (minigame, null)
let pendingChoice = null; // choix en attente de son divert
const minigames = new Map(); // id relais -> {name, success, failure}

// Pile de blocs conditionnels ouverts. Chaque frame fournit `alts()` :
// une liste d'alternatives (OR), chacune étant une liste de conditions (AND).
const frames = [];

function newNode(id) {
  current = { id, lines: [] };
  nodes.push(current);
  nodeIds.add(id);
}

function currentGuardAlts() {
  // Produit cartésien des alternatives de chaque frame → DNF globale.
  let acc = [[]];
  for (const f of frames) {
    const alts = f.alts();
    if (alts === null) continue; // frame sans branche active (ex: switch avant 1er cas)
    acc = andDnf(acc, alts);
  }
  return acc;
}

function guardPrefix(extraDnf = [[]]) {
  const groups = andDnf(currentGuardAlts(), extraDnf).filter((g) => g.length > 0);
  if (groups.length === 0) return "";
  return `{ ${groups.map((g) => g.map(condToStr).join(" and ")).join(" or ")} } `;
}

function emit(line) {
  if (!current) {
    if (line.trim()) warn(`ligne hors de tout nœud ignorée : ${line}`);
    return;
  }
  current.lines.push(line);
}

function emitGuarded(content, extraDnf = [[]]) {
  emit(guardPrefix(extraDnf) + content);
}

// ---------------------------------------------------------- conditions
// Les conditions sont manipulées en forme normale disjonctive (DNF) :
// une liste d'alternatives (OR), chacune une liste de conditions (AND).
// Une condition : {kind:"visited", id, neg} ou {kind:"var", name, op, value}.

function andDnf(a, b) {
  const out = [];
  for (const x of a) for (const y of b) out.push([...x, ...y]);
  return out;
}

function negateCond(c) {
  if (c.kind === "visited") return { ...c, neg: !c.neg };
  return { ...c, op: c.op === "==" ? "!=" : "==" };
}

// ¬(alt1 ∨ alt2 ∨ …) = ¬alt1 ∧ ¬alt2 ∧ … ; ¬(c1 ∧ c2) = ¬c1 ∨ ¬c2.
function negateDnf(dnf) {
  let acc = [[]];
  for (const alt of dnf) acc = andDnf(acc, alt.map((c) => [negateCond(c)]));
  return acc;
}

function condToStr(c) {
  if (c.kind === "visited") return `${c.neg ? "!" : ""}visited(${c.id})`;
  return `${c.name} ${c.op} "${c.value}"`;
}

// Parse une expression booléenne Ink en DNF. Grammaire :
//   expr   := term ("or" term)*
//   term   := factor ("and" factor)*
//   factor := "not" factor | "(" expr ")" | knot_id | var ==|!= "valeur"
// Retourne null si illisible.
function parseCondExpr(src) {
  const tokens = [];
  let i = 0;
  const s = src.trim();
  while (i < s.length) {
    if (/\s/.test(s[i])) { i++; continue; }
    if (s[i] === "(" || s[i] === ")") { tokens.push({ t: s[i] }); i++; continue; }
    const rest = s.slice(i);
    let m;
    if ((m = rest.match(/^(or|and|not)\b/))) { tokens.push({ t: m[1] }); i += m[1].length; continue; }
    if ((m = rest.match(/^(\w+)\s*(==|!=)\s*"([^"]*)"/))) {
      tokens.push({ t: "cmp", name: m[1], op: m[2], value: m[3] });
      i += m[0].length;
      continue;
    }
    if ((m = rest.match(/^\w+/))) { tokens.push({ t: "id", name: m[0] }); i += m[0].length; continue; }
    return null;
  }

  let p = 0;
  const peek = () => tokens[p];
  function expr() {
    let alts = term();
    if (!alts) return null;
    while (peek()?.t === "or") {
      p++;
      const r = term();
      if (!r) return null;
      alts = alts.concat(r);
    }
    return alts;
  }
  function term() {
    let alts = factor();
    if (!alts) return null;
    while (peek()?.t === "and") {
      p++;
      const r = factor();
      if (!r) return null;
      alts = andDnf(alts, r);
    }
    return alts;
  }
  function factor() {
    const tk = peek();
    if (!tk) return null;
    if (tk.t === "not") { p++; const f = factor(); return f && negateDnf(f); }
    if (tk.t === "(") {
      p++;
      const e = expr();
      if (!e || peek()?.t !== ")") return null;
      p++;
      return e;
    }
    if (tk.t === "id") { p++; return [[{ kind: "visited", id: tk.name, neg: false }]]; }
    if (tk.t === "cmp") { p++; return [[{ kind: "var", name: tk.name, op: tk.op, value: tk.value }]]; }
    return null;
  }
  const res = expr();
  return res && p === tokens.length ? res : null;
}

function makeCondFrame(header) {
  const dnf = parseCondExpr(header);
  if (!dnf) return null;
  return {
    kind: "cond",
    negated: false,
    alts() {
      return this.negated ? negateDnf(dnf) : dnf;
    },
  };
}

// Corrige les switchs dont les valeurs ne correspondent pas à la variable
// testée (coquilles de la source : "{type:" avec des noms de personnages).
const TYPE_VALUES = new Set(["Social", "Physique", "Mystique"]);
const CHARACTER_VALUES = new Set([
  "Nadîtum", "Marchand", "Soldat", "Danseuse", "Exorciste", "Prêtresse",
]);

function switchVarFor(varName, value) {
  const actual = TYPE_VALUES.has(value)
    ? "type"
    : CHARACTER_VALUES.has(value)
      ? "character"
      : varName;
  if (actual !== varName)
    warn(`switch sur « ${varName} » avec la valeur « ${value} » : corrigé en « ${actual} »`);
  return actual;
}

function makeSwitchFrame(varName) {
  return {
    kind: "switch",
    varName,
    seen: [],
    active: null, // {value} | {else:true} | null
    alts() {
      if (this.active === null) return null;
      if (this.active.else)
        return [this.seen.map((v) => ({ kind: "var", name: switchVarFor(this.varName, v), op: "!=", value: v }))];
      const v = this.active.value;
      return [[{ kind: "var", name: switchVarFor(this.varName, v), op: "==", value: v }]];
    },
  };
}

// ---------------------------------------------------------- diverts & choix
function resolveTarget(raw) {
  let t = raw.trim();
  if (t === "DONE") return "END";
  const m = t.match(/^minigame\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)$/);
  if (m) {
    const id = `mg_${m[1]}_${m[2]}${m[2] === m[3] ? "" : "_" + m[3]}`;
    minigames.set(id, { name: m[1], success: m[2], failure: m[3] });
    return id;
  }
  if (/[(){}]/.test(t)) warn(`cible de saut suspecte : ${raw}`);
  return t;
}

function flushPendingChoice(target) {
  const c = pendingChoice;
  pendingChoice = null;
  emit(`${c.guard}* [${c.text}] -> ${resolveTarget(target)}`);
}

// ---------------------------------------------------------- texte
// Expanse les conditionnels inline {var=="v":texte} en 2 lignes gardées.
function emitText(content) {
  const m = content.match(/^(.*?)\{(\w+)\s*==\s*"([^"]*)"\s*:([^{}]*)\}(.*)$/);
  if (m) {
    const [, before, v, val, ins, after] = m;
    emitGuarded(before + ins + after, [[{ kind: "var", name: v, op: "==", value: val }]]);
    emitGuarded(before + after, [[{ kind: "var", name: v, op: "!=", value: val }]]);
    return;
  }
  emitGuarded(content);
}

// Traite le contenu d'une ligne (après ouverture/fermeture de blocs).
function processContent(line) {
  let s = line.trim();
  if (!s) return;

  // Fermeture de bloc en début de ligne : "}" puis éventuel reste.
  if (s.startsWith("}")) {
    if (frames.length === 0) warn(`'}' sans bloc ouvert : ${line}`);
    else frames.pop();
    processContent(s.slice(1));
    return;
  }

  // Commentaires : conservés tels quels (ignorés par le parseur).
  if (s.startsWith("//")) {
    emit(s);
    return;
  }

  // Un divert seul juste après un choix sans cible = corps du choix.
  if (pendingChoice) {
    const md = s.match(/^->\s*(.+)$/);
    if (md) {
      flushPendingChoice(md[1]);
      return;
    }
    warn(`choix sans cible non suivi d'un divert : ${pendingChoice.text}`);
    pendingChoice = null;
  }

  // Ouverture de bloc conditionnel "{header:" (multi-ligne) ou forme
  // inline "{header:contenu}" (mono-ligne).
  let m = s.match(/^\{\s*([^:{}]+?)\s*:(.*)$/);
  if (m) {
    const header = m[1];
    const rest = m[2];
    const isSwitch = vars.includes(header);
    const closesInline = rest.trimEnd().endsWith("}") && !rest.includes("{");

    if (closesInline && !isSwitch) {
      // "{Knot:texte}" ou "{(A or B):texte}" sur une seule ligne.
      const frame = makeCondFrame(header);
      if (!frame) {
        warn(`condition inline illisible : ${s}`);
        return;
      }
      frames.push(frame);
      processContent(rest.trimEnd().slice(0, -1));
      frames.pop();
      return;
    }

    const frame = isSwitch ? makeSwitchFrame(header) : makeCondFrame(header);
    if (!frame) {
      warn(`en-tête de bloc illisible : ${s}`);
      return;
    }
    frames.push(frame);
    if (rest.trim()) processContent(rest);
    return;
  }

  // Branches d'un switch / else.
  const top = frames[frames.length - 1];
  if ((m = s.match(/^-\s*else\s*:(.*)$/))) {
    if (!top) warn(`'- else:' hors de tout bloc : ${s}`);
    else if (top.kind === "switch") top.active = { else: true };
    else top.negated = true;
    if (m[1].trim()) processContent(m[1]);
    return;
  }
  // Le deux-points est optionnel : la source contient des branches sans lui.
  if (top && top.kind === "switch" && (m = s.match(/^-\s*"([^"]+)"\s*:?(.*)$/))) {
    top.active = { value: m[1] };
    top.seen.push(m[1]);
    if (m[2].trim()) processContent(m[2]);
    return;
  }

  // Gather : "- texte" (simple regroupement, le tiret saute).
  if ((m = s.match(/^-\s+(.*)$/)) && !s.startsWith("->")) {
    s = m[1].trim();
    if (!s) return;
  }

  // Lignes vides déguisées ("" issues de l'export).
  if (s === '""') return;

  // Commandes moteur "~ ...".
  if (s.startsWith("~")) {
    const c = s.slice(1).trim();
    if (/^displayNode\s*\(\s*\)$/.test(c)) return;
    if ((m = c.match(/^addIllustration\s*\(\s*"([^"]+)"\s*\)$/))) {
      const name = ILLUSTRATION_MAP[m[1]] ?? m[1];
      emitGuarded(`@illustration("${name}")`);
      return;
    }
    warn(`commande ~ inconnue ignorée : ${s}`);
    return;
  }

  // Choix sans crochets : "*texte -> cible" (le texte fait office d'intitulé).
  if (/^\*/.test(s) && !/^\*\s*(\{[^{}]*\})?\s*\[/.test(s)) {
    if ((m = s.match(/^\*\s*(.+?)\s*->\s*(.+?)\s*$/))) {
      emitGuarded(`* [${m[1]}] -> ${resolveTarget(m[2])}`);
      return;
    }
    warn(`choix sans crochets ni cible : ${s}`);
    return;
  }

  // Choix : *{cond} [texte] -> cible   (cond, cible et #tag optionnels)
  if ((m = s.match(/^\*\s*(?:\{\s*([^{}]+?)\s*\})?\s*\[(.*?)\]\s*(?:->\s*(.+?))?\s*(#\S+)?$/))) {
    const [, cond, text, target, tag] = m;
    if (tag) warn(`tag de choix ignoré (${tag}) : ${text}`);
    let extra = [[]];
    if (cond) {
      const dnf = parseCondExpr(cond);
      if (dnf) extra = dnf;
      else warn(`condition de choix illisible : ${s}`);
    }
    if (target) {
      emitGuarded(`* [${text.trim()}] -> ${resolveTarget(target)}`, extra);
    } else {
      pendingChoice = { text: text.trim(), guard: guardPrefix(extra) };
    }
    return;
  }

  // Divert : "-> cible".
  if ((m = s.match(/^->\s*(.+)$/))) {
    emitGuarded(`-> ${resolveTarget(m[1])}`);
    return;
  }

  // Tags de nœud : passés tels quels.
  if (s.startsWith("#")) {
    emit(s);
    return;
  }

  // Sinon : texte narratif.
  emitText(s);
}

// ---------------------------------------------------------- boucle principale
for (const raw of srcLines) {
  const s = raw.trim();

  // Déclarations d'en-tête.
  if (/^EXTERNAL\s/.test(s)) continue;
  let m = s.match(/^VAR\s+(\w+)\s*=\s*(.*)$/);
  if (m) {
    vars.push(m[1]);
    continue;
  }

  // Knot : "=== id ===" ou "=== id(params) ===".
  if ((m = s.match(/^===\s*(\w+)\s*(\([^)]*\))?\s*=*\s*$/))) {
    if (frames.length > 0) {
      warn(`bloc non fermé à la fin du nœud ${current?.id} (${frames.length} restant)`);
      frames.length = 0;
    }
    if (pendingChoice) {
      warn(`choix sans cible en fin de nœud ${current?.id} : ${pendingChoice.text}`);
      pendingChoice = null;
    }
    if (DROPPED_KNOTS.has(m[1]) || m[2]) {
      skipKnot = true;
      current = null;
      continue;
    }
    skipKnot = false;
    newNode(m[1]);
    continue;
  }
  if (skipKnot) continue;

  // Contenu avant le premier knot : nœud d'entrée implicite "start".
  if (!current && s && !s.startsWith("//")) newNode("start");

  if (s.startsWith("//")) {
    if (current) emit(s);
    continue;
  }
  if (!s) continue;

  processContent(s);
}

// ---------------------------------------------------------- relais mini-jeux
if (minigames.size > 0) {
  for (const [id, mg] of minigames) {
    newNode(id);
    emit(`// Mini-jeu « ${mg.name} » — mécanique à venir : on suit la branche succès.`);
    emit(`@minigame("${mg.name}", "${mg.success}", "${mg.failure}")`);
    emit(`-> ${mg.success}`);
  }
}

// ---------------------------------------------------------- correctifs
for (const patch of PATCHES) {
  const node = nodes.find((n) => n.id === patch.node);
  if (!node) {
    warn(`patch sans effet : nœud ${patch.node} introuvable`);
    continue;
  }
  let applied = false;
  node.lines = node.lines.map((l) => {
    if (!l.includes(patch.match)) return l;
    applied = true;
    const m = l.match(/^\{\s*(.*?)\s*\}\s*(.*)$/);
    if (m) {
      // Condition ajoutée à chaque groupe "or" de la garde existante.
      const groups = m[1].split(" or ").map((g) => `${g} and ${patch.addCond}`);
      return `{ ${groups.join(" or ")} } ${m[2]}`;
    }
    return `{ ${patch.addCond} } ${l}`;
  });
  if (!applied) warn(`patch sans effet : « ${patch.match} » absent de ${patch.node}`);
}

// ---------------------------------------------------------- validation
const targetRe = /->\s*(\S+)\s*$/;
let missing = 0;
for (const n of nodes) {
  for (const l of n.lines) {
    const m = l.match(targetRe);
    if (m && m[1] !== "END" && !nodeIds.has(m[1])) {
      warn(`cible inconnue « ${m[1]} » dans ${n.id}`);
      missing++;
    }
  }
}

// ---------------------------------------------------------- écriture
const out = [];
out.push("// ============================================================");
out.push(`//  Généré depuis ${inPath.split(/[\\/]/).pop()} par tools/ink2untold.mjs`);
out.push("//  (regénérable — préférer corriger la source ou le convertisseur)");
out.push("// ============================================================");
out.push("");
for (const v of vars) out.push(`@var ${v} = ""`);
out.push("");
for (const n of nodes) {
  out.push(`:: ${n.id}`);
  out.push(...n.lines);
  out.push("");
}
fs.writeFileSync(outPath, out.join("\n"), "utf8");

console.log(`${nodes.length} nœuds écrits dans ${outPath} (${minigames.size} relais mini-jeu)`);
if (warnings.length) {
  console.log(`\n${warnings.length} avertissement(s) :`);
  for (const w of warnings) console.log("  - " + w);
}
process.exit(missing > 0 ? 2 : 0);
