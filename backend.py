#!/usr/bin/env python3
"""
Google TV / Android TV Remote Backend for Omarchy Shell.
Handles mDNS discovery, pairing, remote control keys, and app launching
via Android TV Remote protocol v2.
"""

import sys
import os
import json
import socket
import select
import asyncio
import signal
import re
import subprocess
from pathlib import Path
from typing import Optional, Dict, Any, List, Tuple

CONFIG_DIR = Path.home() / ".config" / "omarchy" / "googletv"
VENV_DIR = CONFIG_DIR / ".venv"
if not VENV_DIR.exists():
    fallback_venv = Path.home() / ".config" / "omarchy" / "plugins" / "omarchy-googletv" / ".venv"
    if fallback_venv.exists():
        VENV_DIR = fallback_venv

if VENV_DIR.exists():
    lib_dir = VENV_DIR / "lib"
    if lib_dir.exists():
        for p in lib_dir.glob("python*/site-packages"):
            if str(p) not in sys.path:
                sys.path.insert(0, str(p))

try:
    from androidtvremote2 import (
        AndroidTVRemote,
        CannotConnect,
        ConnectionClosed,
        InvalidAuth,
    )
    from androidtvremote2.remotemessage_pb2 import (
        RemoteMessage,
        RemoteImeBatchEdit,
        RemoteEditInfo,
        RemoteImeObject,
    )
except ImportError:
    AndroidTVRemote = None
    CannotConnect = ConnectionClosed = InvalidAuth = Exception
    RemoteMessage = RemoteImeBatchEdit = RemoteEditInfo = RemoteImeObject = None

CONFIG_FILE = CONFIG_DIR / "config.json"
CERT_DIR = CONFIG_DIR / "certs"
CERT_FILE = CERT_DIR / "cert.pem"
KEY_FILE = CERT_DIR / "key.pem"
SOCKET_FILE = CONFIG_DIR / "daemon.sock"
PID_FILE = CONFIG_DIR / "daemon.pid"

COMMON_APPS = [
    {"id": "youtube", "name": "YouTube", "app": "com.google.android.youtube.tv", "icon": "󰗃", "category": "Video"},
    {"id": "netflix", "name": "Netflix", "app": "com.netflix.ninja", "icon": "󰝆", "category": "Video"},
    {"id": "disney", "name": "Disney+", "app": "com.disney.disneyplus", "icon": "󰵈", "category": "Video"},
    {"id": "prime", "name": "Prime Video", "app": "com.amazon.amazonvideo.livingroom", "icon": "󰢔", "category": "Video"},
    {"id": "plex", "name": "Plex", "app": "com.plexapp.android", "icon": "󰚥", "category": "Media"},
    {"id": "spotify", "name": "Spotify", "app": "com.spotify.tv.android", "icon": "󰓇", "category": "Music"},
    {"id": "twitch", "name": "Twitch", "app": "tv.twitch.android.app", "icon": "󰕹", "category": "Streaming"},
    {"id": "appletv", "name": "Apple TV", "app": "com.apple.atve.androidtv.appletv", "icon": "󰀵", "category": "Video"},
    {"id": "max", "name": "Max", "app": "com.wbd.stream", "icon": "󰨜", "category": "Video"},
    {"id": "kodi", "name": "Kodi", "app": "org.xbmc.kodi", "icon": "󰈹", "category": "Media"},
    {"id": "smarttube", "name": "SmartTube", "app": "com.teamsmart.videomanager.tv", "icon": "󰗃", "category": "Video"},
    {"id": "jellyfin", "name": "Jellyfin", "app": "org.jellyfin.androidtv", "icon": "󰑋", "category": "Media"},
    {"id": "hulu", "name": "Hulu", "app": "com.hulu.livingroomplus", "icon": "󰚗", "category": "Video"},
    {"id": "crunchyroll", "name": "Crunchyroll", "app": "com.crunchyroll.crunchyroid", "icon": "󰄛", "category": "Anime"},
    {"id": "vlc", "name": "VLC", "app": "org.videolan.vlc", "icon": "󰐊", "category": "Media"}
]

DEFAULT_BUTTONS = [
    {"slot": 1, "name": "YouTube", "app": "com.google.android.youtube.tv", "icon": "󰗃"},
    {"slot": 2, "name": "Netflix", "app": "com.netflix.ninja", "icon": "󰝆"},
    {"slot": 3, "name": "Disney+", "app": "com.disney.disneyplus", "icon": "󰵈"},
    {"slot": 4, "name": "Prime", "app": "com.amazon.amazonvideo.livingroom", "icon": "󰢔"}
]

APP_DEEP_LINKS: Dict[str, str] = {
    # YouTube & SmartTube
    "com.google.android.youtube.tv": "https://www.youtube.com",
    "com.google.android.youtube": "https://www.youtube.com",
    "youtube": "https://www.youtube.com",
    "vnd.youtube": "https://www.youtube.com",
    "com.teamsmart.videomanager.tv": "https://www.youtube.com",
    "org.smarttube.beta": "https://www.youtube.com",
    "smarttube": "https://www.youtube.com",
    # Netflix
    "com.netflix.ninja": "https://www.netflix.com/title",
    "com.netflix.mediaclient": "https://www.netflix.com/title",
    "netflix": "https://www.netflix.com/title",
    # Disney+
    "com.disney.disneyplus": "https://www.disneyplus.com",
    "disney": "https://www.disneyplus.com",
    "disney+": "https://www.disneyplus.com",
    # Prime Video
    "com.amazon.amazonvideo.livingroom": "https://app.primevideo.com",
    "com.amazon.avod.thirdpartyclient": "https://app.primevideo.com",
    "prime": "https://app.primevideo.com",
    "prime video": "https://app.primevideo.com",
    "amazon": "https://app.primevideo.com",
    # Plex
    "com.plexapp.android": "plex://",
    "plex": "plex://",
    # Spotify
    "com.spotify.tv.android": "spotify://",
    "com.spotify.music": "spotify://",
    "spotify": "spotify://",
    # Twitch
    "tv.twitch.android.app": "twitch://home",
    "twitch": "twitch://home",
    # Apple TV
    "com.apple.atve.androidtv.appletv": "https://tv.apple.com",
    "appletv": "https://tv.apple.com",
    "apple tv": "https://tv.apple.com",
    # Max / HBO Max
    "com.wbd.stream": "https://play.max.com",
    "max": "https://play.max.com",
    "com.hbo.hbonow": "https://play.hbomax.com",
    "hbomax": "https://play.hbomax.com",
    "hbo": "https://play.hbomax.com",
    # Kodi
    "org.xbmc.kodi": "kodi://",
    "kodi": "kodi://",
    # Jellyfin
    "org.jellyfin.androidtv": "jellyfin://",
    "jellyfin": "jellyfin://",
    # Hulu
    "com.hulu.livingroomplus": "https://www.hulu.com",
    "hulu": "https://www.hulu.com",
    # Crunchyroll
    "com.crunchyroll.crunchyroid": "crunchyroll://",
    "crunchyroll": "crunchyroll://",
    # VLC
    "org.videolan.vlc": "vlc://",
    "vlc": "vlc://",
    # Stremio
    "com.stremio.one": "stremio:///",
    "stremio": "stremio:///",
    # Emby
    "tv.emby.embyatv": "embyatv://tv.emby.embyatv/startapp",
    "emby": "embyatv://tv.emby.embyatv/startapp",
    # Tubi
    "com.tubitv": "https://tubitv.com/",
    "tubi": "https://tubitv.com/",
    # Paramount+
    "com.cbs.ott": "https://www.paramountplus.com/",
    "paramount": "https://www.paramountplus.com/",
    "paramount+": "https://www.paramountplus.com/",
    # Google Play Store
    "com.android.vending": "https://play.google.com/store/",
    "playstore": "https://play.google.com/store/",
    "play store": "https://play.google.com/store/",
}

def resolve_app_target(app_str: str) -> str:
    """Resolve an app package name, identifier, or URI to a working Android TV deep link."""
    cleaned = (app_str or "").strip()
    if not cleaned:
        return ""
    if "://" in cleaned:
        return cleaned
    lower = cleaned.lower()
    if lower in APP_DEEP_LINKS:
        return APP_DEEP_LINKS[lower]
    if cleaned in APP_DEEP_LINKS:
        return APP_DEEP_LINKS[cleaned]
    if lower.startswith("www.") or lower.endswith(".com") or lower.endswith(".tv") or lower.endswith(".org"):
        return f"https://{cleaned}"
    return cleaned

# Mapping of character -> (RemoteKeyCode base name, requires_shift)
# Universally supported by Android TV IME and all third-party app search boxes.
CHAR_KEY_MAP: Dict[str, Tuple[str, bool]] = {
    # Lowercase letters
    'a': ('A', False), 'b': ('B', False), 'c': ('C', False), 'd': ('D', False),
    'e': ('E', False), 'f': ('F', False), 'g': ('G', False), 'h': ('H', False),
    'i': ('I', False), 'j': ('J', False), 'k': ('K', False), 'l': ('L', False),
    'm': ('M', False), 'n': ('N', False), 'o': ('O', False), 'p': ('P', False),
    'q': ('Q', False), 'r': ('R', False), 's': ('S', False), 't': ('T', False),
    'u': ('U', False), 'v': ('V', False), 'w': ('W', False), 'x': ('X', False),
    'y': ('Y', False), 'z': ('Z', False),

    # Uppercase letters
    'A': ('A', True), 'B': ('B', True), 'C': ('C', True), 'D': ('D', True),
    'E': ('E', True), 'F': ('F', True), 'G': ('G', True), 'H': ('H', True),
    'I': ('I', True), 'J': ('J', True), 'K': ('K', True), 'L': ('L', True),
    'M': ('M', True), 'N': ('N', True), 'O': ('O', True), 'P': ('P', True),
    'Q': ('Q', True), 'R': ('R', True), 'S': ('S', True), 'T': ('T', True),
    'U': ('U', True), 'V': ('V', True), 'W': ('W', True), 'X': ('X', True),
    'Y': ('Y', True), 'Z': ('Z', True),

    # Digits
    '0': ('0', False), '1': ('1', False), '2': ('2', False), '3': ('3', False),
    '4': ('4', False), '5': ('5', False), '6': ('6', False), '7': ('7', False),
    '8': ('8', False), '9': ('9', False),

    # Whitespace & Control
    ' ': ('SPACE', False),
    '\t': ('TAB', False),
    '\n': ('ENTER', False),
    '\r': ('ENTER', False),

    # Direct / unshifted punctuation
    '.': ('PERIOD', False),
    ',': ('COMMA', False),
    '-': ('MINUS', False),
    '=': ('EQUALS', False),
    '/': ('SLASH', False),
    '\\': ('BACKSLASH', False),
    ';': ('SEMICOLON', False),
    "'": ('APOSTROPHE', False),
    '[': ('LEFT_BRACKET', False),
    ']': ('RIGHT_BRACKET', False),
    '`': ('GRAVE', False),

    # Dedicated keycodes
    '@': ('AT', False),
    '*': ('STAR', False),
    '#': ('POUND', False),
    '+': ('PLUS', False),

    # Shifted punctuation
    '!': ('1', True),
    '$': ('4', True),
    '%': ('5', True),
    '^': ('6', True),
    '&': ('7', True),
    '(': ('9', True),
    ')': ('0', True),
    '_': ('MINUS', True),
    '{': ('LEFT_BRACKET', True),
    '}': ('RIGHT_BRACKET', True),
    '|': ('BACKSLASH', True),
    ':': ('SEMICOLON', True),
    '"': ('APOSTROPHE', True),
    '<': ('COMMA', True),
    '>': ('PERIOD', True),
    '?': ('SLASH', True),
    '~': ('GRAVE', True),
}

def ensure_dirs():
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    CERT_DIR.mkdir(parents=True, exist_ok=True)

def load_config() -> Dict[str, Any]:
    ensure_dirs()
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    # Initial default configuration
    default_cfg = {
        "selected_tv": "",
        "tvs": {},
        "programmable_buttons": DEFAULT_BUTTONS
    }
    save_config(default_cfg)
    return default_cfg

def save_config(cfg: Dict[str, Any]):
    ensure_dirs()
    temp_file = CONFIG_FILE.with_suffix(".tmp")
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(cfg, f, indent=2)
    temp_file.replace(CONFIG_FILE)

def scan_network(timeout_sec: int = 2) -> List[Dict[str, Any]]:
    """Scan local network for Android TV / Google TV / Cast devices via avahi-browse."""
    devices: Dict[str, Dict[str, Any]] = {}

    # Scan _androidtvremote2._tcp
    try:
        cmd = ["timeout", str(timeout_sec), "avahi-browse", "-rtp", "_androidtvremote2._tcp"]
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_sec + 1)
        for line in p.stdout.splitlines():
            parts = line.split(";")
            if len(parts) >= 9 and parts[0] == "=" and parts[2] == "IPv4":
                name = parts[3].strip()
                ip = parts[7].strip()
                port = int(parts[8]) if parts[8].isdigit() else 6466
                devices[ip] = {
                    "name": name,
                    "ip": ip,
                    "port": port,
                    "model": "Android TV / Google TV",
                    "paired": False
                }
    except Exception:
        pass

    # Also scan _googlecast._tcp for friendly names and TV device models
    try:
        cmd2 = ["timeout", str(timeout_sec), "avahi-browse", "-rtp", "_googlecast._tcp"]
        p2 = subprocess.run(cmd2, capture_output=True, text=True, timeout=timeout_sec + 1)
        for line in p2.stdout.splitlines():
            parts = line.split(";")
            if len(parts) >= 9 and parts[0] == "=" and parts[2] == "IPv4":
                ip = parts[7].strip()
                txt = parts[9] if len(parts) > 9 else ""
                fn_match = re.search(r'"fn=([^"]+)"', txt)
                md_match = re.search(r'"md=([^"]+)"', txt)
                fn = fn_match.group(1).strip() if fn_match else parts[3].strip()
                md = md_match.group(1).strip() if md_match else "Chromecast"

                # Check if it looks like a TV or streamer or already discovered via remote2
                is_tv_device = any(k in md.lower() for k in ["tv", "shield", "streamer", "bravia", "fire", "chromecast"])
                if is_tv_device or ip in devices:
                    if ip not in devices:
                        devices[ip] = {
                            "name": fn or parts[3].strip(),
                            "ip": ip,
                            "port": 6466,
                            "model": md,
                            "paired": False
                        }
                    else:
                        if md:
                            devices[ip]["model"] = md
                        if fn and not fn.startswith("Android"):
                            devices[ip]["name"] = fn
    except Exception:
        pass

    # Merge paired status from current config
    cfg = load_config()
    saved_tvs = cfg.get("tvs", {})
    for ip, dev in devices.items():
        if ip in saved_tvs:
            dev["paired"] = saved_tvs[ip].get("paired", False)
            if saved_tvs[ip].get("name"):
                dev["name"] = saved_tvs[ip]["name"]

    return list(devices.values())

class GoogleTVDaemon:
    def __init__(self):
        self.config = load_config()
        self.remote: Optional[AndroidTVRemote] = None
        self.pairing_remote: Optional[AndroidTVRemote] = None
        self.pairing_active: bool = False
        self.pairing_ip: str = ""
        self.connected: bool = False
        self.is_on: bool = False
        self.current_app: str = ""
        self.volume_info: Dict[str, Any] = {}
        self.server_sock: Optional[socket.socket] = None
        self.running: bool = True
        self.loop: Optional[asyncio.AbstractEventLoop] = None
        self.reconnect_task: Optional[asyncio.Task] = None

    def get_active_tv(self) -> Optional[Dict[str, Any]]:
        selected = self.config.get("selected_tv", "")
        tvs = self.config.get("tvs", {})
        if selected and selected in tvs:
            return tvs[selected]
        if tvs:
            first_ip = next(iter(tvs.keys()))
            return tvs[first_ip]
        return None

    def _is_transport_connected(self) -> bool:
        if not self.remote or not self.connected:
            return False
        proto = getattr(self.remote, "_remote_message_protocol", None)
        if not proto:
            return False
        transport = getattr(proto, "transport", None)
        return bool(transport and not transport.is_closing())

    def _on_is_available_updated(self, is_available: bool):
        self.connected = is_available

    def _on_invalid_auth(self):
        self.connected = False
        tv = self.get_active_tv()
        if tv:
            tv["paired"] = False
            self.config.get("tvs", {})[tv["ip"]] = tv
            save_config(self.config)

    def _on_is_on_updated(self, is_on: bool):
        self.is_on = is_on

    def _on_current_app_updated(self, app: str):
        self.current_app = app

    def _on_volume_info_updated(self, vol_info):
        try:
            self.volume_info = {
                "level": getattr(vol_info, "level", 0),
                "max": getattr(vol_info, "max", 100),
                "muted": getattr(vol_info, "muted", False)
            }
        except Exception:
            pass

    async def connect_active_tv(self):
        tv = self.get_active_tv()
        if not tv:
            self.connected = False
            return False

        ip = tv.get("ip")
        port = tv.get("port", 6466)
        pair_port = tv.get("pair_port", 6467)

        if not tv.get("paired", False):
            self.connected = False
            return False

        if self.remote:
            try:
                self.remote.disconnect()
            except Exception:
                pass
            self.remote = None

        try:
            self.remote = AndroidTVRemote(
                "Omarchy",
                str(CERT_FILE),
                str(KEY_FILE),
                ip,
                api_port=port,
                pair_port=pair_port,
                loop=self.loop
            )
            await self.remote.async_generate_cert_if_missing()
            self.remote.add_is_on_updated_callback(self._on_is_on_updated)
            self.remote.add_current_app_updated_callback(self._on_current_app_updated)
            self.remote.add_volume_info_updated_callback(self._on_volume_info_updated)
            self.remote.add_is_available_updated_callback(self._on_is_available_updated)

            await asyncio.wait_for(self.remote.async_connect(), timeout=4.0)
            self.connected = True
            self.remote.keep_reconnecting(invalid_auth_callback=self._on_invalid_auth)
            return True
        except (InvalidAuth, ConnectionClosed, CannotConnect, asyncio.TimeoutError, Exception) as exc:
            self.connected = False
            if isinstance(exc, InvalidAuth):
                # Mark as unpaired if invalid auth
                tv["paired"] = False
                self.config["tvs"][ip] = tv
                save_config(self.config)
            return False

    async def auto_reconnect_loop(self):
        while self.running:
            tv = self.get_active_tv()
            if tv and tv.get("paired", False) and not self._is_transport_connected() and not self.pairing_active:
                await self.connect_active_tv()
            await asyncio.sleep(5)

    async def handle_client(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
        try:
            line = await reader.readline()
            if not line:
                writer.close()
                await writer.wait_closed()
                return

            req = json.loads(line.decode("utf-8").strip())
            cmd = req.get("cmd", "")
            resp = await self.process_command(cmd, req)
            writer.write((json.dumps(resp) + "\n").encode("utf-8"))
            await writer.drain()
        except Exception as e:
            err_resp = {"ok": False, "error": str(e)}
            try:
                writer.write((json.dumps(err_resp) + "\n").encode("utf-8"))
                await writer.drain()
            except Exception:
                pass
        finally:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass

    async def send_text_to_tv(self, text_str: str) -> None:
        """Send text to TV via Android TV Remote v2 protocol.
        
        Uses the proven two-step IME batch edit sequence (insert=0 followed by insert=1)
        which correctly synchronizes with Android TV's virtual keyboard and updates the
        active input field across Google TV Search, Play Store, YouTube, and all IME apps.
        """
        if not self.remote:
            return

        proto = getattr(self.remote, "_remote_message_protocol", None)
        if not proto:
            return

        if RemoteMessage and RemoteImeBatchEdit and RemoteEditInfo and RemoteImeObject:
            try:
                # Step 1: Initialize/clear target field with insert=0
                obj0 = RemoteImeObject(start=0, end=len(text_str), value=text_str)
                edit0 = RemoteEditInfo(insert=0, text_field_status=obj0)
                b0 = RemoteImeBatchEdit(ime_counter=0, field_counter=0, edit_info=[edit0])
                msg0 = RemoteMessage()
                msg0.remote_ime_batch_edit.CopyFrom(b0)
                proto._send_message(msg0)

                # Brief pause to let Android TV input method process the field state
                await asyncio.sleep(0.08)

                # Step 2: Commit the full text string with insert=1
                param = max(0, len(text_str) - 1)
                obj1 = RemoteImeObject(start=param, end=param, value=text_str)
                edit1 = RemoteEditInfo(insert=1, text_field_status=obj1)
                b1 = RemoteImeBatchEdit(ime_counter=0, field_counter=0, edit_info=[edit1])
                msg1 = RemoteMessage()
                msg1.remote_ime_batch_edit.CopyFrom(b1)
                proto._send_message(msg1)
                return
            except Exception:
                pass

        # Fallback to standard send_text
        try:
            self.remote.send_text(text_str)
        except Exception:
            pass

    async def process_command(self, cmd: str, req: Dict[str, Any]) -> Dict[str, Any]:
        if cmd == "ping":
            return {
                "ok": True,
                "connected": self.connected,
                "pairing_active": self.pairing_active,
                "active_tv": self.get_active_tv()
            }

        elif cmd == "status":
            is_connected = self._is_transport_connected()
            return {
                "ok": True,
                "connected": is_connected,
                "is_on": self.is_on if is_connected else False,
                "current_app": self.current_app if is_connected else "",
                "volume": self.volume_info if is_connected else {},
                "pairing_active": self.pairing_active,
                "active_tv": self.get_active_tv(),
                "config": self.config,
                "common_apps": COMMON_APPS
            }

        elif cmd == "key":
            key_name = req.get("key", "").upper()
            if not key_name:
                return {"ok": False, "error": "No key specified"}

            if not self._is_transport_connected():
                connected = await self.connect_active_tv()
                if not connected or not self._is_transport_connected():
                    return {"ok": False, "error": "TV not connected. Check pairing."}

            try:
                self.remote.send_key_command(key_name)
                return {"ok": True, "key": key_name}
            except Exception as e:
                self.connected = False
                return {"ok": False, "error": str(e)}

        elif cmd == "launch":
            app = req.get("app", "")
            if not app:
                return {"ok": False, "error": "No app specified"}

            if not self._is_transport_connected():
                connected = await self.connect_active_tv()
                if not connected or not self._is_transport_connected():
                    return {"ok": False, "error": "TV not connected. Check pairing."}

            target = resolve_app_target(app)
            try:
                self.remote.send_launch_app_command(target)
                return {"ok": True, "app": app, "target": target}
            except Exception as e:
                self.connected = False
                return {"ok": False, "error": str(e)}

        elif cmd == "text":
            text_str = req.get("text", "")
            if not text_str:
                return {"ok": False, "error": "No text specified"}

            if not self._is_transport_connected():
                connected = await self.connect_active_tv()
                if not connected or not self._is_transport_connected():
                    return {"ok": False, "error": "TV not connected. Check pairing."}

            try:
                await self.send_text_to_tv(text_str)
                return {"ok": True, "text": text_str}
            except Exception as e:
                self.connected = False
                return {"ok": False, "error": str(e)}

        elif cmd == "pair_start":
            ip = req.get("ip")
            if not ip:
                active = self.get_active_tv()
                if active:
                    ip = active.get("ip")
            if not ip:
                return {"ok": False, "error": "No IP specified"}

            # Disconnect current remote if any
            if self.remote:
                try:
                    self.remote.disconnect()
                except Exception:
                    pass
                self.remote = None
            self.connected = False

            if self.pairing_remote:
                try:
                    self.pairing_remote.disconnect()
                except Exception:
                    pass
                self.pairing_remote = None

            try:
                self.pairing_ip = ip
                tv = self.config.get("tvs", {}).get(ip, {})
                api_port = int(tv.get("port", 6466))
                pair_port = int(tv.get("pair_port", 6467))
                self.pairing_remote = AndroidTVRemote(
                    "Omarchy",
                    str(CERT_FILE),
                    str(KEY_FILE),
                    ip,
                    api_port=api_port,
                    pair_port=pair_port,
                    loop=self.loop
                )
                await self.pairing_remote.async_generate_cert_if_missing()
                await asyncio.wait_for(self.pairing_remote.async_start_pairing(), timeout=8.0)
                self.pairing_active = True
                return {
                    "ok": True,
                    "status": "pairing_started",
                    "ip": ip,
                    "message": "Enter code shown on TV screen"
                }
            except Exception as e:
                self.pairing_active = False
                if self.pairing_remote:
                    try:
                        self.pairing_remote.disconnect()
                    except Exception:
                        pass
                    self.pairing_remote = None
                return {"ok": False, "error": f"Failed to start pairing: {e}"}

        elif cmd == "pair_finish":
            code = req.get("code", "").strip()
            if not code:
                return {"ok": False, "error": "No pairing code entered"}

            if not self.pairing_remote or not self.pairing_active:
                return {"ok": False, "error": "No active pairing session. Start pairing first."}

            try:
                await asyncio.wait_for(self.pairing_remote.async_finish_pairing(code), timeout=8.0)
                self.pairing_active = False
                target_ip = self.pairing_ip
                self.pairing_remote = None

                # Update config
                tvs = self.config.get("tvs", {})
                if target_ip in tvs:
                    tvs[target_ip]["paired"] = True
                else:
                    tvs[target_ip] = {
                        "name": f"Google TV ({target_ip})",
                        "ip": target_ip,
                        "port": 6466,
                        "paired": True
                    }
                self.config["selected_tv"] = target_ip
                self.config["tvs"] = tvs
                save_config(self.config)

                # Connect active TV
                await self.connect_active_tv()
                return {"ok": True, "status": "paired", "ip": target_ip}
            except Exception as e:
                self.pairing_active = False
                if self.pairing_remote:
                    try:
                        self.pairing_remote.disconnect()
                    except Exception:
                        pass
                    self.pairing_remote = None
                return {"ok": False, "error": f"Pairing failed: {e}"}

        elif cmd == "pair_cancel":
            self.pairing_active = False
            if self.pairing_remote:
                try:
                    self.pairing_remote.disconnect()
                except Exception:
                    pass
                self.pairing_remote = None
            return {"ok": True}

        elif cmd == "scan":
            devices = scan_network()
            return {"ok": True, "devices": devices}

        elif cmd == "add_tv":
            ip = req.get("ip", "").strip()
            name = req.get("name", "").strip() or f"Google TV ({ip})"
            port = int(req.get("port", 6466))
            model = req.get("model", "Google TV")
            if not ip:
                return {"ok": False, "error": "Missing IP"}

            tvs = self.config.get("tvs", {})
            tvs[ip] = {
                "name": name,
                "ip": ip,
                "port": port,
                "model": model,
                "paired": tvs.get(ip, {}).get("paired", False)
            }
            self.config["selected_tv"] = ip
            self.config["tvs"] = tvs
            save_config(self.config)
            await self.connect_active_tv()
            return {"ok": True, "config": self.config}

        elif cmd == "remove_tv":
            ip = req.get("ip", "").strip()
            tvs = self.config.get("tvs", {})
            if ip in tvs:
                del tvs[ip]
                if self.config.get("selected_tv") == ip:
                    self.config["selected_tv"] = next(iter(tvs.keys())) if tvs else ""
                self.config["tvs"] = tvs
                save_config(self.config)
                if self.remote:
                    self.remote.disconnect()
                    self.remote = None
                self.connected = False
            return {"ok": True, "config": self.config}

        elif cmd == "select_tv":
            ip = req.get("ip", "").strip()
            name = req.get("name", "").strip()
            port = int(req.get("port", 6466))
            model = req.get("model", "Google TV")
            if not ip:
                return {"ok": False, "error": "Missing IP"}

            tvs = self.config.get("tvs", {})
            if ip not in tvs:
                tvs[ip] = {
                    "name": name or f"Google TV ({ip})",
                    "ip": ip,
                    "port": port,
                    "model": model,
                    "paired": False
                }
            elif name and (tvs[ip].get("name", "").startswith("Google TV (") or not tvs[ip].get("name")):
                tvs[ip]["name"] = name

            self.config["selected_tv"] = ip
            self.config["tvs"] = tvs
            save_config(self.config)
            await self.connect_active_tv()
            return {"ok": True, "selected_tv": ip}

        elif cmd == "set_button":
            slot = int(req.get("slot", 1))
            name = req.get("name", "").strip()
            app = req.get("app", "").strip()
            icon = req.get("icon", "󰗃")

            buttons = self.config.get("programmable_buttons", DEFAULT_BUTTONS)
            found = False
            for btn in buttons:
                if btn.get("slot") == slot:
                    btn["name"] = name
                    btn["app"] = app
                    btn["icon"] = icon
                    found = True
                    break
            if not found:
                buttons.append({"slot": slot, "name": name, "app": app, "icon": icon})

            self.config["programmable_buttons"] = buttons
            save_config(self.config)
            return {"ok": True, "buttons": buttons}

        elif cmd == "get_config":
            return {"ok": True, "config": self.config, "common_apps": COMMON_APPS}

        return {"ok": False, "error": f"Unknown command: {cmd}"}

    async def run(self):
        self.loop = asyncio.get_running_loop()
        ensure_dirs()

        # Remove stale socket
        if SOCKET_FILE.exists():
            SOCKET_FILE.unlink()

        # Write PID
        with open(PID_FILE, "w") as f:
            f.write(str(os.getpid()))

        # Start unix socket server
        server = await asyncio.start_unix_server(self.handle_client, path=str(SOCKET_FILE))
        os.chmod(str(SOCKET_FILE), 0o700)

        # Attempt connection to active TV
        await self.connect_active_tv()

        # Start reconnect task
        self.reconnect_task = asyncio.create_task(self.auto_reconnect_loop())

        try:
            async with server:
                await server.serve_forever()
        finally:
            self.running = False
            if self.reconnect_task:
                self.reconnect_task.cancel()
            if self.remote:
                self.remote.disconnect()
            if self.pairing_remote:
                self.pairing_remote.disconnect()
            if SOCKET_FILE.exists():
                SOCKET_FILE.unlink()
            if PID_FILE.exists():
                PID_FILE.unlink()

def start_daemon():
    daemon = GoogleTVDaemon()

    def handle_exit(signum, frame):
        if SOCKET_FILE.exists():
            SOCKET_FILE.unlink()
        if PID_FILE.exists():
            PID_FILE.unlink()
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)
    asyncio.run(daemon.run())

def is_daemon_alive() -> bool:
    if not SOCKET_FILE.exists():
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(str(SOCKET_FILE))
        s.sendall(b'{"cmd": "ping"}\n')
        data = s.recv(1024)
        s.close()
        return len(data) > 0
    except Exception:
        if SOCKET_FILE.exists():
            try:
                SOCKET_FILE.unlink()
            except Exception:
                pass
        return False

def ensure_daemon():
    if is_daemon_alive():
        return True
    # Spawn daemon in background using nohup / detached process
    python_bin = sys.executable
    if VENV_DIR.exists():
        venv_py = VENV_DIR / "bin" / "python"
        if venv_py.exists():
            python_bin = str(venv_py)
    script_path = str(Path(__file__).resolve())
    subprocess.Popen(
        [python_bin, script_path, "daemon"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True
    )
    # Wait up to 2 seconds for socket
    import time
    for _ in range(20):
        time.sleep(0.1)
        if is_daemon_alive():
            return True
    return False

def client_request(payload: Dict[str, Any], timeout: float = 5.0) -> Dict[str, Any]:
    ensure_daemon()
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(timeout)
    try:
        s.connect(str(SOCKET_FILE))
        msg = json.dumps(payload) + "\n"
        s.sendall(msg.encode("utf-8"))
        buf = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            buf += chunk
            if b"\n" in buf:
                break
        s.close()
        return json.loads(buf.decode("utf-8").strip())
    except Exception as e:
        return {"ok": False, "error": str(e)}

def main():
    if len(sys.argv) < 2:
        print("Usage: backend.py [daemon|ensure-daemon|status|key <NAME>|launch <APP>|text <TEXT>|scan|pair-start [IP]|pair-finish <CODE>|add-tv <IP> [NAME]|select-tv <IP>|set-button <SLOT> <NAME> <APP> [ICON]]")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "daemon":
        start_daemon()
    elif cmd == "ensure-daemon":
        alive = ensure_daemon()
        print(json.dumps({"ok": alive}))
    elif cmd == "status":
        print(json.dumps(client_request({"cmd": "status"})))
    elif cmd == "key":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing key argument"}))
            sys.exit(1)
        key_name = sys.argv[2]
        print(json.dumps(client_request({"cmd": "key", "key": key_name})))
    elif cmd == "launch":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing app argument"}))
            sys.exit(1)
        app = " ".join(sys.argv[2:])
        print(json.dumps(client_request({"cmd": "launch", "app": app})))
    elif cmd == "text":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing text argument"}))
            sys.exit(1)
        text_arg = " ".join(sys.argv[2:])
        print(json.dumps(client_request({"cmd": "text", "text": text_arg}, timeout=15.0)))
    elif cmd == "scan":
        # Scanning can take up to 3 seconds
        print(json.dumps(client_request({"cmd": "scan"}, timeout=8.0)))
    elif cmd == "pair-start":
        ip = sys.argv[2] if len(sys.argv) > 2 else ""
        print(json.dumps(client_request({"cmd": "pair_start", "ip": ip}, timeout=10.0)))
    elif cmd == "pair-finish":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing pairing code"}))
            sys.exit(1)
        code = sys.argv[2]
        print(json.dumps(client_request({"cmd": "pair_finish", "code": code}, timeout=10.0)))
    elif cmd == "pair-cancel":
        print(json.dumps(client_request({"cmd": "pair_cancel"})))
    elif cmd == "add-tv":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing IP"}))
            sys.exit(1)
        ip = sys.argv[2]
        name = sys.argv[3] if len(sys.argv) > 3 else f"Google TV ({ip})"
        port = int(sys.argv[4]) if len(sys.argv) > 4 else 6466
        print(json.dumps(client_request({"cmd": "add_tv", "ip": ip, "name": name, "port": port})))
    elif cmd == "remove-tv":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing IP"}))
            sys.exit(1)
        ip = sys.argv[2]
        print(json.dumps(client_request({"cmd": "remove_tv", "ip": ip})))
    elif cmd == "select-tv":
        if len(sys.argv) < 3:
            print(json.dumps({"ok": False, "error": "Missing IP"}))
            sys.exit(1)
        ip = sys.argv[2]
        name = sys.argv[3] if len(sys.argv) > 3 else ""
        port = int(sys.argv[4]) if len(sys.argv) > 4 else 6466
        print(json.dumps(client_request({"cmd": "select_tv", "ip": ip, "name": name, "port": port})))
    elif cmd == "set-button":
        if len(sys.argv) < 5:
            print(json.dumps({"ok": False, "error": "Usage: set-button <slot> <name> <app> [icon]"}))
            sys.exit(1)
        slot = int(sys.argv[2])
        name = sys.argv[3]
        app = sys.argv[4]
        icon = sys.argv[5] if len(sys.argv) > 5 else "󰗃"
        print(json.dumps(client_request({"cmd": "set_button", "slot": slot, "name": name, "app": app, "icon": icon})))
    elif cmd == "get-config":
        print(json.dumps(client_request({"cmd": "get_config"})))
    else:
        print(json.dumps({"ok": False, "error": f"Unknown command {cmd}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
