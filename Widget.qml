import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

// aura.call — a bar icon that opens a small collapsible panel: live/idle
// status, Start Call, a native-QML transcript + typed-input box, and the
// same model/effort/voice/STT/volume/hang-up controls the full Backtalk-UI
// page has (all of which turned out to just be canned phrases posted
// through the same /api/input channel the text box uses -- see
// ~/Jarvis/04 - Resources/Aura Quickshell Widgets.md). No bridge process:
// backtalk's own launcher.py/transcript_server.py already answer
// idle-vs-live and carry the transcript on port 8793.
Panel {
  id: root
  moduleName: "aura.call"
  ipcTarget: "aura.call"
  manageIpc: false

  readonly property string statusUrl: "http://127.0.0.1:8793/api/transcript"
  readonly property string startUrl: "http://127.0.0.1:8793/start"
  readonly property string inputUrl: "http://127.0.0.1:8793/api/input"
  readonly property string openScript: String(Qt.resolvedUrl("open-or-focus.sh")).replace(/^file:\/\//, "")

  readonly property color foreground: bar ? bar.foreground : Color.foreground

  property bool live: false
  property bool starting: false
  property bool launchFailed: false
  property bool settingsVisible: false

  // Live conversation state -- kept up to date even while the panel is
  // closed (the poll below always runs), so opening the panel never
  // shows an empty flash while the first fetch completes.
  property var liveState: ({})
  property var events: []
  property int sinceCursor: 0
  property string bootId: ""

  implicitWidth: Style.bar.iconSlot
  implicitHeight: Style.bar.iconSlot

  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function stateColor() {
    if (root.launchFailed) return bar ? bar.urgent : Color.urgent
    if (root.live) return Color.accent
    return root.foreground
  }

  function tooltip() {
    if (root.launchFailed) return "Aura — launch failed, click to retry"
    if (root.live) return "Aura — call live, click to open"
    if (root.starting) return "Aura — starting…"
    return "Aura — click to open"
  }

  function fetchJson(url, onSuccess, onError, method, body) {
    var req = new XMLHttpRequest()
    var finished = false
    function fail() {
      if (finished) return
      finished = true
      onError()
    }
    req.timeout = 4000
    req.onreadystatechange = function() {
      if (req.readyState !== XMLHttpRequest.DONE || finished) return
      if (req.status < 200 || req.status >= 300) { fail(); return }
      var parsed = ({})
      if (req.responseText) {
        try { parsed = JSON.parse(req.responseText) } catch (e) { fail(); return }
      }
      finished = true
      onSuccess(parsed)
    }
    req.onerror = fail
    req.ontimeout = fail
    try {
      req.open(method || "GET", url)
      if (body !== undefined) req.setRequestHeader("Content-Type", "application/json")
      req.send(body === undefined ? null : body)
    } catch (e) { fail() }
  }

  function poll() {
    var since = root.events.length === 0 ? 0 : root.sinceCursor
    root.fetchJson(root.statusUrl + "?since=" + since, function(resp) {
      if (resp.idle === true) {
        root.live = false
        root.events = []
        root.sinceCursor = 0
        root.bootId = ""
        root.settingsVisible = false
        if (resp.launch_failed === true) {
          root.launchFailed = true
          root.starting = false
        }
        return
      }
      // transcript_server.py is answering instead of launcher.py's idle
      // placeholder -- no "idle" key in its /api/transcript response.
      root.live = true
      root.starting = false
      root.launchFailed = false
      var evs = Array.isArray(resp.events) ? resp.events : []
      if (resp.boot && resp.boot !== root.bootId) {
        // First poll under a new boot id (fresh call, or backtalk
        // restarted underneath us): the ids `since` was relative to no
        // longer exist. Reset and bail this tick -- next tick's poll
        // sees events.length === 0 and re-fetches from since=0 under
        // the new boot id instead of silently missing everything.
        root.bootId = resp.boot
        root.events = []
        root.sinceCursor = 0
      } else if (since === 0) {
        root.events = evs.slice(-60)
        for (var i = 0; i < evs.length; i++) root.sinceCursor = Math.max(root.sinceCursor, Number(evs[i].id || 0))
      } else if (evs.length > 0) {
        root.events = root.events.concat(evs).slice(-60)
        for (var j = 0; j < evs.length; j++) root.sinceCursor = Math.max(root.sinceCursor, Number(evs[j].id || 0))
      }
      if (resp.state) root.liveState = resp.state
    }, function() {
      // Connection refused during the idle<->live port handoff, or the
      // whole chain is down. Momentary by design -- don't flap state.
    })
  }

  function startCall() {
    if (root.live || root.starting) return
    root.launchFailed = false
    root.starting = true
    root.fetchJson(root.startUrl, function() {
      // 202 accepted -- the poll loop picks up the idle->live transition.
    }, function() {
      root.starting = false
      root.launchFailed = true
    }, "POST")
  }

  function postInput(text, onDone) {
    var t = String(text || "").trim()
    if (!t) return
    root.fetchJson(root.inputUrl, function() {
      if (onDone) onDone(true)
    }, function() {
      if (onDone) onDone(false)
    }, "POST", JSON.stringify({ text: t }))
  }

  function setAutoApprove(on) {
    if (on) root.postInput("stop asking for permission", function() { root.postInput("confirm") })
    else root.postInput("start asking again")
  }

  Timer {
    id: pollTimer
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.poll()
  }

  Component.onCompleted: root.poll()

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    dimmed: root.starting
    tooltipText: root.tooltip()
    onPressed: function(buttonCode) { root.toggle() }

    // Plain `text:` centers via OpticalGlyph's own painted-bounds
    // calculation, which sat visibly low for this particular glyph on
    // this font stack -- iconComponent gives direct control over the
    // offset instead. -2 is a first guess (r3pc0n asked for it to sit
    // a bit higher); nudge further if it's still not quite level with
    // the rest of the row.
    hasVisualContent: true
    iconComponent: Component {
      Text {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -2
        text: "☎"
        color: root.stateColor()
        font.pixelSize: Style.bar.iconFont
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: chatInput
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    onOpenChanged: if (panel.open) { volumeSlider.value = Number(root.liveState.volume || 100); root.poll() }

    Flickable {
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentColumn.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(10)

        // ---------- header ----------
        Item {
          width: parent.width
          height: Style.space(20)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.live ? "Aura — live" : (root.starting ? "Aura — starting…" : "Aura")
            color: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(10)

            Text {
              text: root.settingsVisible ? "←" : "☰"
              visible: root.live
              color: root.foreground
              font.pixelSize: Style.font.body
              ToolTip.visible: menuHover.hovered
              ToolTip.text: root.settingsVisible ? "Back to transcript" : "Settings"
              HoverHandler { id: menuHover }
              TapHandler { onTapped: root.settingsVisible = !root.settingsVisible }
            }

            Text {
              text: "↗"
              color: root.foreground
              font.pixelSize: Style.font.body
              ToolTip.visible: openHover.hovered
              ToolTip.text: "Open full page"
              HoverHandler { id: openHover }
              TapHandler { onTapped: if (root.bar) root.bar.run(root.openScript) }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- idle: Start Call ----------
        Column {
          visible: !root.live
          width: parent.width
          spacing: Style.space(8)

          Text {
            visible: root.launchFailed
            width: parent.width
            text: "Launch failed — click to try again"
            color: root.bar ? root.bar.urgent : Color.urgent
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Rectangle {
            width: parent.width
            height: Style.space(34)
            radius: Style.cornerRadius
            color: root.alpha(Color.accent, root.starting ? 0.08 : 0.18)
            border.width: 1
            border.color: root.alpha(Color.accent, 0.4)

            Text {
              anchors.centerIn: parent
              text: root.starting ? "Starting…" : "Start Call"
              color: root.foreground
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.starting
              onClicked: root.startCall()
            }
          }
        }

        // ---------- live: transcript view ----------
        Column {
          visible: root.live && !root.settingsVisible
          width: parent.width
          spacing: Style.space(10)

          // status strip
          Grid {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(8)
            rowSpacing: Style.space(4)

            Repeater {
              model: [
                { label: "Model", value: String(root.liveState.tier || "—") },
                { label: "Effort", value: String(root.liveState.effort || "—") },
                { label: "Voice", value: String(root.liveState.voice_mode || "—") + (root.liveState.voice ? " (" + root.liveState.voice + ")" : "") },
                { label: "Hearing", value: String(root.liveState.stt_mode || "—") },
                { label: "Volume", value: root.liveState.volume !== undefined ? root.liveState.volume + "%" : "—" },
                { label: "Auto-approve", value: root.liveState.auto_approve ? "on" : "off" }
              ]
              delegate: Row {
                required property var modelData
                width: (contentColumn.width - Style.space(8)) / 2
                spacing: Style.space(4)
                Text {
                  text: modelData.label + ":"
                  color: root.alpha(root.foreground, 0.65)
                  font.pixelSize: Style.font.caption
                }
                Text {
                  text: modelData.value
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  elide: Text.ElideRight
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // transcript
          Rectangle {
            width: parent.width
            height: Style.space(180)
            radius: Style.cornerRadius
            color: root.alpha(root.foreground, 0.04)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.12)
            clip: true

            Flickable {
              id: transcriptFlick
              anchors.fill: parent
              anchors.margins: Style.space(6)
              contentWidth: width
              contentHeight: transcriptCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              onContentHeightChanged: contentY = Math.max(0, contentHeight - height)

              Column {
                id: transcriptCol
                width: transcriptFlick.width
                spacing: Style.space(4)

                Text {
                  visible: root.events.length === 0
                  text: "No messages yet."
                  color: root.alpha(root.foreground, 0.5)
                  font.pixelSize: Style.font.caption
                }

                Repeater {
                  model: root.events
                  delegate: Text {
                    required property var modelData
                    width: transcriptCol.width
                    wrapMode: Text.WordWrap
                    text: (modelData.speaker === "you" ? "You: " : "Aura: ") + String(modelData.text || "")
                    color: modelData.speaker === "you" ? Color.accent : root.foreground
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // typed input
          Rectangle {
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: root.alpha(root.foreground, 0.06)
            border.width: 1
            border.color: root.alpha(root.foreground, 0.22)

            TextInput {
              id: chatInput
              anchors.left: parent.left
              anchors.right: sendGlyph.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(4)
              color: root.foreground
              font.pixelSize: Style.font.caption
              clip: true
              selectByMouse: true
              onAccepted: { root.postInput(text); text = "" }
            }

            Text {
              anchors.left: chatInput.left
              anchors.verticalCenter: chatInput.verticalCenter
              visible: !chatInput.text && !chatInput.activeFocus
              text: "Type a message…"
              color: root.alpha(root.foreground, 0.45)
              font.pixelSize: Style.font.caption
            }

            Text {
              id: sendGlyph
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: "→"
              color: root.foreground
              font.pixelSize: Style.font.body
              TapHandler { onTapped: { root.postInput(chatInput.text); chatInput.text = "" } }
            }
          }

        }

        // ---------- live: settings view ----------
        // Every control here just posts the same canned phrase the full
        // transcript page's own settings buttons do -- no separate API.
        Column {
          visible: root.live && root.settingsVisible
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { width: parent.width; text: "MODEL"; foreground: root.foreground }
          Row {
            spacing: Style.space(6)
            ChoiceButton { label: "Fast"; active: root.liveState.tier === "fast"; onActivated: root.postInput("switch to the fast model") }
            ChoiceButton { label: "Deep"; active: root.liveState.tier === "deep"; onActivated: root.postInput("switch to the deep model") }
            ChoiceButton { label: "Cheap"; active: root.liveState.tier === "cheap"; onActivated: root.postInput("switch to the cheap model") }
          }

          PanelSectionHeader { width: parent.width; text: "EFFORT"; foreground: root.foreground }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            ChoiceButton { label: "Low"; active: root.liveState.effort === "low"; onActivated: root.postInput("set effort to low") }
            ChoiceButton { label: "Med"; active: root.liveState.effort === "medium"; onActivated: root.postInput("set effort to medium") }
            ChoiceButton { label: "High"; active: root.liveState.effort === "high"; onActivated: root.postInput("set effort to high") }
            ChoiceButton { label: "XHi"; active: root.liveState.effort === "xhigh"; onActivated: root.postInput("set effort to xhigh") }
            ChoiceButton { label: "Max"; active: root.liveState.effort === "max"; onActivated: root.postInput("set effort to max") }
          }

          PanelSectionHeader { width: parent.width; text: "VOICE ENGINE"; foreground: root.foreground }
          Row {
            spacing: Style.space(6)
            ChoiceButton { label: "Local"; active: root.liveState.voice_mode === "local"; onActivated: root.postInput("switch to local voice") }
            ChoiceButton { label: "Cloud"; active: root.liveState.voice_mode === "cloud"; onActivated: root.postInput("switch to cloud voice") }
          }

          PanelSectionHeader { width: parent.width; text: "SPEECH-TO-TEXT"; foreground: root.foreground }
          Row {
            spacing: Style.space(6)
            ChoiceButton { label: "Local"; active: root.liveState.stt_mode === "local"; onActivated: root.postInput("switch to local hearing") }
            ChoiceButton { label: "Cloud"; active: root.liveState.stt_mode === "cloud"; onActivated: root.postInput("switch to cloud hearing") }
          }

          PanelSectionHeader { width: parent.width; text: "VOLUME"; foreground: root.foreground }
          Row {
            width: parent.width
            spacing: Style.space(8)
            Slider {
              id: volumeSlider
              width: parent.width - Style.space(48)
              from: 0; to: 300; stepSize: 5
              onPressedChanged: if (!pressed) root.postInput("set volume to " + Math.round(value))
            }
            Text {
              text: Math.round(volumeSlider.value) + "%"
              color: root.foreground
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Text {
            width: parent.width
            text: (root.liveState.auto_approve ? "☑ " : "☐ ") + "Auto-approve (stop asking for permission)"
            color: root.foreground
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
            TapHandler { onTapped: root.setAutoApprove(!root.liveState.auto_approve) }
          }

          PanelSeparator { foreground: root.foreground }

          // Deliberately its own full-width button, well clear of the
          // other controls above -- r3pc0n asked for it tucked away so
          // it can't be fat-fingered alongside the settings/open-page
          // navigation icons up in the header.
          Rectangle {
            width: parent.width
            height: Style.space(30)
            radius: Style.cornerRadius
            color: root.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.12)
            border.width: 1
            border.color: root.alpha(root.bar ? root.bar.urgent : Color.urgent, 0.4)

            Text {
              anchors.centerIn: parent
              text: "Hang Up"
              color: root.bar ? root.bar.urgent : Color.urgent
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
            }

            MouseArea {
              anchors.fill: parent
              onClicked: root.postInput("end voice mode")
            }
          }
        }
      }
    }
  }

  // Small reusable pill button for the quick-action rows above.
  component ChoiceButton: Rectangle {
    id: cb
    property string label: ""
    property bool active: false
    signal activated()

    implicitWidth: cbText.implicitWidth + Style.space(16)
    implicitHeight: Style.space(24)
    radius: Style.cornerRadius
    color: cb.active ? root.alpha(Color.accent, 0.22) : root.alpha(root.foreground, 0.06)
    border.width: 1
    border.color: cb.active ? Color.accent : root.alpha(root.foreground, 0.15)

    Text {
      id: cbText
      anchors.centerIn: parent
      text: cb.label
      color: cb.active ? Color.accent : root.foreground
      font.pixelSize: Style.font.caption
      font.bold: cb.active
    }

    MouseArea {
      anchors.fill: parent
      onClicked: cb.activated()
    }
  }
}
