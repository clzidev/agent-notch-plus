# Agent Notch Plus

[🇬🇧 English](README.md) | **🇪🇸 Español**

Tus agentes de IA, viviendo al lado del notch de la MacBook. **v2.9.39**

[![Última versión](https://img.shields.io/github/v/release/clzidev/agent-notch-plus?label=release&color=00c98f)](https://github.com/clzidev/agent-notch-plus/releases/latest)
[![Descargar DMG](https://img.shields.io/badge/⬇_Descargar-AgentNotchPlus.dmg-00c98f)](https://github.com/clzidev/agent-notch-plus/releases/latest/download/AgentNotchPlus.dmg)

## 📦 Descarga

No hace falta compilar nada — bajate el instalador listo:

1. **[Descargar AgentNotchPlus.dmg](https://github.com/clzidev/agent-notch-plus/releases/latest/download/AgentNotchPlus.dmg)** (universal: Apple Silicon + Intel, macOS 12+)
2. Abrí el DMG y arrastrá **AgentNotchPlus** a **Aplicaciones**
3. Primera vez: **click derecho → Abrir** (la app está firmada ad-hoc, sin notarizar), o permitila en Ajustes del Sistema → Privacidad y seguridad

Cada versión se publica en la [página de Releases](https://github.com/clzidev/agent-notch-plus/releases) con notas bilingües (EN/ES). ¿Preferís compilar desde el código? Mirá [Compilar y ejecutar](#compilar-y-ejecutar).

> Fork de [realfishsam/agent-notch](https://github.com/realfishsam/agent-notch) — todo el crédito por el concepto, diseño e implementación originales es de su autor. Este fork agrega un atajo de teclado global, apertura al pasar el mouse y un panel de ajustes con mascotas GIF animadas personalizables. Mirá [Qué agrega este fork](#qué-agrega-este-fork).

Mientras **Claude Code** o **Codex** trabaja, su mascota camina al lado del notch — el bichito del banner de Claude Code para Claude, la mascota oficial de Codex para Codex. Cada agente tiene su lugar: apenas uno termina, su mascota se convierte en una burbuja verde (aunque el otro siga trabajando). El verde es un aviso de "terminó desde la última vez que miraste" — enfocar tu terminal lo limpia. Un click abre un panel con tus sesiones, agrupadas por prompt, con cada subagente plegado bajo un desplegable.

<p align="center"><img src="docs/indicator.gif" width="520" alt="La mascota de Claude Code y la de Codex caminando junto al notch" /></p>

## El panel

Una fila por sesión, titulada por la herramienta, encabezada por **tu** último prompt — no la charla de los agentes. Los subagentes (el enjambre de filósofos de Codex, los agentes Task de Claude) se pliegan bajo un desplegable `▸ N subagentes`. Las filas en ejecución muestran su mascota caminando en el lugar; las terminadas reciben un tilde verde pixelado. La etiqueta a la derecha es el modelo real que corre esa sesión.

<p align="center"><img src="docs/panel-demo.gif" width="600" alt="Panel de sesiones con mascotas caminando y desplegables de subagentes" /></p>

## Cómo funciona

Sin hooks, sin APIs, sin cuentas. La detección de vida sigue el modelo de [open-vibe-island](https://github.com/Octane0411/open-vibe-island) — *una sesión es un proceso de agente corriendo en una terminal* — consultado cada 3 s:

- `ps` encuentra procesos `claude`/`codex` conectados a una TTY (las sesiones headless o en segundo plano se ignoran)
- `lsof` asocia cada proceso al transcript que mantiene abierto (Codex), o a su directorio de trabajo (Claude Code, que no mantiene abierto el fd del transcript)
- los transcripts aportan la metadata: prompts, fragmentos, modelos, subagentes
  - Claude Code: `~/.claude/projects/*/*.jsonl` (+ `<sesión>/subagents/agent-*.jsonl`)
  - Codex: `~/.codex/sessions/**/*.jsonl`, agrupados por `parent_thread_id`

Dentro de una sesión viva, *ocupado vs. inactivo* es un híbrido: proceso vivo + transcript escrito en los últimos 30 s = ocupado (la mascota camina); vivo pero callado = inactivo (nada en el notch, fila atenuada en el panel); proceso desaparecido por 2 consultas = terminado (burbuja verde). Las sesiones inactivas más de 6 h desaparecen del panel. Activar una app de terminal (Ghostty, Terminal, iTerm2, kitty, Warp, Alacritty) da por vistos los agentes terminados y limpia su indicador verde.

### Limitación conocida: el resplandor de ~30 s

Ocupado/inactivo se infiere de los tiempos de escritura del transcript, y esas escrituras vienen en ráfagas — así que la mascota sigue caminando hasta ~33 s (ventana de 30 s + consulta de 3 s) después de que un turno realmente termina, y a la inversa, los silencios dentro de un turno se suavizan. Ningún indicador a nivel proceso (red, CPU, procesos hijos) puede arreglarlo del todo: solo el agente sabe cuándo termina su turno. La solución precisa serían hooks del agente (`UserPromptSubmit`/`Stop` escribiendo un archivo de estado, como hace open-vibe-island), omitida a propósito acá para mantener el diseño sin configuración y sin hooks. Si el resplandor te molesta, ese es el camino de mejora.

La ventana plegada es transparente y deja pasar todos los clicks salvo la pequeña zona del indicador, así que nunca bloquea menús ni apps debajo. En espacios a pantalla completa la barra ocupa todo el borde superior.

## Qué agrega este fork

- **Atajo global — ⌃⌥N (Control + Option + N)** abre y cierra el panel, sin mouse. Registrado vía Carbon `RegisterEventHotKey`, así que no necesita permisos de Accesibilidad ni de Monitoreo de entrada.
- **Abrir al pasar el mouse** — dejá el cursor sobre el indicador (~0,35 s) y el panel se abre; se cierra cuando el mouse lo abandona. Las aperturas por click o atajo quedan fijas hasta que las cierres.
- **Panel de ajustes** — click derecho en el indicador (o en el panel abierto) → *Configuración…*:
  - elegí la mascota de Codex desde un desplegable (se acabó editar archivos de configuración a mano)
  - poné un **GIF animado propio** por agente que reemplaza su mascota en el notch y en las filas del panel — los GIF de fondo transparente lucen mejor sobre la barra negra
- **Responder a los agentes desde el notch** — activá el hook de Claude Code desde los ajustes (un click; agrega hooks `Notification`/`Stop`/`UserPromptSubmit` a `~/.claude/settings.json`). Cuando un agente pregunta algo o pide permiso, aparece una tarjeta naranja en el panel con el mensaje y un campo de respuesta — escribí y apretá ↩. Las respuestas a una sesión que corre **dentro del terminal del notch** se escriben directo a su shell (exacto, sin permisos). Las respuestas a **terminales externas** (Warp, Ghostty…) requieren activar "Responder a terminales externas" y el permiso de Accesibilidad — macOS bloquea la vía segura y dirigida (TIOCSTI), así que esas respuestas se inyectan como teclas en la ventana enfocada, con la salvedad de ventana-equivocada que eso implica.
- **Panel estilo centro de control con tarjetas** — cada sesión es una tarjeta con mascota, agente + proyecto, modelo + antigüedad, tu prompt y una línea de estado de color (verde = trabajando, naranja = esperándote, terminado ✓); la tarjeta activa lleva un borde de acento. Una barra de cabecera suma botones rápidos de ajustes/terminal y un resumen de sesiones.
- **Zoom al pasar el mouse** — con el panel abierto, pasarle el mouse lo agranda un porcentaje configurable (25% por defecto); la letra no cambia de tamaño pero los fragmentos se reacomodan en 2-3 líneas reales llenando el ancho extra, así que leés *más* texto. Vuelve a achicarse cuando el mouse se va.
- **Todos los atajos son configurables** — el del panel, el del terminal, y las teclas ⌘ internas del terminal para dividir / panel de archivos / carpetas rápidas.
- **El panel de carpetas rápidas se sincroniza con el shell en ambos sentidos** — navegar el panel hace `cd` en la terminal, y escribir `cd` en la terminal mueve el panel (el cwd real del shell se lee del kernel ~1×/s); una fila ".." arriba sube un nivel.
- **Edición con selección en el terminal** — seleccioná texto con el mouse, ⌘C/⌘X lo copia y ⌘V pega, sin barra de menú.
- **Liviano en recursos** — las colas de los transcripts se cachean por mtime (solo se releen los archivos que cambiaron en cada consulta de 3 s), y el indicador solo se repinta mientras algo se anima de verdad.
- **Terminal del notch** (atajo configurable, ⌃⌥Espacio por defecto) — una terminal de verdad ([SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)) que se despliega desde el notch como una cortina y se enrolla al ocultarse, con sus shells siempre corriendo. Es parte del notch: no se puede mover, y redimensionar desde cualquier borde la agranda simétricamente, siempre centrada bajo el notch. **⌘D** la divide en hasta 3 panes lado a lado. Prompt minimalista estilo matrix — `proyecto rama ❯` dentro de un repo git, un `❯` pelado en cualquier otro lado, con cursor de bloque verde parpadeante (tu `~/.zshrc` se sigue cargando, colores intactos). Arrastrá archivos encima para tipear sus rutas entre comillas, y elegí su carpeta inicial en los ajustes (cae a `/` si la carpeta desaparece). **⌘F** muestra un panel embebido estilo Finder, totalmente independiente de las terminales: barra lateral con ubicaciones estándar más tus favoritos fijados (arrastrá una carpeta encima), columnas de nombre/fecha/tamaño, selección múltiple, **Espacio para Vista Rápida**, ⌘C/⌘V, doble click abre archivos, y todo se arrastra afuera como archivos reales — a las terminales o a cualquier lado de macOS. El panel de archivos tiene su propia carpeta inicial en los ajustes (ej.: la terminal abre en `~/Code` y ⌘F en `~/Descargas`); si no la fijás, usa la de la terminal.
- **Las sesiones inactivas siguen visibles** — un agente vivo pero callado muestra su mascota atenuada y estática en vez de desaparecer del notch. Corré `claude` o `codex` en una pane y contestá sus confirmaciones directo desde el notch. `exit` cierra una pane, ✕ fuerza el cierre de todo aunque un shell esté colgado.
- **Mascotas emoji animadas — sin API, sin cuenta** — una galería desplazable de 60 [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/) (GIFs chicos de fondo transparente servidos por el CDN público de Google). Buscá por nombre (EN/ES), un click reemplaza al instante la mascota de Claude o Codex; otro click restaura la original. Descargar estos emoji es el único acceso a red de la app.
- **Sonidos** (opcionales, apagados por defecto) — una campanita cuando un agente termina (Glass) y cuando se queda esperando tu respuesta (Ping). Como máximo una vez por episodio de actividad.
- **Interfaz bilingüe** — inglés/español, seleccionable en ajustes (por defecto, el idioma del sistema).
- **App de verdad** — `scripts/build-app.sh` produce `AgentNotchPlus.app` (ícono, entrada en Launchpad, sin ensuciar el Dock) con un interruptor de **Abrir al iniciar sesión** en los ajustes (`SMAppService`).
- La configuración vive en `~/.config/agent-notch/` (`pet`, `claude-gif`, `codex-gif`, `lang`, `zoom`, `term-hotkey`, `sound-done`, `sound-attention`; los emoji descargados van a `gifs/`) y se relee cada 3 s, así que los cambios aplican en vivo.
- Los spritesheets de la mascota de Codex ahora se resuelven relativos al binario (con la ruta original hardcodeada como respaldo), así que la app funciona desde cualquier ubicación del clon.

## Mascota de Codex

La animación de Codex usa los spritesheets oficiales de Codex Pets (en `pets/`). Cambiá de mascota con:

```sh
echo dewey > ~/.config/agent-notch/pet
```

Opciones: `codex`, `dewey`, `fireball`, `rocky`, `seedy`, `stacky`, `bsod`, `null-signal`. Aplica en un par de segundos, sin reiniciar. (Spritesheets © OpenAI, de su CDN público de pets.)

## Compilar y ejecutar

Como app normal (recomendado — ícono en Launchpad, soporte de abrir al iniciar sesión):

```sh
./scripts/build-app.sh
cp -R build/AgentNotchPlus.app /Applications/
open /Applications/AgentNotchPlus.app
```

Después activá **Abrir al iniciar sesión** desde el panel de ajustes (click derecho en el indicador → Configuración). Si cerrás la app, reabrila desde Launchpad/Spotlight.

Para compartirla, generá un **DMG universal** (Apple Silicon + Intel, solo necesita las Command Line Tools):

```sh
./scripts/make-dmg.sh   # → build/AgentNotchPlus.dmg
```

Nota: la app está firmada ad-hoc y sin notarizar (eso requiere un Apple Developer ID pago). Quien descargue el DMG debe hacer click derecho → Abrir la primera vez, o permitirla en Ajustes del Sistema → Privacidad y seguridad.

O como binario pelado:

```sh
swift build -c release
cp .build/release/AgentNotchPlus AgentNotch
./AgentNotch &
```

(La primera compilación descarga [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) vía Swift Package Manager.)

- **Click** en el indicador → abre el panel. Click en cualquier lado → lo cierra.
- Para iniciar con la sesión: Ajustes del Sistema → General → Ítems de inicio → agregá `AgentNotch`.
- Requiere macOS 12+ (compilada y probada en una MacBook con notch; en pantallas sin notch se centra sobre un notch virtual).

## Créditos

- **[realfishsam](https://github.com/realfishsam)** — autor del [agent-notch](https://github.com/realfishsam/agent-notch) original, que es todo el núcleo de este proyecto (licencia MIT, conservada intacta en [LICENSE](LICENSE)).
- **[open-vibe-island](https://github.com/Octane0411/open-vibe-island)** — el modelo de detección de vida por procesos que sigue el original.
- **OpenAI** — los spritesheets de Codex Pets en `pets/` (© OpenAI, de su CDN público de pets).
- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** de Miguel de Icaza — el emulador de terminal embebido en el terminal del notch (MIT).
- **Google** — los [Noto Animated Emoji](https://googlefonts.github.io/noto-emoji-animation/) usados como mascotas opcionales (Noto Emoji, licencias OFL/Apache por Google Fonts).
- La mascota caminante de Claude está dibujada con los caracteres de bloque del banner de arranque de Claude Code.
