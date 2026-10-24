import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "chess.mjs" as ChessLib

// Chess against Stockfish, or two players at one keyboard, in a centered
// overlay. The plugin is keepLoaded so closing the board keeps the game, and
// every change is also written to ~/.local/state/omarchy/chess.json, which
// brings the game back after a shell restart.
//
// Mouse: click a piece then a square, or drag it. Keys: arrows / hjkl move
// the cursor · Enter / Space pick up and drop · u undo · n new game ·
// f flip · Esc drops the selection, then closes. On promotion: q r b n
// (or d t a c, or 1–4).
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  property bool opened: false

  // chess.js mutates in place, so sync() copies what the view needs into
  // plain properties after every change.
  property var game: new ChessLib.Chess()
  property bool restored: false

  // The game being played.
  property string mode: "engine"
  property string playerColor: "w"
  property string colorChoice: "w"
  property int level: Model.DEFAULT_LEVEL
  property bool flipped: false
  // Picks for the next game. While no move is made they apply at once.
  property string nextMode: "engine"
  property string nextColor: "w"

  // Position snapshot.
  property var pieces: ({})
  property var sanList: []
  property var uciList: []
  property string turn: "w"
  property bool inCheck: false
  property string checkSquare: ""
  property string lastFrom: ""
  property string lastTo: ""
  property var result: ({ over: false, winner: "", reason: "" })
  property var taken: ({ w: [], b: [], advantage: 0 })

  // Interaction.
  property string selected: ""
  property var targets: ({})
  property string cursor: ""
  property var promotion: null
  property bool pressedSelected: false
  property bool movedOnPress: false
  property var queuedEngineMove: null
  property real requestedAt: 0

  readonly property bool engineGame: mode === "engine"
  readonly property bool engineTurn: engineGame && !result.over && turn !== playerColor
  readonly property bool humanTurn: !result.over && !engineTurn
  readonly property int playerMoves: playerColor === "w" ? Math.ceil(sanList.length / 2) : Math.floor(sanList.length / 2)
  readonly property bool canUndo: engineGame ? playerMoves > 0 : sanList.length > 0
  readonly property bool settingsPending: sanList.length > 0
    && (nextMode !== mode || (nextMode === "engine" && nextColor !== colorChoice))
  readonly property string topColor: flipped ? "w" : "b"
  readonly property string bottomColor: flipped ? "b" : "w"
  // "es" or "en", from the system's language preferences.
  readonly property string lang: Model.language(Qt.locale().uiLanguages)
  readonly property string statusLine: Model.statusText({
    outcome: result, turn: turn, inCheck: inCheck, mode: mode,
    playerColor: playerColor, engineMissing: engine.missing, lang: lang
  })
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/chess.json"

  readonly property color fg: Color.popups.text
  readonly property color dim: Util.alpha(fg, 0.6)
  readonly property string fontFamily: Style.font.family
  readonly property string pieceFont: "Font Awesome 7 Free"
  readonly property int squareSize: Style.space(58)
  // Theme-tinted, but kept light enough that both piece colors read.
  readonly property color lightSquare: Qt.tint("#ededed", Util.alpha(Color.accent, 0.14))
  readonly property color darkSquare: Qt.tint("#707479", Util.alpha(Color.accent, 0.5))

  // ------------------------------------------------------------ lifecycle

  function open(payloadJson) {
    // Retry a missing engine on every open: it may have been installed.
    engine.missing = false
    opened = true
    // The window is created hidden, so focus taken before it maps lands
    // nowhere; take it again once it is up.
    Qt.callLater(function() {
      if (!root.opened) return
      keyCatcher.forceActiveFocus()
      root.scheduleEngine()
    })
  }

  function close() {
    opened = false
    promotion = null
    clearSelection()
    engineMoveTimer.stop()
    queuedEngineMove = null
  }

  function dismiss() {
    if (shell && typeof shell.hide === "function") shell.hide(Model.PLUGIN_ID)
    else close()
  }

  // ---------------------------------------------------------- game state

  function sync() {
    pieces = Model.pieceMap(game.board())
    var history = game.history({ verbose: true })
    sanList = history.map(function(move) { return move.san })
    uciList = history.map(Model.uciOf)
    var last = history.length > 0 ? history[history.length - 1] : null
    lastFrom = last ? last.from : ""
    lastTo = last ? last.to : ""
    turn = game.turn()
    inCheck = game.in_check()
    checkSquare = inCheck ? Model.kingSquare(pieces, turn) : ""
    result = Model.outcome(game)
    taken = Model.captured(pieces, history)
  }

  function save() {
    if (!restored) return
    stateFile.setText(JSON.stringify({
      version: Model.STATE_VERSION,
      mode: mode,
      playerColor: playerColor,
      colorChoice: colorChoice,
      nextMode: nextMode,
      nextColor: nextColor,
      level: level,
      flipped: flipped,
      moves: uciList
    }, null, 2) + "\n")
  }

  function restore(text) {
    if (restored) return
    var state = Model.parseState(text)
    mode = state.mode
    playerColor = state.playerColor
    colorChoice = state.colorChoice
    nextMode = state.nextMode
    nextColor = state.nextColor
    level = state.level
    flipped = state.flipped
    game.reset()
    // Replay until the first move that no longer applies; a hand-edited
    // or truncated file still restores everything before it.
    for (var i = 0; i < state.moves.length; i++) {
      if (!game.move(Model.parseUci(state.moves[i]))) break
    }
    restored = true
    sync()
    if (opened) scheduleEngine()
  }

  function newGame() {
    stopEngineWork()
    mode = nextMode
    colorChoice = nextColor
    playerColor = mode !== "engine" ? "w"
      : nextColor === "random" ? (Math.random() < 0.5 ? "w" : "b")
      : nextColor
    flipped = mode === "engine" && playerColor === "b"
    if (cursor !== "") cursor = Model.viewSquare(52, flipped)
    game.reset()
    clearSelection()
    sync()
    save()
    scheduleEngine()
  }

  function undo() {
    if (!canUndo) return
    stopEngineWork()
    if (engineGame) {
      // Back to the player's previous turn: drop the engine's reply, if it
      // came, and the player's move before it.
      var move
      do { move = game.undo() } while (move && move.color !== playerColor)
    } else {
      game.undo()
    }
    clearSelection()
    sync()
    save()
    scheduleEngine()
  }

  function flip() {
    flipped = !flipped
    save()
  }

  function setNextMode(value) {
    nextMode = value
    if (sanList.length === 0) newGame()
    else save()
  }

  function setNextColor(value) {
    nextColor = value
    if (sanList.length === 0) newGame()
    else save()
  }

  function setLevel(value) {
    level = Model.clampLevel(value)
    save()
  }

  // --------------------------------------------------------------- moves

  function legalTargets(square) {
    var map = {}
    var moves = game.moves({ square: square, verbose: true })
    for (var i = 0; i < moves.length; i++) map[moves[i].to] = moves[i].captured ? "capture" : "move"
    return map
  }

  function ownPiece(square) {
    var piece = pieces[square]
    return !!piece && piece.color === turn
  }

  function select(square) {
    selected = square
    targets = legalTargets(square)
  }

  function clearSelection() {
    selected = ""
    targets = ({})
  }

  // Press + release make click-to-move: a press on a target moves, a press
  // on an own piece selects it, and releasing on the piece that was already
  // selected (without dragging) drops the selection again.
  function pressSquare(square) {
    movedOnPress = false
    pressedSelected = square !== "" && square === selected
    if (!humanTurn || promotion) return
    if (selected !== "" && targets[square]) {
      movedOnPress = true
      tryMove(selected, square)
    } else if (ownPiece(square)) {
      select(square)
    } else {
      clearSelection()
    }
  }

  function releaseSquare(from, to, dragged) {
    if (movedOnPress) {
      movedOnPress = false
      return
    }
    if (!humanTurn || promotion) return
    if (dragged) {
      if (to !== from && selected === from && targets[to]) tryMove(from, to)
    } else if (pressedSelected && from === to) {
      clearSelection()
    }
  }

  function tryMove(from, to) {
    var options = game.moves({ square: from, verbose: true }).filter(function(move) { return move.to === to })
    if (options.length === 0) return
    if (options[0].promotion) promotion = { from: from, to: to, color: options[0].color }
    else commitMove({ from: from, to: to }, true)
  }

  function choosePromotion(type) {
    if (!promotion || Model.PROMOTIONS.indexOf(type) === -1) return
    var move = { from: promotion.from, to: promotion.to, promotion: type }
    promotion = null
    commitMove(move, true)
  }

  function commitMove(move, byHuman) {
    var made = game.move(move)
    if (!made) return
    clearSelection()
    if (byHuman && cursor !== "") cursor = made.to
    sync()
    save()
    scheduleEngine()
  }

  // ------------------------------------------------------------- engine

  function stopEngineWork() {
    engine.cancel()
    engineMoveTimer.stop()
    queuedEngineMove = null
    promotion = null
  }

  function scheduleEngine() {
    engineMoveTimer.stop()
    queuedEngineMove = null
    if (!opened || !restored || !engineTurn) return
    requestedAt = Date.now()
    engine.request(game.fen(), level)
  }

  function engineReply(fen, move) {
    if (!engineTurn || fen !== game.fen()) return
    queuedEngineMove = { fen: fen, move: move }
    // A floor on the reply time, so the low levels do not answer before
    // the player's own move has visibly landed.
    engineMoveTimer.interval = Math.max(1, 450 - (Date.now() - requestedAt))
    engineMoveTimer.restart()
  }

  function playQueuedEngineMove() {
    var queued = queuedEngineMove
    queuedEngineMove = null
    if (!queued || !engineTurn || queued.fen !== game.fen()) return
    commitMove(queued.move, false)
  }

  // ------------------------------------------------------------ keyboard

  function moveCursor(dx, dy) {
    if (cursor === "") cursor = selected || lastTo || Model.viewSquare(52, flipped)
    else cursor = Model.stepSquare(cursor, dx, dy, flipped)
  }

  function activateCursor() {
    if (cursor === "") {
      moveCursor(0, 0)
      return
    }
    pressSquare(cursor)
    releaseSquare(cursor, cursor, false)
  }

  // (Not "escape": QML rejects methods named after JS globals.)
  function handleEscape() {
    if (promotion) promotion = null
    else if (selected !== "") clearSelection()
    else dismiss()
  }

  function handleKey(event) {
    if (promotion) {
      var type = Model.promotionKey(event.text)
      if (type !== "") {
        choosePromotion(type)
        return true
      }
    }
    switch (event.key) {
    case Qt.Key_Escape: handleEscape(); return true
    case Qt.Key_Left: case Qt.Key_H: moveCursor(-1, 0); return true
    case Qt.Key_Right: case Qt.Key_L: moveCursor(1, 0); return true
    case Qt.Key_Up: case Qt.Key_K: moveCursor(0, -1); return true
    case Qt.Key_Down: case Qt.Key_J: moveCursor(0, 1); return true
    case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Space: activateCursor(); return true
    case Qt.Key_U: undo(); return true
    case Qt.Key_N: newGame(); return true
    case Qt.Key_F: flip(); return true
    }
    return false
  }

  // ---------------------------------------------------------------- text

  function tr(key, arg) {
    return Model.text(lang, key, arg)
  }

  function playerName(side) {
    if (!engineGame) return Model.colorName(side, lang)
    return side === playerColor ? tr("you") : tr("stockfishLevel", level)
  }

  function takenGlyphs(side) {
    return (taken[side] || []).map(function(type) { return Model.GLYPHS[type] }).join(" ")
  }

  function advantageText(side) {
    var lead = side === "w" ? taken.advantage : -taken.advantage
    return lead > 0 ? "+" + lead : ""
  }

  function detailLine() {
    if (!engineGame) return tr("detailLocal")
    return tr("detailEngine", Model.colorName(playerColor, lang).toLowerCase())
  }

  // -------------------------------------------------------------- plumbing

  Engine {
    id: engine
    wanted: root.opened && root.engineGame && !root.result.over
    onBestMove: function(fen, move) { root.engineReply(fen, move) }
  }

  Timer {
    id: engineMoveTimer
    onTriggered: root.playQueuedEngineMove()
  }

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restore(text())
    onLoadFailed: root.restore("")
  }

  // ------------------------------------------------------------------ view

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-chess"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Util.alpha(Color.background, 0.6)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (root.handleKey(event)) event.accepted = true
      }

      BorderSurface {
        id: card
        anchors.centerIn: parent
        width: layout.implicitWidth + contentLeftInset + contentRightInset
        height: layout.implicitHeight + contentTopInset + contentBottomInset
        // Small or heavily scaled outputs: shrink the whole card rather
        // than clip it at the screen edge.
        scale: Math.min(1,
          (keyCatcher.width - Style.space(32)) / Math.max(1, width),
          (keyCatcher.height - Style.space(32)) / Math.max(1, height))
        color: Color.popups.background
        radius: Style.cornerRadius
        padding: Style.spacing.panelPadding
        borderSpec: Border.localOrSurfaceSpec("popups", "border", Color.popups.border, Color.popups.border, Math.max(1, Style.space(2)))

        // Swallow clicks so only the scrim outside the card dismisses.
        MouseArea {
          anchors.fill: parent
          onClicked: keyCatcher.forceActiveFocus()
        }

        RowLayout {
          id: layout
          x: card.contentLeftInset
          y: card.contentTopInset
          spacing: Style.spacing.panelGap

          ColumnLayout {
            id: boardColumn
            spacing: Style.spacing.sm

            PlayerStrip {
              Layout.fillWidth: true
              side: root.topColor
              name: root.playerName(side)
              moving: !root.result.over && root.turn === side
              captures: root.takenGlyphs(side)
              advantage: root.advantageText(side)
              foreground: root.fg
              dimmed: root.dim
              fontFamily: root.fontFamily
              pieceFont: root.pieceFont
            }

            Item {
              Layout.preferredWidth: root.squareSize * 8
              Layout.preferredHeight: root.squareSize * 8

              Board {
                id: board
                anchors.fill: parent
                pieces: root.pieces
                flipped: root.flipped
                selected: root.selected
                targets: root.targets
                lastFrom: root.lastFrom
                lastTo: root.lastTo
                checkSquare: root.checkSquare
                cursor: root.cursor
                interactive: root.humanTurn && root.promotion === null
                lightColor: root.lightSquare
                darkColor: root.darkSquare
                checkColor: Color.urgent
                pieceFont: root.pieceFont
                labelFont: root.fontFamily

                onSquarePressed: function(square) {
                  // The keyboard cursor hides once the mouse takes over.
                  root.cursor = ""
                  root.pressSquare(square)
                }
                onSquareReleased: function(from, to, dragged) { root.releaseSquare(from, to, dragged) }
              }

              // Promotion picker over the board.
              Rectangle {
                anchors.fill: parent
                visible: root.promotion !== null
                color: Qt.rgba(0, 0, 0, 0.5)

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.promotion = null
                }

                Row {
                  anchors.centerIn: parent
                  spacing: Style.spacing.lg

                  Repeater {
                    model: Model.PROMOTIONS

                    delegate: Rectangle {
                      id: choice
                      required property string modelData
                      readonly property bool whiteSide: root.promotion !== null && root.promotion.color === "w"

                      width: Math.round(root.squareSize * 1.15)
                      height: width
                      radius: Style.cornerRadius
                      color: choiceMouse.containsMouse ? root.lightSquare : Qt.darker(root.lightSquare, 1.12)
                      border.width: Math.max(1, Style.space(2))
                      border.color: Color.accent

                      Text {
                        anchors.centerIn: parent
                        text: Model.GLYPHS[choice.modelData]
                        color: choice.whiteSide ? board.whitePiece : board.blackPiece
                        style: Text.Outline
                        styleColor: choice.whiteSide ? board.whiteOutline : board.blackOutline
                        font.family: root.pieceFont
                        font.weight: Font.Black
                        font.pixelSize: Math.round(root.squareSize * 0.7)
                      }

                      MouseArea {
                        id: choiceMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.choosePromotion(choice.modelData)
                      }
                    }
                  }
                }
              }
            }

            PlayerStrip {
              Layout.fillWidth: true
              side: root.bottomColor
              name: root.playerName(side)
              moving: !root.result.over && root.turn === side
              captures: root.takenGlyphs(side)
              advantage: root.advantageText(side)
              foreground: root.fg
              dimmed: root.dim
              fontFamily: root.fontFamily
              pieceFont: root.pieceFont
            }
          }

          ColumnLayout {
            Layout.preferredWidth: Style.space(260)
            Layout.maximumWidth: Style.space(260)
            Layout.fillHeight: true
            spacing: Style.spacing.lg

            RowLayout {
              Layout.fillWidth: true

              Text {
                Layout.fillWidth: true
                text: "Ajedrez"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 2
              }

              Button {
                text: root.tr("close")
                fontSize: Style.font.bodySmall
                onClicked: root.dismiss()
              }
            }

            Text {
              Layout.fillWidth: true
              text: root.statusLine
              color: root.result.over ? Color.accent : root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
              wrapMode: Text.Wrap
            }

            Text {
              Layout.fillWidth: true
              text: root.detailLine()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            Text {
              Layout.fillWidth: true
              visible: root.engineGame && (engine.missing || engine.crashed)
              text: root.tr(engine.missing ? "installHint" : "engineCrashed")
              color: Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.Wrap
            }

            ListView {
              id: moveList
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: Style.space(80)
              clip: true
              model: Model.movePairs(root.sanList)
              boundsBehavior: Flickable.StopAtBounds
              // The model is rebuilt on every move; keep the newest one in view.
              onModelChanged: Qt.callLater(function() { moveList.positionViewAtEnd() })

              delegate: Row {
                id: pair
                required property var modelData
                required property int index
                readonly property bool lastRow: index === moveList.count - 1
                spacing: Style.spacing.md

                Text {
                  width: Style.space(30)
                  text: pair.modelData.number + "."
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  width: Style.space(84)
                  text: Model.displaySan(pair.modelData.white, root.lang)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: pair.lastRow && pair.modelData.black === ""
                }

                Text {
                  width: Style.space(84)
                  text: Model.displaySan(pair.modelData.black, root.lang)
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: pair.lastRow
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.md

              Button {
                text: root.tr("undo")
                bordered: true
                enabled: root.canUndo
                opacity: enabled ? 1 : 0.4
                fontSize: Style.font.bodySmall
                onClicked: root.undo()
              }

              Button {
                text: root.tr("flip")
                bordered: true
                fontSize: Style.font.bodySmall
                onClicked: root.flip()
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 1
              color: Util.alpha(root.fg, 0.15)
            }

            Text {
              visible: root.engineGame || root.nextMode === "engine"
              text: root.tr("levelHeading")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            ButtonGroup {
              visible: root.engineGame || root.nextMode === "engine"
              focusable: false
              fontSize: Style.font.bodySmall
              options: ["1", "2", "3", "4", "5", "6", "7", "8"]
              value: String(root.level)
              onChanged: function(value) { root.setLevel(Number(value)) }
            }

            Text {
              text: root.tr("newGameHeading")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1
            }

            ButtonGroup {
              focusable: false
              fontSize: Style.font.bodySmall
              options: [
                { value: "engine", label: root.tr("modeEngine") },
                { value: "local", label: root.tr("modeLocal") }
              ]
              value: root.nextMode
              onChanged: function(value) { root.setNextMode(value) }
            }

            ButtonGroup {
              visible: root.nextMode === "engine"
              focusable: false
              fontSize: Style.font.bodySmall
              options: [
                { value: "w", label: Model.colorName("w", root.lang) },
                { value: "b", label: Model.colorName("b", root.lang) },
                { value: "random", label: root.tr("random") }
              ]
              value: root.nextColor
              onChanged: function(value) { root.setNextColor(value) }
            }

            Text {
              Layout.fillWidth: true
              visible: root.settingsPending
              text: root.tr("appliesNext")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }

            Button {
              Layout.fillWidth: true
              text: root.tr("newGame")
              bordered: true
              selected: root.settingsPending || root.result.over
              onClicked: root.newGame()
            }

            Text {
              Layout.fillWidth: true
              text: root.tr("keysHelp")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
  }
}
