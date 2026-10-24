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

var DRAW_REASONS = {
  stalemate: "por ahogado",
  repetition: "por triple repetición",
  material: "por material insuficiente",
  fifty: "por la regla de los 50 movimientos"
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

function colorName(color) {
  return color === "b" ? "Negras" : "Blancas"
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

// state: { outcome, turn, inCheck, mode, playerColor, engineMissing }
function statusText(state) {
  var result = state.outcome || {}
  if (result.over) {
    if (result.reason === "checkmate") {
      if (state.mode === "engine")
        return result.winner === state.playerColor ? "Jaque mate. ¡Ganaste!" : "Jaque mate. Gana Stockfish"
      return "Jaque mate. Ganan " + colorName(result.winner)
    }
    return "Tablas " + (DRAW_REASONS[result.reason] || "")
  }
  var check = state.inCheck ? " · jaque" : ""
  if (state.mode === "engine") {
    if (state.turn === state.playerColor) return "Te toca" + check
    if (state.engineMissing) return "Falta Stockfish"
    return "Stockfish piensa…" + check
  }
  return "Juegan " + colorName(state.turn) + check
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
