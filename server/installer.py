"""Instalador: copia SC-Companion-Server.exe y crea el acceso directo."""
import ctypes
import json
import os
import shutil
import subprocess
import sys
import tkinter as tk
from tkinter import messagebox

NAME = "SC Companion Server"
EXE = "SC-Companion-Server.exe"


def resource(name):
    base = getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(__file__)))
    return os.path.join(base, name)


def desktop():
    buf = ctypes.create_unicode_buffer(260)
    ctypes.windll.shell32.SHGetFolderPathW(None, 0x0000, None, 0, buf)  # CSIDL_DESKTOPDIRECTORY
    return buf.value


def install(token):
    dest = os.path.join(os.environ["LOCALAPPDATA"], "SC-Companion")
    os.makedirs(dest, exist_ok=True)
    target = os.path.join(dest, EXE)
    shutil.copyfile(resource(EXE), target)
    with open(os.path.join(dest, "config.json"), "w", encoding="utf-8") as f:
        json.dump({"token": token, "port": 8765}, f, indent=2)
    link = os.path.join(desktop(), NAME + ".lnk")
    ps = (
        "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:SC_LNK);"
        "$s.TargetPath=$env:SC_TARGET;$s.WorkingDirectory=$env:SC_DIR;"
        "$s.Description='Servidor de SC Companion';$s.Save()"
    )
    env = dict(os.environ, SC_LNK=link, SC_TARGET=target, SC_DIR=dest)
    subprocess.run(["powershell", "-NoProfile", "-Command", ps], env=env, check=True,
                   creationflags=0x08000000)
    return dest


def main():
    root = tk.Tk()
    root.title(NAME + " - Instalador")
    root.geometry("360x170")
    tk.Label(root, text="Token (debe ser igual al de la app):").pack(pady=(15, 3))
    token = tk.Entry(root, width=30)
    token.insert(0, "elrors")
    token.pack()

    def go():
        t = token.get().strip()
        if not t:
            return messagebox.showerror(NAME, "El token no puede estar vacío.")
        try:
            dest = install(t)
        except Exception as e:  # noqa: BLE001
            return messagebox.showerror(NAME, f"Error al instalar: {e}")
        messagebox.showinfo(NAME, f"Instalado en:\n{dest}\n\nUsa el acceso directo del escritorio.")
        root.destroy()

    tk.Button(root, text="Instalar", width=15, command=go).pack(pady=20)
    root.mainloop()


if __name__ == "__main__":
    main()
