import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Stockfish over UCI. The process runs only while `wanted` is set (panel
// open, game against the engine still going), so it holds no memory while
// the board is hidden. A request made before the engine answers readyok
// waits in `pending`; every search reports the FEN it was started for, and
// the caller drops a bestmove whose FEN no longer matches the board.
Item {
  id: root
  visible: false

  property bool wanted: false
  property bool ready: false
  property bool missing: false
  property bool crashed: false
  property bool thinking: false
  property var pending: null
  property string searchFen: ""
  // `go` commands still waiting for their bestmove. A request that
  // supersedes a running search sends `stop` first, and only the bestmove
  // that brings this back to zero belongs to the newest search.
  property int outstanding: 0

  signal bestMove(string fen, var move)

  onWantedChanged: wanted ? start() : stop()

  function start() {
    if (proc.running) return
    ready = false
    crashed = false
    outstanding = 0
    proc.running = true
  }

  function stop() {
    pending = null
    thinking = false
    searchFen = ""
    outstanding = 0
    ready = false
    if (proc.running) proc.running = false
  }

  function request(fen, level) {
    if (missing) {
      thinking = false
      return
    }
    pending = { fen: fen, level: level }
    thinking = true
    if (!proc.running) start()
    else if (ready) flush()
  }

  function cancel() {
    pending = null
    thinking = false
    // An empty FEN never matches the board, so the stopped search's
    // bestmove is ignored when it arrives.
    searchFen = ""
    if (outstanding > 0) send("stop")
  }

  function flush() {
    if (!pending) return
    var job = pending
    pending = null
    if (outstanding > 0) send("stop")
    send("setoption name Skill Level value " + Model.levelSpec(job.level).skill)
    send("position fen " + job.fen)
    send(Model.goCommand(job.level))
    searchFen = job.fen
    outstanding++
    thinking = true
  }

  function send(line) {
    if (proc.running) proc.write(line + "\n")
  }

  function handleLine(line) {
    var text = String(line).trim()
    if (text === "uciok") {
      send("isready")
    } else if (text === "readyok") {
      ready = true
      flush()
    } else if (text.indexOf("bestmove") === 0) {
      outstanding = Math.max(0, outstanding - 1)
      if (outstanding > 0) return
      thinking = pending !== null
      var move = Model.parseBestMove(text)
      if (move && searchFen !== "") root.bestMove(searchFen, move)
    }
  }

  Process {
    id: proc
    // Exit 127 from the wrapper means the binary is not installed, which
    // the panel reports with the install command instead of a crash.
    command: ["sh", "-c", "command -v stockfish >/dev/null 2>&1 || exit 127; exec stockfish"]
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(data) { root.handleLine(data) }
    }
    onStarted: root.send("uci")
    onExited: function(exitCode) {
      var wasWanted = root.wanted
      root.ready = false
      root.thinking = false
      root.outstanding = 0
      root.searchFen = ""
      root.pending = null
      if (exitCode === 127) root.missing = true
      else if (wasWanted && exitCode !== 0) root.crashed = true
    }
  }
}
