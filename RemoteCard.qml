import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Item {
  id: cardRoot

  required property var rootWidget
  property bool isFloating: false
  property var windowRef: null

  signal closeRequested()
  signal toggleFloatingRequested()

  readonly property int contentHeight: flick.contentHeight
  readonly property Item keyCatcherItem: keyCatcher

  PanelKeyCatcher {
    id: keyCatcher
    anchors.fill: parent
    blocked: rootWidget.currentView !== "remote" || (sendTextInput && sendTextInput.activeFocus)
    onMoveRequested: function(dx, dy) {
      if (dx === 1) rootWidget.sendKey("DPAD_RIGHT")
      else if (dx === -1) rootWidget.sendKey("DPAD_LEFT")
      else if (dy === 1) rootWidget.sendKey("DPAD_DOWN")
      else if (dy === -1) rootWidget.sendKey("DPAD_UP")
    }
    onActivateRequested: rootWidget.sendKey("DPAD_CENTER")
    onReturnRequested: rootWidget.sendKey("DPAD_CENTER")
    onCloseRequested: cardRoot.closeRequested()
    onTextKey: function(t) {
      if (t === "h" || t === "H") rootWidget.sendKey("HOME")
      else if (t === "b" || t === "B") rootWidget.sendKey("BACK")
      else if (t === "p" || t === "P") rootWidget.sendKey("MEDIA_PLAY_PAUSE")
      else if (t === "+" || t === "=") rootWidget.sendKey("VOLUME_UP")
      else if (t === "-") rootWidget.sendKey("VOLUME_DOWN")
      else if (t === "m" || t === "M") rootWidget.sendKey("VOLUME_MUTE")
    }

    Flickable {
      id: flick
      anchors.fill: parent
      contentWidth: width
      contentHeight: contentCol.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: contentCol
        width: flick.width
        spacing: Style.space(12)

        // ==========================================
        // VIEW 1: REMOTE CONTROL (COMPACT)
        // ==========================================
        Column {
          width: parent.width
          spacing: Style.space(6)
          visible: rootWidget.currentView === "remote"
          height: visible ? implicitHeight : 0
          clip: true

          // Compact Header Bar
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Rectangle {
              width: Style.space(8)
              height: Style.space(8)
              radius: width / 2
              color: rootWidget.connected ? Color.accent : (rootWidget.tvPaired ? "#e5c07b" : Color.urgent)
              Layout.alignment: Qt.AlignVCenter
            }

            // Draggable Title Area
            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: titleCol.implicitHeight
              Layout.alignment: Qt.AlignVCenter

              Column {
                id: titleCol
                anchors.fill: parent
                spacing: 0

                RowLayout {
                  spacing: Style.space(4)
                  width: parent.width

                  Text {
                    text: rootWidget.tvName
                    color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
                    font.family: rootWidget.bar ? rootWidget.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    visible: cardRoot.isFloating
                    text: "󰁌"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.6)
                    Layout.alignment: Qt.AlignVCenter
                  }
                }

                Text {
                  text: rootWidget.tvIp ? (rootWidget.tvIp + (rootWidget.connected ? " • Connected" : (rootWidget.tvPaired ? " • Standby" : " • Unpaired"))) : "No TV selected"
                  color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.4)
                  font.family: rootWidget.bar ? rootWidget.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                  width: parent.width
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: cardRoot.isFloating
                cursorShape: cardRoot.isFloating ? Qt.SizeAllCursor : Qt.ArrowCursor
                onPressed: {
                  if (cardRoot.windowRef && typeof cardRoot.windowRef.startSystemMove === "function") {
                    cardRoot.windowRef.startSystemMove()
                  }
                }
              }
            }

            // Toggle Docked / Floating Button
            Button {
              iconText: cardRoot.isFloating ? "󰖳" : "󰖲"
              tooltipText: cardRoot.isFloating ? "Dock to bar" : "Float remote (detach)"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.toggleFloatingRequested()
            }

            // Settings Button
            Button {
              iconText: "󰒓"
              tooltipText: "Settings & TVs"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: rootWidget.currentView = "settings"
            }

            // Power Button
            Button {
              iconText: "󰐥"
              tooltipText: "Power Toggle"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              accent: Color.urgent
              bordered: true
              onClicked: rootWidget.sendKey("POWER")
            }

            // Close Button (visible when floating)
            Button {
              visible: cardRoot.isFloating
              iconText: "󰅖"
              tooltipText: "Close"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.closeRequested()
            }
          }

          // Compact Unpaired Notice
          Rectangle {
            width: parent.width
            height: Style.space(24)
            visible: !rootWidget.tvPaired && rootWidget.tvIp.length > 0
            radius: Style.cornerRadius
            color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)
            border.color: Color.urgent
            border.width: 1

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(4)
              spacing: Style.space(4)

              Text {
                text: "󰀦 TV Needs Pairing"
                color: Color.urgent
                font.bold: true
                font.pixelSize: Style.font.caption
                Layout.fillWidth: true
              }

              Button {
                text: "Pair"
                fontSize: Style.font.caption
                verticalPadding: 0
                horizontalPadding: Style.space(6)
                accent: Color.accent
                bordered: true
                onClicked: rootWidget.startPairing(rootWidget.tvIp)
              }
            }
          }

          // Volume & Mute Row
          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              iconText: "󰝟"
              tooltipText: "Mute"
              fontSize: Style.font.caption
              Layout.preferredWidth: Style.space(48)
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("VOLUME_MUTE")
            }

            Button {
              iconText: "󰝝"
              text: "Vol -"
              tooltipText: "Volume Down (-)"
              fontSize: Style.font.caption
              Layout.fillWidth: true
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("VOLUME_DOWN")
            }

            Button {
              iconText: "󰝝"
              text: "Vol +"
              tooltipText: "Volume Up (+)"
              fontSize: Style.font.caption
              Layout.fillWidth: true
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("VOLUME_UP")
            }
          }

          // Compact D-PAD
          Item {
            width: parent.width
            height: Style.space(120)

            Rectangle {
              id: dpadBase
              width: Style.space(120)
              height: Style.space(120)
              radius: width / 2
              anchors.centerIn: parent
              color: Style.controlFill(false, false, (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, Color.accent)
              border.color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.7)
              border.width: 1

              // UP
              Button {
                anchors.top: parent.top
                anchors.topMargin: Style.space(2)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(44)
                height: Style.space(34)
                iconText: "󰁝"
                tooltipText: "Up (Arrow Up)"
                fontSize: Style.font.body
                verticalPadding: 0
                bordered: false
                onClicked: rootWidget.sendKey("DPAD_UP")
              }

              // LEFT
              Button {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                height: Style.space(44)
                iconText: "󰁍"
                tooltipText: "Left (Arrow Left)"
                fontSize: Style.font.body
                horizontalPadding: 0
                bordered: false
                onClicked: rootWidget.sendKey("DPAD_LEFT")
              }

              // OK / SELECT
              Button {
                anchors.centerIn: parent
                width: Style.space(40)
                height: Style.space(40)
                text: "OK"
                tooltipText: "OK / Select (Enter)"
                fontSize: Style.font.caption
                accent: Color.accent
                bordered: true
                onClicked: rootWidget.sendKey("DPAD_CENTER")
              }

              // RIGHT
              Button {
                anchors.right: parent.right
                anchors.rightMargin: Style.space(2)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(34)
                height: Style.space(44)
                iconText: "󰁔"
                tooltipText: "Right (Arrow Right)"
                fontSize: Style.font.body
                horizontalPadding: 0
                bordered: false
                onClicked: rootWidget.sendKey("DPAD_RIGHT")
              }

              // DOWN
              Button {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Style.space(2)
                anchors.horizontalCenter: parent.horizontalCenter
                width: Style.space(44)
                height: Style.space(34)
                iconText: "󰁅"
                tooltipText: "Down (Arrow Down)"
                fontSize: Style.font.body
                verticalPadding: 0
                bordered: false
                onClicked: rootWidget.sendKey("DPAD_DOWN")
              }
            }
          }

          // Navigation Row (Back, Home, Play)
          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            Button {
              iconText: "󰁮"
              text: "Back"
              tooltipText: "Back (Backspace / b)"
              fontSize: Style.font.caption
              Layout.fillWidth: true
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("BACK")
            }

            Button {
              iconText: "󰋜"
              text: "Home"
              tooltipText: "Home (Home / h)"
              fontSize: Style.font.caption
              Layout.fillWidth: true
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("HOME")
            }

            Button {
              iconText: "󰐊"
              text: "Play"
              tooltipText: "Play/Pause (Space / p)"
              fontSize: Style.font.caption
              Layout.fillWidth: true
              verticalPadding: Style.space(3)
              bordered: true
              onClicked: rootWidget.sendKey("MEDIA_PLAY_PAUSE")
            }
          }

          // Send Text Input Row
          RowLayout {
            width: parent.width
            spacing: Style.space(4)

            TextField {
              id: sendTextInput
              Layout.fillWidth: true
              placeholderText: "Send text to TV..."
              font.pixelSize: Style.font.caption
              verticalPadding: Style.space(2)
              onAccepted: {
                if (text.trim().length > 0) {
                  rootWidget.sendText(text.trim())
                  text = ""
                }
              }
            }

            Button {
              text: "Send"
              iconText: "󰒭"
              tooltipText: "Send text to TV"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(8)
              accent: Color.accent
              bordered: true
              onClicked: {
                if (sendTextInput.text.trim().length > 0) {
                  rootWidget.sendText(sendTextInput.text.trim())
                  sendTextInput.text = ""
                }
              }
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Programmable Buttons Section Header
          RowLayout {
            width: parent.width

            PanelSectionHeader {
              text: "QUICK APPS"
              foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
              fontSize: Style.font.caption
              Layout.fillWidth: true
            }

            Button {
              text: "Edit"
              iconText: "󰏫"
              fontSize: Style.font.caption
              verticalPadding: Style.space(1)
              horizontalPadding: Style.space(5)
              bordered: true
              onClicked: rootWidget.currentView = "apps_edit"
            }
          }

          // 4 Programmable Buttons Grid (2x2)
          Grid {
            width: parent.width
            columns: 2
            spacing: Style.space(5)

            Repeater {
              model: rootWidget.programmableButtons

              Button {
                width: (flick.width - Style.space(5)) / 2
                text: modelData.name || ("Button " + modelData.slot)
                iconText: modelData.icon || "󰗃"
                fontSize: Style.font.caption
                verticalPadding: Style.space(3)
                bordered: true
                onClicked: rootWidget.launchApp(modelData.app)
              }
            }
          }
        }

        // ==========================================
        // VIEW 2: SETTINGS (TV Selection & Discovery)
        // ==========================================
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: rootWidget.currentView === "settings"

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              iconText: "󰁮"
              text: "Remote"
              bordered: true
              onClicked: rootWidget.currentView = "remote"
            }

            Text {
              text: "TV Settings"
              color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
              font.family: rootWidget.bar ? rootWidget.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              Layout.fillWidth: true
            }

            Button {
              iconText: cardRoot.isFloating ? "󰖳" : "󰖲"
              tooltipText: cardRoot.isFloating ? "Dock to bar" : "Float remote (detach)"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.toggleFloatingRequested()
            }

            Button {
              visible: cardRoot.isFloating
              iconText: "󰅖"
              tooltipText: "Close"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.closeRequested()
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Active TV Details
          PanelSectionHeader {
            text: "CURRENT ACTIVE TV"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          Rectangle {
            width: parent.width
            implicitHeight: activeTvCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, Color.accent)
            border.color: rootWidget.tvPaired ? Color.accent : Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.6)
            border.width: 1

            Column {
              id: activeTvCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)

              RowLayout {
                width: parent.width

                Column {
                  Layout.fillWidth: true
                  spacing: 2
                  Text {
                    text: rootWidget.tvName
                    color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
                    font.bold: true
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    text: rootWidget.tvIp ? (rootWidget.tvIp + " (" + rootWidget.tvModel + ")") : "No TV configured"
                    color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.4)
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  text: rootWidget.tvPaired ? "󰄬 Paired" : "󰀦 Unpaired"
                  color: rootWidget.tvPaired ? Color.accent : Color.urgent
                  font.bold: true
                  font.pixelSize: Style.font.caption
                }
              }

              Button {
                width: parent.width
                visible: !rootWidget.tvPaired && rootWidget.tvIp.length > 0
                text: "Pair with this TV"
                accent: Color.accent
                bordered: true
                onClicked: rootWidget.startPairing(rootWidget.tvIp)
              }
            }
          }

          // Configured TVs switcher
          PanelSectionHeader {
            text: "KNOWN TVS"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
            visible: Object.keys(rootWidget.allTvs).length > 1
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: Object.keys(rootWidget.allTvs).length > 1

            Repeater {
              model: Object.keys(rootWidget.allTvs)

              RowLayout {
                width: parent.width
                spacing: Style.space(6)

                Button {
                  Layout.fillWidth: true
                  text: (rootWidget.allTvs[modelData].name || modelData) + (modelData === rootWidget.tvIp ? " (Active)" : "")
                  selected: modelData === rootWidget.tvIp
                  bordered: true
                  onClicked: rootWidget.selectTv(modelData)
                }

                Button {
                  visible: !rootWidget.allTvs[modelData].paired
                  text: "Pair"
                  accent: Color.accent
                  bordered: true
                  fontSize: Style.font.caption
                  verticalPadding: Style.space(2)
                  horizontalPadding: Style.space(8)
                  onClicked: {
                    rootWidget.selectTv(modelData)
                    rootWidget.startPairing(modelData)
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Network Discovery Section
          PanelSectionHeader {
            text: "SEARCH NETWORK FOR CONNECTED DEVICES"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          Button {
            width: parent.width
            text: rootWidget.isScanning ? "Scanning Network (mDNS)..." : "Scan Network for Google TVs"
            iconText: "󰍉"
            bordered: true
            onClicked: rootWidget.scanNetwork()
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: rootWidget.scanResults.length > 0

            Text {
              text: "Discovered Devices:"
              color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
              font.bold: true
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: rootWidget.scanResults

              Rectangle {
                width: parent.width
                implicitHeight: devRow.implicitHeight + Style.space(8)
                radius: Style.cornerRadius
                color: Style.controlFill(false, false, (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, Color.accent)
                border.color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.6)
                border.width: 1

                RowLayout {
                  id: devRow
                  anchors.fill: parent
                  anchors.margins: Style.space(6)

                  Column {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                      text: modelData.name
                      color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
                      font.bold: true
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      text: modelData.ip + " • " + modelData.model + (modelData.paired ? " (Paired)" : " (Unpaired)")
                      color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.4)
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Button {
                    visible: modelData.ip === rootWidget.tvIp
                    text: "Active"
                    selected: true
                    bordered: true
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(6)
                  }

                  Button {
                    visible: modelData.ip !== rootWidget.tvIp
                    text: "Select"
                    bordered: true
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(6)
                    onClicked: {
                      rootWidget.selectTv(modelData.ip, modelData.name, modelData.port)
                    }
                  }

                  Button {
                    visible: !modelData.paired && !(modelData.ip === rootWidget.tvIp && rootWidget.tvPaired)
                    text: "Pair"
                    accent: Color.accent
                    bordered: true
                    fontSize: Style.font.caption
                    verticalPadding: Style.space(2)
                    horizontalPadding: Style.space(6)
                    onClicked: {
                      rootWidget.selectTv(modelData.ip, modelData.name, modelData.port)
                      rootWidget.startPairing(modelData.ip)
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Manually Add TV Section
          PanelSectionHeader {
            text: "MANUALLY ADD A TV"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          TextField {
            id: manualIpField
            width: parent.width
            placeholderText: "TV IP Address (e.g. 192.168.1.100)"
            text: rootWidget.manualIpText
            onTextChanged: rootWidget.manualIpText = text
          }

          TextField {
            id: manualNameField
            width: parent.width
            placeholderText: "TV Name (e.g. Living Room Google TV)"
            text: rootWidget.manualNameText
            onTextChanged: rootWidget.manualNameText = text
          }

          Button {
            width: parent.width
            text: "Add TV to List"
            iconText: "󰐕"
            bordered: true
            onClicked: rootWidget.addTvManual()
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          Button {
            width: parent.width
            text: "Configure 4 App Shortcuts"
            iconText: "󰏫"
            bordered: true
            onClicked: rootWidget.currentView = "apps_edit"
          }
        }

        // ==========================================
        // VIEW 3: PAIRING VIEW
        // ==========================================
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: rootWidget.currentView === "pairing"

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              iconText: "󰁮"
              text: "Cancel"
              bordered: true
              onClicked: rootWidget.cancelPairing()
            }

            Text {
              text: "Pairing with TV"
              color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
              font.family: rootWidget.bar ? rootWidget.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              Layout.fillWidth: true
            }

            Button {
              iconText: cardRoot.isFloating ? "󰖳" : "󰖲"
              tooltipText: cardRoot.isFloating ? "Dock to bar" : "Float remote (detach)"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.toggleFloatingRequested()
            }

            Button {
              visible: cardRoot.isFloating
              iconText: "󰅖"
              tooltipText: "Close"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.closeRequested()
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          Rectangle {
            width: parent.width
            implicitHeight: pairInstructCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12)
            border.color: Color.accent
            border.width: 1

            Column {
              id: pairInstructCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(6)

              Text {
                text: "📺 Look at your TV screen!"
                color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
                font.bold: true
                font.pixelSize: Style.font.body
              }

              Text {
                text: "A 6-character code (hex / alphanumeric) is displayed on your TV right now.\nEnter it below to complete authorization:"
                color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.2)
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                width: parent.width
              }
            }
          }

          TextField {
            id: pairField
            width: parent.width
            placeholderText: "Enter 6-character code"
            font.pixelSize: Style.font.heading
            text: rootWidget.pairingCodeInput
            onTextChanged: rootWidget.pairingCodeInput = text.toUpperCase()
            onAccepted: rootWidget.finishPairing(text)
          }

          Text {
            width: parent.width
            text: rootWidget.pairingError
            color: Color.urgent
            font.bold: true
            font.pixelSize: Style.font.caption
            visible: rootWidget.pairingError.length > 0
            wrapMode: Text.Wrap
          }

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              Layout.fillWidth: true
              text: "Cancel"
              bordered: true
              onClicked: rootWidget.cancelPairing()
            }

            Button {
              Layout.fillWidth: true
              text: "Confirm & Pair"
              accent: Color.accent
              bordered: true
              onClicked: rootWidget.finishPairing(pairField.text)
            }
          }
        }

        // ==========================================
        // VIEW 4: APP BUTTONS SETUP
        // ==========================================
        Column {
          width: parent.width
          spacing: Style.space(12)
          visible: rootWidget.currentView === "apps_edit"

          RowLayout {
            width: parent.width
            spacing: Style.space(8)

            Button {
              iconText: "󰁮"
              text: "Done"
              bordered: true
              onClicked: rootWidget.currentView = "remote"
            }

            Text {
              text: "Program App Buttons"
              color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
              font.family: rootWidget.bar ? rootWidget.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.heading
              font.bold: true
              Layout.fillWidth: true
            }

            Button {
              iconText: cardRoot.isFloating ? "󰖳" : "󰖲"
              tooltipText: cardRoot.isFloating ? "Dock to bar" : "Float remote (detach)"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.toggleFloatingRequested()
            }

            Button {
              visible: cardRoot.isFloating
              iconText: "󰅖"
              tooltipText: "Close"
              fontSize: Style.font.caption
              verticalPadding: Style.space(2)
              horizontalPadding: Style.space(6)
              bordered: true
              onClicked: cardRoot.closeRequested()
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          PanelSectionHeader {
            text: "SELECT BUTTON SLOT TO CONFIGURE"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          // 4 Slot Selection Tabs
          RowLayout {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: [1, 2, 3, 4]

              Button {
                Layout.fillWidth: true
                text: "Slot " + modelData
                selected: rootWidget.selectedSlot === modelData
                bordered: true
                onClicked: {
                  rootWidget.selectedSlot = modelData
                  var cur = rootWidget.programmableButtons[modelData - 1]
                  if (cur) {
                    rootWidget.customNameText = cur.name || ""
                    rootWidget.customAppText = cur.app || ""
                  }
                }
              }
            }
          }

          // Current Slot Info
          Rectangle {
            width: parent.width
            implicitHeight: slotInfoCol.implicitHeight + Style.space(12)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, Color.accent)
            border.color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.6)
            border.width: 1

            Column {
              id: slotInfoCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: 2

              Text {
                text: "Currently assigned to Slot " + rootWidget.selectedSlot + ":"
                color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.4)
                font.pixelSize: Style.font.caption
              }

              Text {
                text: {
                  var cur = rootWidget.programmableButtons[rootWidget.selectedSlot - 1]
                  return cur ? (cur.name + " (" + cur.app + ")") : "Not assigned"
                }
                color: Color.accent
                font.bold: true
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Common Apps List
          PanelSectionHeader {
            text: "COMMON APPS (1-CLICK SETUP)"
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          Grid {
            width: parent.width
            columns: 2
            spacing: Style.space(6)

            Repeater {
              model: rootWidget.commonApps

              Button {
                width: (flick.width - Style.space(6)) / 2
                text: modelData.name
                iconText: modelData.icon
                bordered: true
                onClicked: {
                  rootWidget.setButton(rootWidget.selectedSlot, modelData.name, modelData.app, modelData.icon)
                  rootWidget.customNameText = modelData.name
                  rootWidget.customAppText = modelData.app
                }
              }
            }
          }

          PanelSeparator { foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground }

          // Custom App Form
          PanelSectionHeader {
            text: "ADD CUSTOM APP TO SLOT " + rootWidget.selectedSlot
            foreground: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
          }

          TextField {
            width: parent.width
            placeholderText: "App Button Label (e.g. Jellyfin)"
            text: rootWidget.customNameText
            onTextChanged: rootWidget.customNameText = text
          }

          TextField {
            width: parent.width
            placeholderText: "Package ID or URL (e.g. org.jellyfin.androidtv)"
            text: rootWidget.customAppText
            onTextChanged: rootWidget.customAppText = text
          }

          Button {
            width: parent.width
            text: "Save Custom App to Slot " + rootWidget.selectedSlot
            accent: Color.accent
            bordered: true
            onClicked: {
              if (rootWidget.customAppText.trim().length > 0) {
                var label = rootWidget.customNameText.trim() || "App"
                rootWidget.setButton(rootWidget.selectedSlot, label, rootWidget.customAppText.trim(), "󰐊")
              }
            }
          }

          // Step-by-Step Instructions Card
          Rectangle {
            width: parent.width
            implicitHeight: instructCol.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: Style.controlFill(false, false, (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, Color.accent)
            border.color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.6)
            border.width: 1

            Column {
              id: instructCol
              anchors.fill: parent
              anchors.margins: Style.space(10)
              spacing: Style.space(4)

              Text {
                text: "ℹ How to find an Android TV App ID:"
                color: (rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground
                font.bold: true
                font.pixelSize: Style.font.caption
              }

              Text {
                text: "1. Open play.google.com in a web browser.\n2. Search for the Android TV app.\n3. Check the page URL in your browser bar:\n   play.google.com/store/apps/details?id=package.name\n4. Copy the package ID (e.g. org.xbmc.kodi) and paste it above.\n\nDeep link URLs (e.g. https://... or netflix://) are also supported."
                color: Qt.darker((rootWidget && rootWidget.barForeground) ? rootWidget.barForeground : Color.foreground, 1.3)
                font.pixelSize: Style.font.caption
                wrapMode: Text.Wrap
                width: parent.width
              }
            }
          }
        }
      }
    }
  }
}
