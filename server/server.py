"""Servidor para la PC: recibe comandos de la tablet y presiona teclas.

Uso: pip install keyboard ; python server.py   (ejecutar como administrador
si el juego corre elevado). Cambia TOKEN abajo y ponlo igual en la app.
"""
import ctypes
import json
import os
import socket
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import keyboard

# Token y puerto se pueden cambiar en config.json junto al ejecutable.
_dir = os.path.dirname(sys.executable if getattr(sys, "frozen", False) else __file__)
_cfg = {}
try:
    with open(os.path.join(_dir, "config.json"), encoding="utf-8") as f:
        _cfg = json.load(f)
except OSError:
    pass

TOKEN = _cfg.get("token", "elrors")
PORT = int(_cfg.get("port", 8765))


_MOUSE = {"mouse:left": (0x2, 0x4), "mouse:right": (0x8, 0x10), "mouse:middle": (0x20, 0x40)}
_held = {}


_ALIASES = {"right alt": "right menu", "ralt": "right menu", "rctrl": "right ctrl"}
_NUMPAD = {"right alt": 0xE038, "ralt": 0xE038, "num7": 71, "num8": 72, "num9": 73, "num4": 75, "num5": 76,
           "num6": 77, "num1": 79, "num2": 80, "num3": 81, "num0": 82}


class _KBD(ctypes.Structure):
    _fields_ = [("wVk", ctypes.c_ushort), ("wScan", ctypes.c_ushort),
                ("dwFlags", ctypes.c_ulong), ("time", ctypes.c_ulong),
                ("dwExtraInfo", ctypes.c_size_t)]


class _INPUT(ctypes.Structure):
    class _U(ctypes.Union):
        _fields_ = [("ki", _KBD), ("pad", ctypes.c_byte * 32)]
    _anonymous_ = ("u",)
    _fields_ = [("type", ctypes.c_ulong), ("u", _U)]


def _scan_key(code: int, down: bool) -> None:
    # Los juegos leen scancodes; 0xE0xx son teclas extendidas (Alt der., flechas).
    flags = 0x0008 | (0 if down else 0x0002)
    if code >= 0xE000:
        flags |= 0x0001
        code &= 0xFF
    i = _INPUT(type=1, ki=_KBD(0, code, flags, 0, 0))
    ctypes.windll.user32.SendInput(1, ctypes.byref(i), ctypes.sizeof(i))


def _part(p: str, down: bool) -> None:
    p = _ALIASES.get(p.strip().lower(), p.strip().lower())
    if p in _MOUSE:
        ctypes.windll.user32.mouse_event(_MOUSE[p][0 if down else 1], 0, 0, 0, 0)
        return
    code = _NUMPAD.get(p) or keyboard.key_to_scan_codes(p)[0]
    _scan_key(code, down)


def down(keys: str) -> None:
    for p in keys.split("+"):
        _part(p, True)
        time.sleep(0.03)


def up(keys: str) -> None:
    for p in reversed(keys.split("+")):
        _part(p, False)


def press(keys: str, hold_ms: int = 60) -> None:
    down(keys)
    time.sleep(max(hold_ms, 20) / 1000)
    up(keys)


def hold_start(keys: str) -> None:
    hold_stop(keys)
    down(keys)
    # Si la tablet pierde la conexión, suelta solo para no dejar la tecla pegada.
    t = threading.Timer(15, lambda: hold_stop(keys))
    _held[keys] = t
    t.start()


def hold_stop(keys: str) -> None:
    t = _held.pop(keys, None)
    if t:
        t.cancel()
        up(keys)


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        self._send(200, {"ok": True, "name": "sc-companion"})

    def do_POST(self):
        if self.headers.get("X-Token") != TOKEN:
            return self._send(401, {"error": "token invalido"})
        try:
            n = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(n) or b"{}")
            if self.path == "/key":
                press(str(body["keys"]), int(body.get("hold", 60)))
            elif self.path == "/down":
                hold_start(str(body["keys"]))
            elif self.path == "/up":
                hold_stop(str(body["keys"]))
            elif self.path == "/sequence":
                for step in body["steps"]:
                    press(str(step["keys"]), int(step.get("hold", 60)))
                    time.sleep(float(step.get("delay", 0.5)))
            else:
                return self._send(404, {"error": "ruta"})
            self._send(200, {"ok": True})
        except Exception as e:  # noqa: BLE001
            self._send(400, {"error": str(e)})

    def log_message(self, fmt, *args):
        pass


def local_ip() -> str:
    # La IP de la interfaz que usa la ruta a internet suele ser la de la LAN.
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("8.8.8.8", 80))
        return s.getsockname()[0]
    except OSError:
        return socket.gethostbyname(socket.gethostname())
    finally:
        s.close()


def save_config() -> None:
    with open(os.path.join(_dir, "config.json"), "w", encoding="utf-8") as f:
        json.dump({"token": TOKEN, "port": PORT}, f, indent=2)


def main() -> None:
    global TOKEN
    import tkinter as tk
    from tkinter import messagebox

    ip = local_ip()
    root = tk.Tk()
    root.title("SC Companion Server")
    root.geometry("380x260")
    root.resizable(False, False)

    tk.Label(root, text="Configura la app con estos datos:").pack(pady=(12, 4))
    tk.Label(root, text="IP de la PC:").pack()
    ip_e = tk.Entry(root, width=28, justify="center")
    ip_e.insert(0, f"{ip}:{PORT}")
    ip_e.configure(state="readonly")
    ip_e.pack()
    tk.Label(root, text="Token:").pack(pady=(8, 0))
    token_e = tk.Entry(root, width=28, justify="center")
    token_e.insert(0, TOKEN)
    token_e.pack()
    status = tk.Label(root, text="Detenido", fg="gray")
    status.pack(pady=8)

    state = {"server": None}

    def start():
        global TOKEN
        t = token_e.get().strip()
        if not t:
            return messagebox.showerror("SC Companion", "El token no puede estar vacío.")
        TOKEN = t
        save_config()
        if state["server"] is None:
            try:
                srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
            except OSError as e:
                return messagebox.showerror("SC Companion", f"No se pudo abrir el puerto {PORT}: {e}")
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            state["server"] = srv
        status.config(text=f"Activo en {ip}:{PORT}", fg="green")
        btn.config(text="Guardar token")

    btn = tk.Button(root, text="Guardar e iniciar", width=20, command=start)
    btn.pack()
    tk.Label(root, text="Cierra esta ventana para detener el servidor.",
             fg="gray", font=("Segoe UI", 8)).pack(pady=8)
    root.mainloop()


if __name__ == "__main__":
    main()
 