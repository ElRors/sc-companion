# StarCitizen Companion

App para tablet Android que manda teclas a Star Citizen por wifi. Sirve para tener a mano, en pantalla, las cosas que en pleno combate cuestan en el teclado: energía, escudos, señuelos, VTOL, solicitud de aterrizaje y demás. No reemplaza los controles de la nave, los complementa.

No lee ni toca el juego. Solo simula pulsaciones de teclado en el PC.

## Cómo funciona

- `lib/main.dart`: la app (Flutter). Cada botón hace un POST con la tecla a enviar.
- `server/server.py`: servidor HTTP en el PC (Windows). Recibe la tecla y la inyecta con `SendInput` usando scancodes, que es lo que lee el juego.
- `server/installer.py`: instalador gráfico del servidor. Copia el exe y crea el acceso directo en el escritorio.

La app y el servidor se autentican con un token compartido que se configura en los dos lados.

## Pestañas

- **Control**: sistemas de la nave, armas, objetivo, distribución de energía y otros.
- **Macros** y **Secuencias**: teclas sueltas y rutinas (arranque, apagado, despegue).
- **Comercio**: precios de [UEX Corp](https://uexcorp.space) y calculadora de ganancia.
- **Calculadora**: [Erkul DPS Calculator](https://erkul.games/calculator) dentro de la app.
- **Timers** y **Notas**.
- **Hangar**: estado del hangar ejecutivo, con los parámetros de [exec.xyxyll.com](https://exec.xyxyll.com).

Español e inglés, se cambia en Ajustes. Manteniendo pulsado un botón se cambia su tecla.

## Compilar

App (necesita Flutter):

```
flutter pub get
flutter build apk --release
```

Servidor (necesita Python y PyInstaller):

```
cd server
pip install keyboard pyinstaller
powershell -ExecutionPolicy Bypass -File build.ps1
```

Genera `server/dist/SC-Companion-Server.exe` y `SC-Companion-Setup.exe`.

## Instalación para usuarios

Ver [README-INSTALL.txt](README-INSTALL.txt).

## Limitaciones

- Star Citizen no tiene API de estado de nave, así que la app no puede mostrar si algo está encendido o apagado.
- Las teclas por defecto siguen mi configuración; hay que ajustarlas si tus atajos son otros.
- El servidor necesita ejecutarse como administrador para que el juego reciba las teclas.

Proyecto personal, sin relación con Cloud Imperium Games.
