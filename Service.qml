import QtQuick
import Quickshell
import Quickshell.Io

// D&D Beyond data service. The python helper owns auth (CobaltSession cookie ->
// bearer token) and the v5 payload transform; this item schedules it and
// exposes one defensive model to the panel.
//
//   states: "loading" | "ok" | "error" | "no-auth"
Item {
  id: root

  property var settings: ({})

  // List state.
  property string state: "loading"
  property string message: "Loading characters…"
  property var characters: []
  // Selection persists in the helper's state.json, not shell.json — a
  // shell.json write recreates the widget and breaks in-progress clicks.
  property string selectedId: ""

  // Sheet state for the selected character.
  property string characterId: ""
  property var sheet: null
  property string sheetState: "idle" // idle | loading | ok | error
  property string sheetMessage: ""

  property string _listOut: ""
  property string _sheetOut: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  readonly property int refreshIntervalSec: {
    var value = parseInt(String(setting("refreshIntervalSec", 300)), 10)
    if (!isFinite(value)) value = 300
    return Math.max(60, Math.min(3600, value))
  }

  function helperPath() {
    return decodeURIComponent(Qt.resolvedUrl("omarchy-dndbeyond-fetch").toString().replace(/^file:\/\//, ""))
  }

  // ---- session cookie (stored in the helper's config.json, mode 600) ---------

  readonly property string configPath: {
    var xdg = Quickshell.env("XDG_CONFIG_HOME")
    var home = Quickshell.env("HOME")
    return (xdg !== "" ? xdg : home + "/.config") + "/omarchy-dndbeyond/config.json"
  }
  property bool cookieSet: false
  property string cookieTail: ""
  property var configCharacterIds: []
  property string _configText: ""

  function applyConfig(raw) {
    _configText = String(raw || "")
    try {
      var cfg = JSON.parse(_configText)
      var cookie = String(cfg.cobaltSession || "")
      cookieSet = cookie !== "" && cookie.indexOf("PASTE_") !== 0
      cookieTail = cookieSet ? cookie.slice(-4) : ""
      configCharacterIds = Array.isArray(cfg.characterIds) ? cfg.characterIds : []
    } catch (e) {
      cookieSet = false
      cookieTail = ""
      configCharacterIds = []
    }
  }

  // Write the cookie back, preserving other keys; the cached bearer token
  // belongs to the old cookie, so it goes. Refresh once the write lands.
  function setCookie(value) {
    var cookie = String(value || "").trim()
    if (cookie === "") return
    var cfg = {}
    try { cfg = JSON.parse(_configText) } catch (e) {}
    if (typeof cfg !== "object" || cfg === null) cfg = {}
    cfg.cobaltSession = cookie
    configView.pendingSave = true
    configView.setText(JSON.stringify(cfg, null, 2) + "\n")
  }

  FileView {
    id: configView
    property bool pendingSave: false
    path: root.configPath
    printErrors: false
    atomicWrites: true
    watchChanges: true
    onLoaded: {
      if (pendingSave) return
      root.applyConfig(text())
    }
    onLoadFailed: function(err) { root.applyConfig("") }
    onFileChanged: if (!pendingSave) reload()
    onSaved: {
      pendingSave = false
      root.applyConfig(text())
      // atomic rename resets permissions; the cookie must stay private.
      chmodProc.running = true
      root.refresh()
    }
    onSaveFailed: function(err) { pendingSave = false }
  }

  Process {
    id: chmodProc
    running: false
    command: ["bash", "-c", "chmod 600 " + root.configPath + " && rm -f " + root.configPath.replace(/config\.json$/, "token.json")]
  }

  // ---- character list -------------------------------------------------------

  function refresh() {
    if (listProc.running) return
    state = "loading"
    message = "Loading characters…"
    _listOut = ""
    listProc.running = true
  }

  Process {
    id: listProc
    running: false
    command: [root.helperPath(), "list", "--extra-ids", String(root.setting("extraCharacterIds", ""))]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._listOut = text }
    onExited: function(code) { root.applyList(root._listOut) }
  }

  function applyList(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      state = "error"
      message = "Helper returned an unreadable response."
      return
    }
    state = String(data.state || "error")
    message = String(data.message || "")
    characters = Array.isArray(data.characters) ? data.characters : []
    selectedId = String(data.selectedId || "")
    if (state === "ok") pickCharacter()
  }

  // Prefer the helper-persisted selection if it still exists, else the first row.
  function pickCharacter() {
    if (characters.length === 0) { sheet = null; sheetState = "idle"; return }
    if (selectedId !== "") {
      for (var i = 0; i < characters.length; i++) {
        if (String(characters[i].id) === selectedId) {
          characterId = selectedId
          loadSheet(selectedId)
          return
        }
      }
    }
    characterId = String(characters[0].id)
    loadSheet(characterId)
  }

  function selectCharacter(id) {
    var value = String(id || "")
    if (value === "") return
    selectedId = value
    if (!selectProc.running) {
      selectProc.command = [helperPath(), "select", value]
      selectProc.running = true
    }
    if (value === characterId) return
    characterId = value
    loadSheet(value)
  }

  Process {
    id: selectProc
    running: false
  }

  // ---- selected sheet --------------------------------------------------------

  function loadSheet(id) {
    var value = String(id || "")
    if (value === "" || sheetProc.running) return
    sheetState = "loading"
    sheetMessage = "Loading sheet…"
    _sheetOut = ""
    sheetProc.command = [helperPath(), "sheet", value]
    sheetProc.running = true
  }

  Process {
    id: sheetProc
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._sheetOut = text }
    onExited: function(code) { root.applySheet(root._sheetOut) }
  }

  function applySheet(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (error) {
      sheetState = "error"
      sheetMessage = "Helper returned an unreadable response."
      return
    }
    if (String(data.state) === "ok" && data.sheet) {
      sheet = data.sheet
      sheetState = "ok"
      sheetMessage = ""
    } else {
      sheetState = String(data.state || "error") === "no-auth" ? "error" : "error"
      sheetMessage = String(data.message || "Could not load the sheet.")
      if (String(data.state) === "no-auth") { state = "no-auth"; message = sheetMessage }
    }
  }

  // ---- rests (server-side write) --------------------------------------------

  property bool resting: false

  // Short rest restores pact magic + short-rest abilities; long rest also HP,
  // all slots, hit dice, death saves. Helper re-fetches the sheet after.
  function rest(kind) {
    if (restProc.running || characterId === "") return
    resting = true
    sheetMessage = (kind === "long" ? "Long" : "Short") + " resting…"
    _sheetOut = ""
    restProc.command = [helperPath(), "rest", kind, characterId]
    restProc.running = true
  }

  Process {
    id: restProc
    running: false
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._sheetOut = text }
    onExited: function(code) { root.resting = false; root.applySheet(root._sheetOut) }
  }

  // Re-fetch the open sheet on a slow timer; the panel also refreshes on open.
  Timer {
    interval: root.refreshIntervalSec * 1000
    running: root.characterId !== ""
    repeat: true
    onTriggered: root.loadSheet(root.characterId)
  }

  Component.onCompleted: refresh()
}
