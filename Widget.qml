import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "omarchy-googletv"
  ipcTarget: "omarchy.googletv"
  manageIpc: false

  readonly property string homeDir: Quickshell.env("HOME") || "/home/andrew"
  readonly property string dataDir: homeDir + "/.config/omarchy/googletv"
  readonly property string pluginDir: homeDir + "/.config/omarchy/plugins/omarchy-googletv"
  readonly property string pythonBin: dataDir + "/.venv/bin/python"
  readonly property string backendScript: pluginDir + "/backend.py"

  // Views: "remote" | "settings" | "pairing" | "apps_edit"
  property string currentView: "remote"

  // TV State
  property string tvName: "Google TV"
  property string tvIp: ""
  property string tvModel: "Android TV"
  property bool tvPaired: false
  property bool connected: false
  property bool isOn: false
  property var allTvs: ({})
  property var programmableButtons: [
    { "slot": 1, "name": "YouTube", "app": "com.google.android.youtube.tv", "icon": "󰗃" },
    { "slot": 2, "name": "Netflix", "app": "com.netflix.ninja", "icon": "󰝆" },
    { "slot": 3, "name": "Disney+", "app": "com.disney.disneyplus", "icon": "󰵈" },
    { "slot": 4, "name": "Prime", "app": "com.amazon.amazonvideo.livingroom", "icon": "󰢔" }
  ]
  property var commonApps: []
  property var scanResults: []
  property bool isScanning: false
  property bool isPairing: false
  property string pairingError: ""
  property string statusMessage: ""

  // Floating Window state
  property bool isFloating: false
  property bool floatingVisible: false

  // App edit state
  property int selectedSlot: 1
  property string customNameText: ""
  property string customAppText: ""

  // Manual TV add state
  property string manualNameText: ""
  property string manualIpText: ""
  property string manualPortText: "6466"

  // Pairing state
  property string pairingCodeInput: ""

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: {
    refreshStatus()
  }

  onOpenedChanged: {
    if (opened) {
      currentView = "remote"
      refreshStatus()
    }
  }

  onFloatingVisibleChanged: {
    if (floatingVisible) {
      currentView = "remote"
      refreshStatus()
    }
  }

  Timer {
    id: statusTimer
    interval: 4000
    repeat: true
    running: (root.opened || (root.isFloating && root.floatingVisible)) && !root.isPairing
    onTriggered: refreshStatus()
  }

  // --- Process Handlers for Backend CLI ---

  function sendKey(keyName) {
    statusMessage = "Key: " + keyName
    Quickshell.execDetached([root.pythonBin, root.backendScript, "key", keyName])
  }

  function launchApp(appId) {
    statusMessage = "Launching: " + appId
    Quickshell.execDetached([root.pythonBin, root.backendScript, "launch", appId])
  }

  function sendText(textStr) {
    if (!textStr || textStr.trim().length === 0) return
    statusMessage = "Text sent: " + textStr
    Quickshell.execDetached([root.pythonBin, root.backendScript, "text", textStr.trim()])
  }

  function refreshStatus() {
    if (!statusProc.running) statusProc.running = true
  }

  Process {
    id: statusProc
    running: false
    command: [root.pythonBin, root.backendScript, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data && data.ok) {
            root.connected = !!data.connected
            root.isOn = !!data.is_on
            if (data.active_tv) {
              root.tvName = data.active_tv.name || "Google TV"
              root.tvIp = data.active_tv.ip || ""
              root.tvModel = data.active_tv.model || "Android TV"
              root.tvPaired = !!data.active_tv.paired
            } else {
              root.tvPaired = false
            }
            if (data.config) {
              if (data.config.tvs) root.allTvs = data.config.tvs
              if (data.config.programmable_buttons) root.programmableButtons = data.config.programmable_buttons
            }
            if (data.common_apps && data.common_apps.length > 0) {
              root.commonApps = data.common_apps
            }
          }
        } catch (e) {}
      }
    }
  }

  function scanNetwork() {
    root.isScanning = true
    scanProc.running = true
  }

  Process {
    id: scanProc
    running: false
    command: [root.pythonBin, root.backendScript, "scan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.isScanning = false
        try {
          var data = JSON.parse(text)
          if (data && data.ok && data.devices) {
            root.scanResults = data.devices
          }
        } catch (e) {}
      }
    }
  }

  function startPairing(targetIp) {
    root.pairingError = ""
    root.pairingCodeInput = ""
    root.isPairing = true
    root.currentView = "pairing"
    pairStartProc.command = [root.pythonBin, root.backendScript, "pair-start", targetIp || root.tvIp]
    pairStartProc.running = true
  }

  Process {
    id: pairStartProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (!data.ok) {
            root.pairingError = data.error || "Failed to start pairing"
          }
        } catch (e) {
          root.pairingError = "Error contacting TV"
        }
      }
    }
  }

  function finishPairing(code) {
    if (!code || code.length === 0) {
      root.pairingError = "Please enter the code shown on TV"
      return
    }
    root.pairingError = ""
    pairFinishProc.command = [root.pythonBin, root.backendScript, "pair-finish", code]
    pairFinishProc.running = true
  }

  Process {
    id: pairFinishProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          if (data.ok) {
            root.isPairing = false
            root.currentView = "remote"
            root.tvPaired = true
            root.refreshStatus()
          } else {
            root.pairingError = data.error || "Invalid pairing code"
          }
        } catch (e) {
          root.pairingError = "Pairing failed"
        }
      }
    }
  }

  function cancelPairing() {
    root.isPairing = false
    root.currentView = "remote"
    Quickshell.execDetached([root.pythonBin, root.backendScript, "pair-cancel"])
  }

  function addTvManual() {
    if (!manualIpText || manualIpText.trim().length === 0) return
    var name = manualNameText.trim() || ("Google TV (" + manualIpText.trim() + ")")
    var port = manualPortText.trim() || "6466"
    addTvProc.command = [root.pythonBin, root.backendScript, "add-tv", manualIpText.trim(), name, port]
    addTvProc.running = true
    manualNameText = ""
    manualIpText = ""
  }

  Process {
    id: addTvProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.refreshStatus()
      }
    }
  }

  function selectTv(ip, name, port) {
    var cmd = [root.pythonBin, root.backendScript, "select-tv", ip]
    if (name) cmd.push(name)
    if (port) cmd.push(String(port))
    selectTvProc.command = cmd
    selectTvProc.running = true
  }

  Process {
    id: selectTvProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.refreshStatus()
      }
    }
  }

  function setButton(slot, name, app, icon) {
    setButtonProc.command = [root.pythonBin, root.backendScript, "set-button", String(slot), name, app, icon || "󰗃"]
    setButtonProc.running = true
  }

  Process {
    id: setButtonProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.refreshStatus()
      }
    }
  }

  // --- IPC Commands ---

  IpcHandler {
    target: "omarchy.googletv"

    function open(): void {
      if (root.isFloating) {
        root.floatingVisible = true
        if (floatingWin) floatingWin.visible = true
      } else {
        root.open()
      }
    }

    function close(): void {
      if (root.isFloating) {
        root.floatingVisible = false
        if (floatingWin) floatingWin.visible = false
      } else {
        root.close()
      }
    }

    function show(): void { open() }
    function hide(): void { close() }

    function scan(): void {
      root.scanNetwork()
    }

    function refresh(): void {
      root.refreshStatus()
    }

    function key(k: string): void {
      root.sendKey(k)
    }

    function toggle(): void {
      if (root.isFloating) {
        root.floatingVisible = !root.floatingVisible
        if (floatingWin) floatingWin.visible = root.floatingVisible
      } else {
        root.toggle()
      }
    }

    function toggleFloat(): void {
      if (root.isFloating) {
        root.isFloating = false
        root.floatingVisible = false
        if (floatingWin) floatingWin.visible = false
        root.open()
      } else {
        root.isFloating = true
        root.floatingVisible = true
        root.close()
        if (floatingWin) floatingWin.visible = true
      }
    }

    function float(): void {
      root.isFloating = true
      root.floatingVisible = true
      root.close()
      if (floatingWin) floatingWin.visible = true
    }

    function dock(): void {
      root.isFloating = false
      root.floatingVisible = false
      if (floatingWin) floatingWin.visible = false
      root.open()
    }
  }

  // --- Bar Button Item ---

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰟴"
    active: root.connected || root.tvPaired
    dimmed: !(root.connected || root.tvPaired)
    tooltipText: root.tvName ? (root.tvName + (root.connected ? " (Connected)" : (root.tvPaired ? " (Standby)" : " (Unpaired)"))) : "Google TV Remote"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        root.currentView = "settings"
        if (root.isFloating) {
          root.floatingVisible = true
          floatingWin.visible = true
        } else {
          root.open()
        }
      } else {
        if (root.isFloating) {
          root.floatingVisible = !root.floatingVisible
          floatingWin.visible = root.floatingVisible
        } else {
          root.toggle()
        }
      }
    }
  }

  // --- Popup Remote Panel (Docked to Bar) ---

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened && !root.isFloating
    focusTarget: dockedCard ? dockedCard.keyCatcherItem : null
    contentWidth: panel.fittedContentWidth(Style.space(330))
    contentHeight: panel.fittedContentHeight(dockedCard ? (dockedCard.contentHeight + Style.space(16)) : Style.space(580), Style.space(640))

    RemoteCard {
      id: dockedCard
      anchors.fill: parent
      rootWidget: root
      isFloating: false
      onCloseRequested: root.close()
      onToggleFloatingRequested: {
        root.isFloating = true
        root.floatingVisible = true
        root.close()
        floatingWin.visible = true
      }
    }
  }

  // --- Detached Floating Remote Window ---

  FloatingWindow {
    id: floatingWin
    title: "Google TV Remote"
    visible: root.isFloating && root.floatingVisible
    color: Color.popups.background
    implicitWidth: Style.space(330)
    implicitHeight: Math.min(Style.space(640), floatingCard ? (floatingCard.contentHeight + Style.space(24)) : Style.space(580))
    minimumSize: Qt.size(Style.space(280), Style.space(400))

    onVisibleChanged: {
      if (!visible) {
        root.floatingVisible = false
      } else {
        Qt.callLater(function() {
          if (floatingCard && floatingCard.keyCatcherItem) {
            floatingCard.keyCatcherItem.forceActiveFocus()
          }
        })
      }
    }

    RemoteCard {
      id: floatingCard
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      rootWidget: root
      isFloating: true
      windowRef: floatingWin
      onCloseRequested: {
        root.floatingVisible = false
        floatingWin.visible = false
      }
      onToggleFloatingRequested: {
        root.isFloating = false
        root.floatingVisible = false
        floatingWin.visible = false
        root.open()
      }
    }
  }
}
