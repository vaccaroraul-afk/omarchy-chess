.pragma library

// Pure helpers for raul.chess: square math, Stockfish levels, UCI parsing,
// saved-state normalization and the status line. Nothing here touches QML
// objects, so it loads the same in the shell and in a bare `qml` test.

var PLUGIN_ID = "raul.chess"
var STATE_VERSION = 1
var FILES = "abcdefgh"

// Font Awesome solid chess glyphs, drawn with the Font Awesome family. Nerd
// Fonts put Octicons on these code points, so the bar icon uses the
// Material Design knight (U+F0858, nf-md-chess_knight) instead.
var GLYPHS = { k: "\uf43f", q: "\uf445", r: "\uf447", b: "\uf43a", n: "\uf441", p: "\uf443" }
var BAR_GLYPH = "\udb82\udc58"
var VALUES = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 }
var CAPTURE_ORDER = ["q", "r", "b", "n", "p"]
var PROMOTIONS = ["q", "r", "b", "n"]

// Stockfish strength per level: Skill Level, a depth cap (0 = none) and the
// time per move. The low levels lean on the depth cap, since Skill Level 0
// searching at full depth still beats most beginners.
var LEVELS = [
  { skill: 0, depth: 1, movetime: 200 },
  { skill: 2, depth: 2, movetime: 300 },
  { skill: 4, depth: 4, movetime: 400 },
  { skill: 7, depth: 6, movetime: 500 },
  { skill: 10, depth: 0, movetime: 400 },
  { skill: 13, depth: 0, movetime: 600 },
  { skill: 16, depth: 0, movetime: 900 },
  { skill: 20, depth: 0, movetime: 1500 }
]
var DEFAULT_LEVEL = 3

// UI text. The panel follows the system language (Qt's uiLanguages, so
// LANGUAGE, LC_MESSAGES and LANG all count): Spanish for an es locale,
// English otherwise. %1 is replaced by the argument.
var STRINGS = {
  en: {
    white: "White",
    black: "Black",
    you: "You",
    stockfishLevel: "Stockfish · level %1",
    detailLocal: "Two players",
    detailEngine: "Against Stockfish · you play %1",
    yourMove: "Your move",
    check: " · check",
    thinking: "Stockfish is thinking…",
    engineMissing: "Stockfish not found",
    toMove: "%1 to move",
    mateWon: "Checkmate. You win!",
    mateLost: "Checkmate. Stockfish wins",
    mateSide: "Checkmate. %1 wins",
    draw: "Draw",
    drawStalemate: "Draw by stalemate",
    drawRepetition: "Draw by threefold repetition",
    drawMaterial: "Draw by insufficient material",
    drawFifty: "Draw by the fifty-move rule",
    close: "Close",
    installHint: "Stockfish not found. Install it with:\nyay -S stockfish",
    engineCrashed: "Stockfish quit unexpectedly. Undo or start a new game to try again.",
    undo: "Undo",
    flip: "Flip board",
    levelHeading: "STOCKFISH LEVEL",
    newGameHeading: "NEW GAME",
    modeEngine: "Against Stockfish",
    modeLocal: "2 players",
    random: "Random",
    appliesNext: "Applies when you start a new game.",
    newGame: "New game",
    keysHelp: "Arrows or hjkl: cursor · Enter: move · U undo · N new · F flip · Esc close"
  },
  es: {
    white: "Blancas",
    black: "Negras",
    you: "Tú",
    stockfishLevel: "Stockfish · nivel %1",
    detailLocal: "Dos jugadores",
    detailEngine: "Contra Stockfish · juegas con %1",
    yourMove: "Te toca",
    check: " · jaque",
    thinking: "Stockfish piensa…",
    engineMissing: "Falta Stockfish",
    toMove: "Juegan %1",
    mateWon: "Jaque mate. ¡Ganaste!",
    mateLost: "Jaque mate. Gana Stockfish",
    mateSide: "Jaque mate. Ganan %1",
    draw: "Tablas",
    drawStalemate: "Tablas por ahogado",
    drawRepetition: "Tablas por triple repetición",
    drawMaterial: "Tablas por material insuficiente",
    drawFifty: "Tablas por la regla de los 50 movimientos",
    close: "Cerrar",
    installHint: "No encontré Stockfish. Instálalo con:\nyay -S stockfish",
    engineCrashed: "Stockfish se cerró de golpe. Deshaz o empieza una partida nueva para reintentar.",
    undo: "Deshacer",
    flip: "Girar tablero",
    levelHeading: "NIVEL DE STOCKFISH",
    newGameHeading: "NUEVA PARTIDA",
    modeEngine: "Contra Stockfish",
    modeLocal: "2 jugadores",
    random: "Al azar",
    appliesNext: "Se aplica al empezar una partida nueva.",
    newGame: "Nueva partida",
    keysHelp: "Flechas o hjkl: cursor · Enter: mover · U deshacer · N nueva · F girar · Esc cerrar"
  }
}

var DRAW_KEYS = {
  stalemate: "drawStalemate",
  repetition: "drawRepetition",
  material: "drawMaterial",
  fifty: "drawFifty"
}

// The first supported language in the system's preference list (e.g.
// ["de-DE", "es-ES"] → "es"), else English.
function language(preferred) {
  var list = preferred || []
  for (var i = 0; i < list.length; i++) {
    var code = String(list[i]).toLowerCase().split(/[-_.@]/)[0]
    if (STRINGS.hasOwnProperty(code)) return code
  }
  return "en"
}

function text(lang, key, arg) {
  var table = STRINGS.hasOwnProperty(lang) ? STRINGS[lang] : STRINGS.en
  var value = table.hasOwnProperty(key) ? table[key]
    : STRINGS.en.hasOwnProperty(key) ? STRINGS.en[key] : key
  return arg === undefined ? value : value.replace("%1", arg)
}

function clampLevel(level) {
  var n = Math.round(Number(level))
  if (!isFinite(n)) return DEFAULT_LEVEL
  return Math.max(1, Math.min(LEVELS.length, n))
}

function levelSpec(level) {
  return LEVELS[clampLevel(level) - 1]
}

function goCommand(level) {
  var spec = levelSpec(level)
  var command = "go movetime " + spec.movetime
  if (spec.depth > 0) command += " depth " + spec.depth
  return command
}

function opposite(color) {
  return color === "b" ? "w" : "b"
}

function colorName(color, lang) {
  return text(lang, color === "b" ? "black" : "white")
}

// View index 0..63 runs left to right, top to bottom; flipped puts black's
// back rank at the bottom.
function viewSquare(index, flipped) {
  var row = Math.floor(index / 8)
  var col = index % 8
  var file = flipped ? 7 - col : col
  var rank = flipped ? row + 1 : 8 - row
  return FILES.charAt(file) + rank
}

function squareView(square, flipped) {
  var file = FILES.indexOf(String(square).charAt(0))
  var rank = Number(String(square).charAt(1))
  if (file < 0 || !(rank >= 1 && rank <= 8)) return -1
  var row = flipped ? rank - 1 : 8 - rank
  var col = flipped ? 7 - file : file
  return row * 8 + col
}

// Moves a view-space cursor, clamped to the board edges.
function stepSquare(square, dx, dy, flipped) {
  var index = squareView(square, flipped)
  if (index < 0) return viewSquare(52, flipped)
  var row = Math.max(0, Math.min(7, Math.floor(index / 8) + dy))
  var col = Math.max(0, Math.min(7, index % 8 + dx))
  return viewSquare(row * 8 + col, flipped)
}

function isLightSquare(square) {
  var file = FILES.indexOf(String(square).charAt(0))
  var rank = Number(String(square).charAt(1))
  return (file + rank) % 2 === 0
}

// chess.js board() rows run rank 8 → 1; flatten them into square → piece.
function pieceMap(board) {
  var map = {}
  for (var r = 0; r < board.length; r++) {
    for (var f = 0; f < board[r].length; f++) {
      var piece = board[r][f]
      if (piece) map[FILES.charAt(f) + (8 - r)] = { type: piece.type, color: piece.color }
    }
  }
  return map
}

function kingSquare(pieces, color) {
  for (var square in pieces) {
    var piece = pieces[square]
    if (piece.type === "k" && piece.color === color) return square
  }
  return ""
}

// What each side has taken (from the verbose move history, so a promoted
// pawn does not count as lost), strongest first, and white's material lead
// on the board.
function captured(pieces, history) {
  var taken = { w: [], b: [] }
  for (var i = 0; i < history.length; i++) {
    if (history[i].captured) taken[history[i].color].push(history[i].captured)
  }
  function strongestFirst(a, b) { return CAPTURE_ORDER.indexOf(a) - CAPTURE_ORDER.indexOf(b) }
  taken.w.sort(strongestFirst)
  taken.b.sort(strongestFirst)
  var material = { w: 0, b: 0 }
  for (var square in pieces) material[pieces[square].color] += VALUES[pieces[square].type]
  return { w: taken.w, b: taken.b, advantage: material.w - material.b }
}

function movePairs(sanList) {
  var pairs = []
  for (var i = 0; i < sanList.length; i += 2) {
    pairs.push({
      number: i / 2 + 1,
      white: sanList[i],
      black: i + 1 < sanList.length ? sanList[i + 1] : ""
    })
  }
  return pairs
}

// SAN with Spanish piece letters (R D T A C); files are lowercase and
// castling uses O, so every uppercase K/Q/R/B/N is a piece.
var SPANISH_LETTERS = { K: "R", Q: "D", R: "T", B: "A", N: "C" }

function spanishSan(san) {
  return String(san || "").replace(/[KQRBN]/g, function(letter) { return SPANISH_LETTERS[letter] })
}

// Spanish games are written with Spanish letters; English keeps plain SAN.
function displaySan(san, lang) {
  return lang === "es" ? spanishSan(san) : String(san || "")
}

function parseUci(text) {
  var match = /^([a-h][1-8])([a-h][1-8])([qrbn])?$/.exec(String(text || "").trim())
  if (!match) return null
  var move = { from: match[1], to: match[2] }
  if (match[3]) move.promotion = match[3]
  return move
}

function uciOf(move) {
  return move.from + move.to + (move.promotion || "")
}

function parseBestMove(line) {
  var match = /^bestmove\s+(\S+)/.exec(String(line || "").trim())
  return match ? parseUci(match[1]) : null
}

// Takes the chess.js game object; only calls its read-only predicates.
function outcome(game) {
  if (game.in_checkmate()) return { over: true, winner: opposite(game.turn()), reason: "checkmate" }
  if (game.in_stalemate()) return { over: true, winner: "", reason: "stalemate" }
  if (game.insufficient_material()) return { over: true, winner: "", reason: "material" }
  if (game.in_threefold_repetition()) return { over: true, winner: "", reason: "repetition" }
  if (game.in_draw()) return { over: true, winner: "", reason: "fifty" }
  return { over: false, winner: "", reason: "" }
}

// state: { outcome, turn, inCheck, mode, playerColor, engineMissing, lang }
function statusText(state) {
  var lang = state.lang
  var result = state.outcome || {}
  if (result.over) {
    if (result.reason === "checkmate") {
      if (state.mode === "engine")
        return text(lang, result.winner === state.playerColor ? "mateWon" : "mateLost")
      return text(lang, "mateSide", colorName(result.winner, lang))
    }
    return text(lang, DRAW_KEYS[result.reason] || "draw")
  }
  var check = state.inCheck ? text(lang, "check") : ""
  if (state.mode === "engine") {
    if (state.turn === state.playerColor) return text(lang, "yourMove") + check
    if (state.engineMissing) return text(lang, "engineMissing")
    return text(lang, "thinking") + check
  }
  return text(lang, "toMove", colorName(state.turn, lang)) + check
}

function normalizeChoice(value, options, fallback) {
  return options.indexOf(value) !== -1 ? value : fallback
}

function normalizeState(raw) {
  var state = raw && typeof raw === "object" ? raw : {}
  var moves = Array.isArray(state.moves) ? state.moves : []
  return {
    mode: normalizeChoice(state.mode, ["engine", "local"], "engine"),
    playerColor: normalizeChoice(state.playerColor, ["w", "b"], "w"),
    nextMode: normalizeChoice(state.nextMode, ["engine", "local"], "engine"),
    nextColor: normalizeChoice(state.nextColor, ["w", "b", "random"], "w"),
    colorChoice: normalizeChoice(state.colorChoice, ["w", "b", "random"], state.playerColor === "b" ? "b" : "w"),
    level: clampLevel(state.level),
    flipped: state.flipped === true,
    moves: moves.filter(function(move) { return parseUci(move) !== null })
  }
}

function parseState(text) {
  try {
    return normalizeState(JSON.parse(String(text || "")))
  } catch (e) {
    return normalizeState(null)
  }
}

function promotionKey(text) {
  var key = String(text || "").toLowerCase()
  var aliases = { q: "q", d: "q", "1": "q", r: "r", t: "r", "2": "r", b: "b", a: "b", "3": "b", n: "n", c: "n", "4": "n" }
  return aliases[key] || ""
}
