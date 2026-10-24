import QtQuick
import "../Model.js" as Model
import "../chess.mjs" as ChessLib

// Headless checks for Model.js and the vendored chess.js. Run with:
//   QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qml tests/ModelTest.qml
// Prints one line per failure and exits 1 if any check failed.
QtObject {
  id: root

  property int failures: 0
  property int checks: 0

  function expect(name, actual, expected) {
    checks++
    var a = JSON.stringify(actual)
    var e = JSON.stringify(expected)
    if (a === e) return
    failures++
    console.log("FAIL " + name + ": got " + a + ", want " + e)
  }

  function play(game, sans) {
    for (var i = 0; i < sans.length; i++) game.move(sans[i])
    return game
  }

  Component.onCompleted: {
    // Rules: perft node counts from the standard test positions.
    expect("perft start 3", new ChessLib.Chess().perft(3), 8902)
    expect("perft kiwipete 2", new ChessLib.Chess("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1").perft(2), 2039)
    expect("perft position 3", new ChessLib.Chess("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1").perft(3), 2812)

    // Squares.
    expect("view 0", Model.viewSquare(0, false), "a8")
    expect("view 63", Model.viewSquare(63, false), "h1")
    expect("view 0 flipped", Model.viewSquare(0, true), "h1")
    expect("round trip", Model.squareView(Model.viewSquare(37, true), true), 37)
    expect("a1 dark", Model.isLightSquare("a1"), false)
    expect("h1 light", Model.isLightSquare("h1"), true)
    expect("step clamps", Model.stepSquare("a8", -1, -1, false), "a8")
    expect("step down", Model.stepSquare("e4", 0, 1, false), "e3")
    expect("step down flipped", Model.stepSquare("e4", 0, 1, true), "e5")

    // UCI.
    expect("bestmove", Model.parseBestMove("bestmove e7e8q ponder a1a2"), { from: "e7", to: "e8", promotion: "q" })
    expect("bestmove none", Model.parseBestMove("bestmove (none)"), null)
    expect("uci", Model.uciOf({ from: "g1", to: "f3" }), "g1f3")
    expect("go low", Model.goCommand(1), "go movetime 200 depth 1")
    expect("go high", Model.goCommand(99), "go movetime 1500")

    // Captures come from history, so a promotion is not a lost pawn.
    var promo = play(new ChessLib.Chess(), ["a4", "b5", "axb5", "a6", "bxa6", "Bb7", "axb7", "Nc6", "bxa8=N"])
    var taken = Model.captured(Model.pieceMap(promo.board()), promo.history({ verbose: true }))
    expect("white took", taken.w, ["r", "b", "p", "p"])
    expect("black took", taken.b, [])
    expect("advantage", taken.advantage, 12)

    // Outcome and status.
    var mate = play(new ChessLib.Chess(), ["f3", "e5", "g4", "Qh4#"])
    var result = Model.outcome(mate)
    expect("mate", result, { over: true, winner: "b", reason: "checkmate" })
    expect("mate local", Model.statusText({ outcome: result, mode: "local", lang: "es" }), "Jaque mate. Ganan Negras")
    expect("mate lost", Model.statusText({ outcome: result, mode: "engine", playerColor: "w", lang: "es" }), "Jaque mate. Gana Stockfish")
    expect("mate local en", Model.statusText({ outcome: result, mode: "local", lang: "en" }), "Checkmate. Black wins")
    expect("stalemate", Model.outcome(new ChessLib.Chess("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")).reason, "stalemate")
    expect("bare kings", Model.outcome(new ChessLib.Chess("8/8/4k3/8/8/4K3/8/8 w - - 0 1")).reason, "material")
    expect("draw", Model.statusText({ outcome: { over: true, reason: "stalemate" }, lang: "es" }), "Tablas por ahogado")
    expect("draw en", Model.statusText({ outcome: { over: true, reason: "fifty" }, lang: "en" }), "Draw by the fifty-move rule")
    expect("your turn", Model.statusText({ outcome: { over: false }, mode: "engine", turn: "w", playerColor: "w", inCheck: true, lang: "es" }), "Te toca · jaque")
    expect("your turn en", Model.statusText({ outcome: { over: false }, mode: "engine", turn: "w", playerColor: "w", inCheck: true, lang: "en" }), "Your move · check")
    expect("missing", Model.statusText({ outcome: { over: false }, mode: "engine", turn: "b", playerColor: "w", engineMissing: true, lang: "es" }), "Falta Stockfish")
    expect("local turn en", Model.statusText({ outcome: { over: false }, mode: "local", turn: "w" }), "White to move")

    // Saved state.
    var state = Model.parseState('{"mode":"local","level":42,"nextColor":"x","moves":["e2e4","junk","e7e5"]}')
    expect("state mode", state.mode, "local")
    expect("state level", state.level, 8)
    expect("state color", state.nextColor, "w")
    expect("state moves", state.moves, ["e2e4", "e7e5"])
    expect("state garbage", Model.parseState("not json").level, Model.DEFAULT_LEVEL)

    // Text.
    expect("spanish san", Model.spanishSan("Nxe5+"), "Cxe5+")
    expect("spanish promo", Model.spanishSan("exd8=Q#"), "exd8=D#")
    expect("castle", Model.spanishSan("O-O-O"), "O-O-O")
    expect("display san es", Model.displaySan("Qxf7#", "es"), "Dxf7#")
    expect("display san en", Model.displaySan("Qxf7#", "en"), "Qxf7#")

    // Language: the first supported entry of Qt's uiLanguages, else English.
    expect("lang es", Model.language(["es-Latn-AR", "es-AR", "es-Latn", "es"]), "es")
    expect("lang en", Model.language(["en-Latn-US", "en-US", "en-Latn", "en"]), "en")
    expect("lang fallback list", Model.language(["de-DE", "de", "es-ES", "es"]), "es")
    expect("lang unsupported", Model.language(["fr-FR", "fr"]), "en")
    expect("lang C", Model.language(["C"]), "en")
    expect("lang empty", Model.language([]), "en")
    expect("text arg", Model.text("es", "stockfishLevel", 3), "Stockfish · nivel 3")
    expect("text unknown lang", Model.text("fr", "undo"), "Undo")
    var missing = []
    for (var lang in Model.STRINGS) {
      for (var other in Model.STRINGS) {
        for (var key in Model.STRINGS[other]) {
          if (!Model.STRINGS[lang].hasOwnProperty(key)) missing.push(lang + "." + key)
        }
      }
    }
    expect("strings complete", missing, [])
    expect("promo key", Model.promotionKey("C"), "n")
    expect("pairs", Model.movePairs(["e4", "e5", "Nf3"]), [{ number: 1, white: "e4", black: "e5" }, { number: 2, white: "Nf3", black: "" }])

    console.log(failures === 0 ? "ok: " + checks + " checks" : failures + " of " + checks + " checks failed")
    Qt.exit(failures === 0 ? 0 : 1)
  }
}
