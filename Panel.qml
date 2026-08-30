import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// brianstarke.dndbeyond — D&D Beyond character sheets in the bar.
//
// One icon, one card. The card shows the selected character from your D&D
// Beyond account with tabs: Main (abilities, HP, AC…), Skills, Spells,
// Features, Inventory. Auth lives in ~/.config/omarchy-dndbeyond/config.json;
// the helper script does the fetching, Service.qml parses, this file draws.
Panel {
  id: root
  moduleName: "brianstarke.dndbeyond"
  ipcTarget: "brianstarke.dndbeyond"
  manageIpc: false

  // ---- theme ----------------------------------------------------------------

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // ---- config -----------------------------------------------------------------

  readonly property int cardWidth: Style.space(Math.max(360, Number(setting("width", 480)) || 480))
  readonly property int cardCap: Style.space(Math.max(300, Number(setting("maxHeight", 640)) || 640))

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === false) return value
    var text = String(value).toLowerCase()
    return text === "true" || text === "yes" || text === "on" || text === "1"
  }

  // Settings persist into this widget's shell.json entry; the shell
  // hot-reloads it and every instance re-reads. Applied locally first so the
  // toggle throws on the click.
  function persistSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- state ------------------------------------------------------------------

  readonly property var tabs: ["Main", "Skills", "Spells", "Features", "Inventory", "Notes"]
  property int activeTab: 0
  property bool chooserOpen: false
  property string expandedSpell: ""
  property bool portraitZoom: false
  property bool settingsOpen: false

  readonly property var tabOptions: [
    { value: "Main", label: "Main" }, { value: "Skills", label: "Skills" },
    { value: "Spells", label: "Spells" }, { value: "Features", label: "Features" },
    { value: "Inventory", label: "Inventory" }, { value: "Notes", label: "Notes" }
  ]
  readonly property var refreshOptions: [
    { value: "60", label: "Every minute" },
    { value: "300", label: "Every 5 minutes" },
    { value: "600", label: "Every 10 minutes" },
    { value: "900", label: "Every 15 minutes" },
    { value: "1800", label: "Every 30 minutes" },
    { value: "3600", label: "Every hour" }
  ]

  // Strip the 150px crop params for the full-size portrait.
  readonly property string portraitFullUrl: {
    var url = sheet && sheet.avatarUrl ? String(sheet.avatarUrl) : ""
    var q = url.indexOf("?")
    return q > 0 ? url.slice(0, q) : url
  }

  readonly property var sheet: ddb.sheet
  readonly property string heroTitle: sheet ? String(sheet.name) : "D&D Beyond"
  readonly property string heroMeta: {
    if (ddb.state === "no-auth") return "not authenticated"
    if (ddb.state === "error") return "error"
    if (ddb.sheetState === "loading") return "loading sheet…"
    if (!sheet) return ddb.state === "loading" ? "loading…" : "no character"
    var parts = []
    if (sheet.race) parts.push(sheet.race)
    var cls = []
    for (var i = 0; i < sheet.classes.length; i++) {
      var c = sheet.classes[i]
      cls.push(c.name + (c.subclass ? " (" + c.subclass + ")" : "") + " " + c.level)
    }
    parts.push(cls.join(" / "))
    parts.push("Level " + sheet.level)
    return parts.join(" · ")
  }

  function defaultTabIndex() {
    var want = String(setting("defaultTab", "Main"))
    var idx = tabs.indexOf(want)
    return idx < 0 ? 0 : idx
  }

  function setTab(index) {
    activeTab = Math.max(0, Math.min(tabs.length - 1, index))
    chooserOpen = false
    expandedSpell = ""
    // sheetFlick lives inside the card component; reach it through the loader.
    Qt.callLater(function() {
      if (cardLoader.item && cardLoader.item.resetScroll) cardLoader.item.resetScroll()
    })
  }

  // ---- bar HP color: green > 75%, red < 25%, yellow between -------------------

  readonly property real hpFraction: sheet && sheet.hp.max > 0 ? sheet.hp.current / sheet.hp.max : 1
  readonly property color hpColor: !sheet || !boolSetting("colorHealth", true) ? foreground
                                   : hpFraction > 0.75 ? "#7fb069"
                                   : hpFraction < 0.25 ? urgent
                                   : "#e0a458"

  // ---- dice rolls -------------------------------------------------------------

  property string rollLabel: ""
  property string rollKind: "check"   // "check" (d20+mod) | "damage" (NdM+mod)
  property int rollDie: 0
  property int rollMod: 0
  property string rollDiceText: ""    // damage: "2d6 + 3 → (4, 2)"
  readonly property int rollTotal: rollDie + rollMod
  readonly property bool rollNat20: rollKind === "check" && rollDie === 20
  readonly property bool rollNat1: rollKind === "check" && rollDie === 1

  function roll(label, mod) {
    rollLabel = String(label)
    rollKind = "check"
    rollMod = Number(mod) || 0
    rollDie = 1 + Math.floor(Math.random() * 20)
  }

  // Damage: diceString like "1d8", plus the flat bonus. rollDie carries the
  // dice subtotal so rollTotal stays dice+bonus.
  function rollDamage(label, diceString, bonus) {
    var m = /^(\d+)d(\d+)$/.exec(String(diceString || ""))
    rollLabel = String(label)
    rollKind = "damage"
    rollMod = Number(bonus) || 0
    if (!m) { rollKind = "check"; roll(label, bonus); return }
    var count = parseInt(m[1], 10), sides = parseInt(m[2], 10)
    var rolls = [], sum = 0
    for (var i = 0; i < count; i++) {
      var r = 1 + Math.floor(Math.random() * sides)
      rolls.push(r)
      sum += r
    }
    rollDie = sum
    rollDiceText = count + "d" + sides + " → (" + rolls.join(", ") + ")"
  }

  // Two-click arm: first click asks, second within 4s confirms the rest.
  property string restArm: ""

  function requestRest(kind) {
    if (ddb.resting) return
    if (restArm === kind) {
      restArm = ""
      restArmTimer.stop()
      ddb.rest(kind)
    } else {
      restArm = kind
      restArmTimer.restart()
    }
  }

  Timer {
    id: restArmTimer
    interval: 4000
    onTriggered: root.restArm = ""
  }

  function cycleTab(direction) {
    setTab((activeTab + direction + tabs.length) % tabs.length)
  }

  function chooseCharacter(id) {
    chooserOpen = false
    ddb.selectCharacter(id)
  }

  readonly property var visibleCharacters: {
    var out = []
    for (var i = 0; i < ddb.characters.length; i++)
      if (!ddb.characters[i].hidden) out.push(ddb.characters[i])
    return out
  }

  function isConfigId(id) {
    for (var i = 0; i < ddb.configCharacterIds.length; i++)
      if (String(ddb.configCharacterIds[i]) === String(id)) return true
    return false
  }

  // Resolve an id to a name once the helper's list has it, else the id.
  function characterName(id) {
    for (var i = 0; i < ddb.characters.length; i++)
      if (String(ddb.characters[i].id) === String(id)) return ddb.characters[i].name
    return "Character " + id
  }

  function fmtSigned(value) {
    var n = Number(value) || 0
    return (n >= 0 ? "+" : "") + n
  }

  // Spells tab model: flat list of {header} and {spell} rows, prepared first.
  function spellRows() {
    if (!sheet || !sheet.spells) return []
    // The helper flags `known`: prepared/alwaysPrepared, or everything for
    // known-casters (warlock, sorcerer…) that don't prepare spells.
    var prepared = []
    for (var i = 0; i < sheet.spells.length; i++) {
      var s = sheet.spells[i]
      if (s.known || s.prepared || s.alwaysPrepared) prepared.push(s)
    }
    var rows = []
    var lastLevel = -1
    for (var j = 0; j < prepared.length; j++) {
      var sp = prepared[j]
      if (sp.level !== lastLevel) {
        lastLevel = sp.level
        rows.push({ header: true, label: sp.level === 0 ? "Cantrips" : "Level " + sp.level })
      }
      rows.push({ header: false, spell: sp })
    }
    return rows
  }

  // ---- lifecycle --------------------------------------------------------------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: {
    chooserOpen = false
    restArm = ""
    if (!opened) {
      rollLabel = ""
      portraitZoom = false
      settingsOpen = false
    }
    if (opened) {
      activeTab = defaultTabIndex()
      ddb.refresh()
    }
  }

  Service {
    id: ddb
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { ddb.refresh(); return "ok" }
    // Global-keybind friendly: rolls and pops the card so the banner is seen.
    function rollInitiative(): string {
      if (!ddb.sheet) return "no sheet loaded"
      root.roll("Initiative", ddb.sheet.initiative)
      if (!root.opened) root.open()
      return "ok"
    }
    function rest(kind: string): string {
      if (kind !== "short" && kind !== "long") return "usage: rest short|long"
      ddb.rest(kind)
      return "ok"
    }
    function select(id: string): string { root.chooseCharacter(id); return "ok" }
    function settings(): string { root.settingsOpen = true; root.open(); return "ok" }
    function zoomPortrait(): string { root.open(); root.portraitZoom = true; return "ok" }
    function expandSpell(name: string): string { root.expandedSpell = name; root.open(); return "ok" }
    function tab(name: string): string {
      var idx = root.tabs.indexOf(name)
      if (idx < 0) return "no such tab"
      root.setTab(idx)
      return "ok"
    }
    function status(): string {
      return ddb.state + "/" + ddb.sheetState + (ddb.cookieSet ? "/cookie:…" + ddb.cookieTail : "/cookie:missing")
    }
  }

  // WidgetButton, not BarIconButton: the icon slot squeezes multi-char text
  // through OpticalGlyph ("bunched up"); the text label path sizes the slot to
  // the string and pads it, like the clock.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // d20 + live HP. The stock label is single-color, so it stays hidden and a
    // two-Text row draws on top: glyph in bar color, numbers tinted by HP.
    text: ""
    hasVisualContent: true
    labelVisible: false
    fixedWidth: vertical ? -1 : buttonRow.implicitWidth + Style.spaceReal(8.75) * 2
    fontSize: Style.bar.iconFont
    horizontalMargin: 8.75
    tooltipText: sheet ? String(sheet.name) : "D&D Beyond"
    active: false
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton || buttonCode === Qt.MiddleButton) ddb.refresh()
      else root.toggle()
    }

    Row {
      id: buttonRow
      anchors.centerIn: parent
      spacing: Style.spaceReal(5)
      visible: !button.vertical

      Text {
        text: "󱅕"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: button.fontSize
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: sheet !== null && root.boolSetting("showCharacterName", false)
        text: sheet ? String(sheet.name) : ""
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Math.round(button.fontSize * 0.85)
        anchors.verticalCenter: parent.verticalCenter
      }
      Text {
        visible: sheet !== null && root.boolSetting("showHealth", true)
        text: sheet ? String(sheet.hp.current) + "/" + String(sheet.hp.max) : ""
        color: root.hpColor
        font.family: root.fontFamily
        font.pixelSize: Math.round(button.fontSize * 0.85)
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: cardLoader.item ? cardLoader.item.keyCatcherItem : null
    contentWidth: panel.fittedContentWidth(root.cardWidth)
    contentHeight: panel.fittedContentHeight(cardLoader.item ? cardLoader.item.implicitHeight : 0, root.cardCap)

    Loader {
      id: cardLoader
      anchors.fill: parent
      active: panel.visible
      sourceComponent: cardComponent
    }
  }

  // ---- the card -----------------------------------------------------------------

  Component {
    id: cardComponent

    Item {
      implicitHeight: column.implicitHeight

      // KeyboardPanel force-focuses this on open; without it the keyCatcher
      // never sees key presses (footer shortcuts dead).
      property alias keyCatcherItem: keyCatcher

      function resetScroll() {
        if (sheetFlick.item) sheetFlick.item.contentY = 0
      }

      PanelKeyCatcher {
        id: keyCatcher
        anchors.fill: parent
        onCloseRequested: root.close()
        onTabRequested: function(direction) { root.cycleTab(direction) }
        onMoveRequested: function(dx, dy) {
          if (dy === 0 || !sheetFlick.item) return
          var f = sheetFlick.item
          var maxY = Math.max(0, f.contentHeight - f.height)
          f.contentY = Math.max(0, Math.min(maxY, f.contentY + dy * Style.space(36)))
        }
        onTextKey: function(t) {
          if (t === "r") ddb.refresh()
          else if (t === "i" && sheet) root.roll("Initiative", sheet.initiative)
          else if (t === "s") root.settingsOpen = !root.settingsOpen
          else if (t === "c") root.chooserOpen = !root.chooserOpen
          else if (t === "[") root.cycleTab(-1)
          else if (t === "]") root.cycleTab(1)
          else {
            var n = parseInt(t, 10)
            if (n >= 1 && n <= root.tabs.length) root.setTab(n - 1)
          }
        }

        Column {
          id: column
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          spacing: Style.space(10)

          PanelHero {
            width: parent.width
            title: root.heroTitle
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Item {
                implicitWidth: Style.space(40)
                implicitHeight: Style.space(40)

                HoverHandler { id: portraitHover; enabled: portrait.status === Image.Ready; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                  anchors.fill: parent
                  enabled: portrait.status === Image.Ready
                  onClicked: root.portraitZoom = true
                }
                PanelToolTip { visible: portraitHover.hovered; text: "Enlarge portrait"; fontFamily: root.fontFamily }

                // Dice glyph until the portrait is fetched (or if none set).
                Rectangle {
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: Style.controlFill(false, false, root.foreground, Color.accent)
                  visible: portrait.status !== Image.Ready
                  Text {
                    anchors.centerIn: parent
                    text: "󱅕"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.display
                  }
                }
                Image {
                  id: portrait
                  anchors.fill: parent
                  source: sheet && sheet.avatarUrl ? String(sheet.avatarUrl) : ""
                  asynchronous: true
                  fillMode: Image.PreserveAspectCrop
                  visible: status === Image.Ready
                }
                // Subtle frame on top of the (square) portrait.
                BorderSurface {
                  anchors.fill: parent
                  visible: portrait.status === Image.Ready
                  color: "transparent"
                  borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
                  radius: Style.cornerRadius
                }
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(6)

                PanelActionButton {
                  iconText: "󰒓"
                  bordered: true
                  hasCursor: root.settingsOpen
                  foreground: root.foreground
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  tooltipText: root.settingsOpen ? "Back to sheet (s)" : "Settings (s)"
                  onClicked: root.settingsOpen = !root.settingsOpen
                }
                PanelActionButton {
                  iconText: "󰑐"
                  bordered: true
                  foreground: root.foreground
                  hoverColor: root.foreground
                  fontFamily: root.fontFamily
                  tooltipText: "Refresh (r)"
                  onClicked: ddb.refresh()
                }
              }
            }
          }

          // ---- roll banner: latest d20 roll with breakdown ----
          Item {
            width: parent.width
            visible: root.rollLabel !== ""
            implicitHeight: rollBannerLabel.implicitHeight + Style.space(6)

            BorderSurface {
              anchors.fill: parent
              color: Style.controlFill(false, rollBannerHover.hovered, root.foreground, Color.accent)
              borderSpec: Border.controlSpec(rollBannerHover.hovered ? "hover-cursor" : "normal",
                                             root.rollNat1 ? root.urgent : root.foreground,
                                             Color.accent)
              radius: Style.cornerRadius
            }
            HoverHandler { id: rollBannerHover }

            Row {
              id: rollBannerLabel
              anchors.left: parent.left
              anchors.right: rollDismiss.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(6)

              Text {
                text: "󱅕"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: root.rollLabel
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                // checks: "17 + 1"; damage: "1d4 → (3) + 2"
                text: (root.rollKind === "damage" ? root.rollDiceText : String(root.rollDie))
                      + (root.rollMod === 0 ? "" : (root.rollMod < 0 ? " − " + Math.abs(root.rollMod) : " + " + root.rollMod))
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: "="
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                text: String(root.rollTotal)
                color: root.rollNat20 ? Color.accent : (root.rollNat1 ? root.urgent : root.foreground)
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                visible: root.rollNat20 || root.rollNat1
                text: root.rollNat20 ? "nat 20!" : "nat 1…"
                color: root.rollNat20 ? Color.accent : root.urgent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.italic: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }
            Text {
              id: rollDismiss
              anchors.right: parent.right
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              text: "✕"
              color: rollDismissHover.hovered ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              HoverHandler { id: rollDismissHover; cursorShape: Qt.PointingHandCursor }
              TapHandler { onTapped: root.rollLabel = "" }
            }
          }

          // ---- settings pane ----
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.settingsOpen

            Toggle {
              width: parent.width
              label: "Show HP in bar"
              description: "Current/max hit points next to the dice glyph."
              checked: root.boolSetting("showHealth", true)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSetting("showHealth", !checked)
            }
            Toggle {
              width: parent.width
              label: "Color HP by health"
              description: "Green above 75%, yellow between, red below 25%."
              checked: root.boolSetting("colorHealth", true)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSetting("colorHealth", !checked)
            }
            Toggle {
              width: parent.width
              label: "Show character name in bar"
              description: "Selected character's name next to the dice glyph."
              checked: root.boolSetting("showCharacterName", false)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.persistSetting("showCharacterName", !checked)
            }
            PanelSeparator { foreground: root.foreground }

            // ---- default tab + refresh interval ----
            Text {
              text: "Default tab"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Dropdown {
              id: defaultTabDropdown
              width: parent.width
              showLabel: false
              options: root.tabOptions
              foreground: root.foreground
              background: Color.popups.background
              accent: Color.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.persistSetting("defaultTab", value) }
              Binding on value { value: String(root.setting("defaultTab", "Main")) }
            }

            Text {
              text: "Refresh interval"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Dropdown {
              id: refreshDropdown
              width: parent.width
              showLabel: false
              options: root.refreshOptions
              foreground: root.foreground
              background: Color.popups.background
              accent: Color.accent
              fontFamily: root.fontFamily
              onChanged: function(value) { root.persistSetting("refreshIntervalSec", parseInt(value, 10)) }
              Binding on value { value: String(root.setting("refreshIntervalSec", 300)) }
            }

            PanelSeparator { foreground: root.foreground }

            // ---- card size ----
            Text {
              text: "Card width — " + Number(root.setting("width", 480)) + " px"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 360
              maximum: 900
              step: 20
              integer: true
              value: Number(root.setting("width", 480))
              onReleased: function(value) { root.persistSetting("width", Math.round(value)) }
            }
            Text {
              text: "Card max height — " + Number(root.setting("maxHeight", 640)) + " px"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            PanelSlider {
              width: parent.width
              bar: root.bar
              minimum: 300
              maximum: 1400
              step: 20
              integer: true
              value: Number(root.setting("maxHeight", 640))
              onReleased: function(value) { root.persistSetting("maxHeight", Math.round(value)) }
            }

            PanelSeparator { foreground: root.foreground }

            // ---- session cookie ----
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: ddb.cookieSet
                    ? "Session cookie set (…" + ddb.cookieTail + "). Paste a fresh CobaltSession cookie to replace it — expires every few weeks."
                    : "No session cookie. Log into dndbeyond.com, then copy the CobaltSession cookie from browser dev tools (Application → Cookies) and paste it here."
              color: ddb.cookieSet ? root.dim : root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            TextField {
              width: parent.width
              password: true
              placeholderText: "Paste CobaltSession cookie, press Enter"
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              text: ""
              onAccepted: {
                ddb.setCookie(text)
                text = ""
              }
            }

            PanelSeparator { foreground: root.foreground }

            // ---- characters: hide from picker, add/remove extras --------------
            Text {
              width: parent.width
              wrapMode: Text.Wrap
              text: "Characters — hide any from the picker. Add extras (shared or private characters the account list misses) by ID from the dndbeyond.com/characters/<id> URL. Stored in config.json."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: ddb.characters
              delegate: Item {
                id: charRow
                required property var modelData
                width: parent.width
                implicitHeight: Style.spacing.popupRowHeight

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(4)
                  anchors.verticalCenter: parent.verticalCenter
                  width: parent.width - hideLink.implicitWidth
                           - (removeLink.visible ? removeLink.implicitWidth : 0) - Style.space(24)
                  text: charRow.modelData.name + "  ·  " + charRow.modelData.id
                  color: charRow.modelData.hidden ? root.dim : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.strikeout: charRow.modelData.hidden === true
                  elide: Text.ElideRight
                }
                Text {
                  id: hideLink
                  anchors.right: removeLink.visible ? removeLink.left : parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  text: charRow.modelData.hidden ? "show" : "hide"
                  color: hideHover.hovered ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  HoverHandler { id: hideHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: ddb.setCharacterHidden(charRow.modelData.id, !charRow.modelData.hidden) }
                }
                Text {
                  id: removeLink
                  visible: root.isConfigId(charRow.modelData.id)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: "✕"
                  color: removeIdHover.hovered ? root.urgent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  HoverHandler { id: removeIdHover; cursorShape: Qt.PointingHandCursor }
                  TapHandler { onTapped: ddb.removeCharacterId(charRow.modelData.id) }
                  PanelToolTip { visible: removeIdHover.hovered; text: "Remove from config.json"; fontFamily: root.fontFamily }
                }
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              TextField {
                id: addIdField
                width: parent.width - addIdLink.implicitWidth - Style.space(8)
                placeholderText: "Character ID, e.g. 167909431"
                foreground: root.foreground
                accent: Color.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                text: ""
                onAccepted: {
                  ddb.addCharacterId(text)
                  text = ""
                }
              }
              Text {
                id: addIdLink
                text: "＋ add"
                color: addIdHover.hovered ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
                HoverHandler { id: addIdHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                  onTapped: {
                    ddb.addCharacterId(addIdField.text)
                    addIdField.text = ""
                  }
                }
              }
            }
          }

          // ---- character chooser ----
          Column {
            width: parent.width
            spacing: Style.space(2)
            visible: !root.settingsOpen && ddb.state === "ok" && root.visibleCharacters.length > 0

            CursorSurface {
              width: parent.width
              implicitHeight: Style.spacing.popupRowHeight
              hasCursor: root.chooserOpen
              foreground: root.foreground
              color: root.chooserOpen ? fill : "transparent"

              RowLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(8)

                Text {
                  text: "Character"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
                Text {
                  Layout.fillWidth: true
                  text: root.sheet ? String(root.sheet.name) : "…"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }
                Text {
                  text: root.chooserOpen ? "󰅃" : "󰅀"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.chooserOpen = !root.chooserOpen
              }
            }

            Repeater {
              model: root.chooserOpen ? root.visibleCharacters : []
              CursorSurface {
                required property var modelData
                width: column.width
                implicitHeight: Style.spacing.popupRowHeight
                hasCursor: String(modelData.id) === ddb.characterId
                foreground: root.foreground
                color: hasCursor ? fill : "transparent"

                RowLayout {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(22)
                  anchors.rightMargin: Style.space(10)

                  Text {
                    Layout.fillWidth: true
                    text: String(modelData.name)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                  }
                  Text {
                    visible: String(modelData.campaign || "") !== ""
                    text: String(modelData.campaign || "")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                    Layout.maximumWidth: column.width * 0.4
                  }
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.chooseCharacter(modelData.id)
                }
              }
            }
          }

          // ---- error / auth states ----
          Text {
            visible: ddb.state === "no-auth" || ddb.state === "error" || (ddb.state === "ok" && ddb.characters.length === 0)
            width: parent.width
            wrapMode: Text.Wrap
            color: ddb.state === "ok" ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            text: ddb.state === "no-auth"
                  ? ddb.message + "\n\nSetup: copy your CobaltSession cookie into ~/.config/omarchy-dndbeyond/config.json — see the plugin README."
                  : (ddb.state === "error" ? ddb.message : "No characters found on this account.")
          }

          // ---- tab bar ----
          Row {
            width: parent.width
            spacing: Style.space(2)
            visible: sheet !== null && !root.settingsOpen

            Repeater {
              model: root.tabs
              delegate: Item {
                required property string modelData
                required property int index
                readonly property bool current: root.activeTab === index
                implicitWidth: tabLabel.implicitWidth + Style.space(16)
                implicitHeight: tabLabel.implicitHeight + Style.space(10)

                Rectangle {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Style.space(2)
                  color: parent.current ? Color.accent : "transparent"
                }
                Text {
                  id: tabLabel
                  anchors.centerIn: parent
                  text: parent.modelData
                  color: parent.current ? root.foreground : (tabHover.hovered ? root.foreground : root.dim)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: parent.current
                }
                HoverHandler { id: tabHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.setTab(parent.index) }
              }
            }
          }

          PanelSeparator { foreground: root.foreground; visible: sheet !== null && !root.settingsOpen }

          // ---- tab body ----
          Loader {
            id: sheetFlick
            width: parent.width
            visible: sheet !== null && !root.settingsOpen
            sourceComponent: root.activeTab === 0 ? mainTab
                           : root.activeTab === 1 ? skillsTab
                           : root.activeTab === 2 ? spellsTab
                           : root.activeTab === 3 ? featuresTab
                           : root.activeTab === 4 ? inventoryTab
                           : notesTab
          }

          Text {
            visible: sheet === null && ddb.sheetState === "loading"
            width: parent.width
            text: "Rolling for initiative…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // ---- footer ----
          Item {
            width: parent.width
            implicitHeight: footRight.implicitHeight
            visible: sheet !== null

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              width: parent.width - footRight.implicitWidth - Style.space(16)
              text: sheet && sheet.campaign ? String(sheet.campaign) : (sheet ? "fetched " + String(sheet.fetchedAt) : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            Text {
              id: footRight
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              text: "1-6 tabs · c character · r refresh · esc close"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // ---- portrait zoom overlay: full-size image over the card ----
      Item {
        anchors.fill: parent
        visible: root.portraitZoom && root.portraitFullUrl !== ""
        z: 10

        Rectangle {
          anchors.fill: parent
          color: "#000000"
          opacity: 0.85
        }
        Image {
          anchors.centerIn: parent
          width: parent.width - Style.space(24)
          height: parent.height - Style.space(24)
          source: root.portraitFullUrl
          asynchronous: true
          fillMode: Image.PreserveAspectFit
          smooth: true
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(6)
          text: "click to close"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        MouseArea {
          anchors.fill: parent
          onClicked: root.portraitZoom = false
        }
      }
    }
  }

  // ---- shared bits -------------------------------------------------------------

  component StatBox: Column {
    property string label: ""
    property string value: ""
    property string sub: ""
    property bool rollable: false
    signal rolled()
    width: Style.space(64)
    spacing: Style.space(1)

    HoverHandler { id: statHover; enabled: parent.rollable; cursorShape: Qt.PointingHandCursor }
    TapHandler { enabled: parent.rollable; onTapped: parent.rolled() }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }
    Text {
      visible: parent.sub !== ""
      anchors.horizontalCenter: parent.horizontalCenter
      text: parent.sub
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  component InfoRow: Item {
    property string label: ""
    property string value: ""
    implicitHeight: Math.max(infoLabel.implicitHeight, infoValue.implicitHeight)

    Text {
      id: infoLabel
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      text: label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      id: infoValue
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      width: parent.width - infoLabel.implicitWidth - Style.space(24)
      horizontalAlignment: Text.AlignRight
      text: value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  component SheetFlick: Flickable {
    // Alias `data`, not `children`: tab bodies declare Repeaters, and the
    // children list silently drops non-Item objects, blanking whole tabs.
    default property alias contentChildren: inner.data
    property real maxBody: root.cardCap - Style.space(220)
    implicitHeight: Math.min(inner.implicitHeight, Math.max(Style.space(120), maxBody))
    contentWidth: width
    contentHeight: inner.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickableDirection: Flickable.VerticalFlick
    interactive: contentHeight > height
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: inner
      width: parent.width
      spacing: Style.space(6)
    }
  }

  // ---- tabs ----------------------------------------------------------------

  Component {
    id: mainTab
    SheetFlick {
      Row {
        width: parent.width
        spacing: Style.space(4)
        Repeater {
          model: sheet ? sheet.abilities : []
          delegate: StatBox {
            required property var modelData
            label: modelData.abbr
            value: String(modelData.score)
            sub: root.fmtSigned(modelData.mod)
            rollable: true
            onRolled: root.roll(modelData.name + " check", modelData.mod)
          }
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(4)
        StatBox { label: "HP"; value: sheet ? String(sheet.hp.current) + "/" + String(sheet.hp.max) : ""; sub: sheet && sheet.hp.temp > 0 ? "+" + sheet.hp.temp + " temp" : "" }
        StatBox { label: "AC"; value: sheet ? String(sheet.ac) : "" }
        StatBox {
          label: "Init"
          value: sheet ? root.fmtSigned(sheet.initiative) : ""
          rollable: sheet !== null
          onRolled: if (sheet) root.roll("Initiative", sheet.initiative)
        }
        StatBox { label: "Prof"; value: sheet ? root.fmtSigned(sheet.profBonus) : "" }
        StatBox { label: "Speed"; value: sheet ? String(sheet.speed).replace(" ft", "") : ""; sub: "ft" }
        StatBox { label: "Perc"; value: sheet ? String(sheet.passivePerception) : ""; sub: "passive" }
      }

      PanelSeparator { foreground: root.foreground }

      Column {
        width: parent.width
        spacing: Style.space(2)
        PanelSectionHeader {
          text: "Saving throws"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        Text {
          width: parent.width
          wrapMode: Text.Wrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          text: {
            if (!sheet) return ""
            var parts = []
            for (var i = 0; i < sheet.abilities.length; i++) {
              var a = sheet.abilities[i]
              parts.push(a.abbr + " " + root.fmtSigned(a.save) + (a.saveProf ? " ●" : ""))
            }
            return parts.join("   ")
          }
        }
      }

      // ---- attacks: click rolls the attack, the damage chip rolls damage ----
      Column {
        width: parent.width
        spacing: Style.space(2)
        visible: sheet && sheet.attacks && sheet.attacks.length > 0

        PanelSectionHeader {
          text: "Attacks"
          foreground: root.foreground
          fontFamily: root.fontFamily
        }
        Repeater {
          model: sheet && sheet.attacks ? sheet.attacks : []
          delegate: Item {
            id: attackRow
            required property var modelData
            width: parent.width
            implicitHeight: attackName.implicitHeight + Style.space(2)

            HoverHandler { id: attackHover; cursorShape: Qt.PointingHandCursor }
            // MouseArea, not TapHandler: a child MouseArea accepts the press, so
            // clicking the damage chip does NOT also fire the attack roll.
            MouseArea {
              anchors.fill: parent
              onClicked: root.roll(attackRow.modelData.name + " attack", attackRow.modelData.attackMod)
            }

            Text {
              id: attackName
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - attackMeta.implicitWidth - attackDamage.implicitWidth - Style.space(28)
              text: parent.modelData.name
              color: attackHover.hovered ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              id: attackMeta
              anchors.right: attackDamage.left
              anchors.rightMargin: Style.space(12)
              anchors.verticalCenter: parent.verticalCenter
              text: root.fmtSigned(parent.modelData.attackMod) + " to hit"
                    + (parent.modelData.properties ? " · " + parent.modelData.properties : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              id: attackDamage
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              visible: parent.modelData.damage !== ""
              text: {
                var b = attackRow.modelData.damageBonus
                return attackRow.modelData.damage + (b === 0 ? "" : (b > 0 ? "+" + b : "−" + Math.abs(b)))
              }
              color: damageHover.hovered ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              HoverHandler { id: damageHover; cursorShape: Qt.PointingHandCursor }
              MouseArea {
                anchors.fill: parent
                onClicked: root.rollDamage(attackRow.modelData.name + " damage",
                                           attackRow.modelData.damage, attackRow.modelData.damageBonus)
              }
              PanelToolTip { visible: damageHover.hovered; text: "Roll damage (" + attackRow.modelData.damageType + ")"; fontFamily: root.fontFamily }
            }
          }
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(1)
        InfoRow { label: "Hit dice"; value: sheet ? String(sheet.hitDice) : "" }
        InfoRow { label: "Level"; value: sheet ? String(sheet.level) + "  (" + sheet.xp + " XP)" : "" }
        InfoRow { label: "Background"; value: sheet ? String(sheet.background) : "" }
        InfoRow { label: "Alignment"; value: sheet ? String(sheet.alignment) : "" }
        InfoRow { visible: sheet && sheet.inspiration; label: "Inspiration"; value: "★ yes" }
        InfoRow { visible: sheet && sheet.conditions.length > 0; label: "Conditions"; value: sheet ? sheet.conditions.join(", ") : "" }
      }
    }
  }

  Component {
    id: skillsTab
    SheetFlick {
      Repeater {
        model: sheet ? sheet.skills : []
        delegate: Item {
          required property var modelData
          width: parent.width
          implicitHeight: skillName.implicitHeight + Style.space(2)

          HoverHandler { id: skillHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.roll(parent.modelData.name, parent.modelData.mod) }

          Text {
            id: skillName
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: (parent.modelData.prof === 2 ? "◆ " : parent.modelData.prof === 1 ? "● " : "○ ") + parent.modelData.name
            color: skillHover.hovered ? root.foreground
                 : (parent.modelData.prof > 0 ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
          Text {
            anchors.right: skillMod.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.ability
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            id: skillMod
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: root.fmtSigned(parent.modelData.mod)
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: parent.modelData.prof > 0
          }
        }
      }
    }
  }

  Component {
    id: spellsTab
    SheetFlick {
      // Slots + casting stats.
      Row {
        width: parent.width
        spacing: Style.space(6)
        visible: sheet && (sheet.spellSlots.length > 0 || sheet.spellcasting.length > 0)
        Repeater {
          model: sheet ? sheet.spellSlots : []
          delegate: StatBox {
            required property var modelData
            label: (modelData.pact ? "Pact " : "Lvl ") + modelData.level
            value: String(modelData.max - modelData.used) + "/" + String(modelData.max)
            sub: modelData.used > 0 ? modelData.used + " used" : "slots"
          }
        }
      }

      // Rests write back to D&D Beyond server-side; per-slot increments are
      // dead upstream (v5 write API 404s), so rests are the only write path.
      Row {
        width: parent.width
        spacing: Style.space(14)
        visible: sheet && sheet.spellSlots.length > 0

        Text {
          text: "Rest:"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
        Text {
          text: root.restArm === "short" ? "short rest?" : "short rest"
          color: root.restArm === "short" ? Color.accent
               : (shortRestHover.hovered ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          HoverHandler { id: shortRestHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.requestRest("short") }
          PanelToolTip { visible: shortRestHover.hovered; text: "Restores pact magic and short-rest abilities"; fontFamily: root.fontFamily }
        }
        Text {
          text: root.restArm === "long" ? "long rest?" : "long rest"
          color: root.restArm === "long" ? root.urgent
               : (longRestHover.hovered ? root.foreground : root.dim)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
          HoverHandler { id: longRestHover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: root.requestRest("long") }
          PanelToolTip { visible: longRestHover.hovered; text: "Restores HP, all slots, hit dice, death saves"; fontFamily: root.fontFamily }
        }
        Text {
          visible: ddb.resting
          text: "resting…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          anchors.verticalCenter: parent.verticalCenter
        }
      }
      Repeater {
        model: sheet ? sheet.spellcasting : []
        delegate: InfoRow {
          required property var modelData
          label: modelData.class + " spellcasting (" + modelData.ability + ")"
          value: "DC " + modelData.dc + " · attack " + root.fmtSigned(modelData.attack)
        }
      }

      Text {
        visible: !sheet || sheet.spells.length === 0
        width: parent.width
        text: "No spells — this character is not a spellcaster."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Repeater {
        model: root.spellRows()
        delegate: Item {
          required property var modelData
          readonly property bool expanded: !modelData.header
                                           && modelData.spell.name === root.expandedSpell
          width: parent.width
          implicitHeight: modelData.header ? spellHeader.implicitHeight + Style.space(4)
                                           : spellName.implicitHeight + Style.space(2)
                                             + (expanded ? spellDetail.implicitHeight + Style.space(6) : 0)

          HoverHandler { id: spellHover; enabled: !modelData.header; cursorShape: Qt.PointingHandCursor }
          // MouseArea so roll chips inside the expanded detail swallow their
          // own clicks instead of also toggling the row.
          MouseArea {
            anchors.fill: parent
            enabled: !modelData.header
            onClicked: root.expandedSpell = parent.expanded ? "" : parent.modelData.spell.name
          }

          PanelSectionHeader {
            id: spellHeader
            visible: parent.modelData.header
            text: parent.modelData.header ? parent.modelData.label : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            id: spellName
            visible: !parent.modelData.header
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            width: parent.width - spellMeta.implicitWidth - Style.space(16)
            text: parent.modelData.header ? "" : (parent.expanded ? "▾ " : "▸ ")
                  + parent.modelData.spell.name
                  + (parent.modelData.spell.ritual ? " Ⓡ" : "")
                  + (parent.modelData.spell.concentration ? " ©" : "")
            color: parent.expanded ? root.foreground : (spellHover.hovered ? root.foreground : root.dim)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            id: spellMeta
            visible: !parent.modelData.header
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            text: {
              if (parent.modelData.header) return ""
              var s = parent.modelData.spell
              var parts = []
              if (s.castingTime) parts.push(s.castingTime)
              if (s.range) parts.push(s.range)
              if (s.components) parts.push(s.components)
              return parts.join(" · ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          // Expanded detail: mechanics line, then the full description.
          Column {
            id: spellDetail
            visible: parent.expanded
            anchors.top: spellName.bottom
            anchors.topMargin: Style.space(3)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(4)
            spacing: Style.space(3)

            property var spell: parent.modelData && !parent.modelData.header ? parent.modelData.spell : null

            // Attack-roll spells get a clickable roll line.
            Text {
              visible: spellDetail.spell && spellDetail.spell.attackBonus !== null
                       && spellDetail.spell.attackBonus !== undefined
              text: "󱅕 roll attack " + root.fmtSigned(spellDetail.spell ? spellDetail.spell.attackBonus : 0)
              color: spellAttackHover.hovered ? Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              HoverHandler { id: spellAttackHover; cursorShape: Qt.PointingHandCursor }
              MouseArea {
                anchors.fill: parent
                onClicked: root.roll(spellDetail.spell.name, spellDetail.spell.attackBonus)
              }
            }

            // Damage chips: one per damage entry (e.g. Witch Bolt 2d12 + 1d12
            // ongoing). No ability bonus — spell damage rarely adds one.
            Row {
              visible: spellDetail.spell && spellDetail.spell.damage
                       && spellDetail.spell.damage.length > 0
              spacing: Style.space(12)
              Repeater {
                model: (spellDetail.spell && spellDetail.spell.damage) ? spellDetail.spell.damage : []
                delegate: Text {
                  required property var modelData
                  text: "󱅕 " + modelData.dice + " " + modelData.type
                  color: spellDamageHover.hovered ? Color.accent : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  HoverHandler { id: spellDamageHover; cursorShape: Qt.PointingHandCursor }
                  MouseArea {
                    anchors.fill: parent
                    onClicked: root.rollDamage(spellDetail.spell.name + " damage", modelData.dice, 0)
                  }
                }
              }
            }
            Text {
              visible: text !== ""
              width: parent.width
              wrapMode: Text.Wrap
              text: {
                var s = spellDetail.spell
                if (!s) return ""
                var parts = []
                if (s.school) parts.push(s.school)
                if (s.duration) parts.push(s.duration)
                if (s.attackSave) parts.push(s.attackSave)
                if (s.material) parts.push("Material: " + s.material)
                return parts.join(" · ")
              }
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.italic: true
            }
            Text {
              visible: text !== ""
              width: parent.width
              wrapMode: Text.Wrap
              text: spellDetail.spell ? String(spellDetail.spell.description || "") : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
            Text {
              visible: text !== ""
              width: parent.width
              wrapMode: Text.Wrap
              text: spellDetail.spell && spellDetail.spell.atHigherLevels
                    ? "At higher levels: " + spellDetail.spell.atHigherLevels : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }

  Component {
    id: featuresTab
    SheetFlick {
      Text {
        visible: !sheet || sheet.features.length === 0
        width: parent.width
        text: "No features found."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: sheet ? sheet.features : []
        delegate: Column {
          required property var modelData
          width: parent.width
          spacing: Style.space(1)

          RowLayout {
            width: parent.width
            Text {
              Layout.fillWidth: true
              text: parent.parent.modelData.name
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              text: parent.parent.modelData.source
                    + (parent.parent.modelData.level > 0 ? " · lvl " + parent.parent.modelData.level : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          Text {
            visible: parent.modelData.description !== ""
            width: parent.width
            text: parent.modelData.description
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }

  Component {
    id: inventoryTab
    SheetFlick {
      // Currency chips.
      Row {
        width: parent.width
        spacing: Style.space(14)
        visible: sheet !== null
        Repeater {
          model: sheet ? ["pp", "gp", "ep", "sp", "cp"] : []
          delegate: Text {
            required property string modelData
            visible: sheet && sheet.currency[modelData] > 0
            text: sheet ? sheet.currency[modelData] + " " + modelData : ""
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }
        }
      }

      PanelSeparator { foreground: root.foreground }

      Text {
        visible: !sheet || sheet.inventory.length === 0
        width: parent.width
        text: "Inventory is empty."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Repeater {
        model: sheet ? sheet.inventory : []
        delegate: Item {
          required property var modelData
          width: parent.width
          implicitHeight: itemName.implicitHeight + Style.space(2)

          Text {
            id: itemName
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - itemMeta.implicitWidth - Style.space(16)
            text: (parent.modelData.equipped ? "⚔ " : "  ") + parent.modelData.name
                  + (parent.modelData.quantity > 1 ? " ×" + parent.modelData.quantity : "")
                  + (parent.modelData.attuned ? " ✦" : "")
            color: parent.modelData.equipped ? root.foreground : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            id: itemMeta
            anchors.right: parent.right
            anchors.rightMargin: Style.space(4)
            anchors.verticalCenter: parent.verticalCenter
            text: parent.modelData.type
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  Component {
    id: notesTab
    SheetFlick {
      Text {
        visible: !sheet || !sheet.notes || sheet.notes.length === 0
        width: parent.width
        text: "No notes on this character."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Repeater {
        model: sheet && sheet.notes ? sheet.notes : []
        delegate: Column {
          required property var modelData
          width: parent.width
          spacing: Style.space(2)

          PanelSectionHeader {
            text: parent.modelData.title
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            width: parent.width
            text: parent.modelData.text
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
            bottomPadding: Style.space(6)
          }
        }
      }
    }
  }
}
