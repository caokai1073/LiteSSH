<div align="center">

<img src="assets/icon.png" width="140" alt="Ícono de LiteSSH">

# LiteSSH

**Cliente SSH nativo para macOS — terminal, explorador de archivos y transferencia entre servidores en una sola ventana**

[Descargar](#descargar) · [Características](#características) · [Inicio rápido](#inicio-rápido) · [Arquitectura](#arquitectura) · [Crear DMG](#crear-dmg)

[English](README.md) · [中文](README.zh.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Español** · [한국어](README.ko.md)

</div>

---

## Descargar

[**→ Descargar la última versión**](https://github.com/caokai1073/LiteSSH/releases/latest)

Requiere macOS 13 Ventura o posterior. Abre el `.dmg` y arrastra **LiteSSH** a la carpeta Aplicaciones.

---

## Características

| | |
|---|---|
| **Terminal completo** | Impulsado por SwiftTerm, ANSI/VT100 completo — htop, nvtop y vim funcionan sin configuración adicional |
| **Explorador de archivos** | Navegación por profundidad en la barra lateral, barra de direcciones, directorio superior y nueva carpeta |
| **Subir / Descargar** | Arrastra archivos locales para subirlos; haz clic derecho o arrastra elementos remotos para descargarlos — **archivos y carpetas** compatibles |
| **Transferencia entre servidores** | Selecciona varios archivos/carpetas → clic derecho → transferir a otro servidor con progreso en tiempo real |
| **Autenticación PEM / clave privada** | Compatible con contraseña, clave privada y archivos AWS `.pem`. La frase de contraseña se suministra automáticamente desde el Llavero |
| **Credenciales una sola vez** | Introduce la contraseña o frase al agregar el servidor; no se volverá a solicitar en conexiones ni operaciones de archivos posteriores |
| **Interfaz bilingüe** | El idioma sigue la configuración del sistema (chino / inglés) |
| **Modo oscuro / claro** | Los colores del terminal se adaptan automáticamente a la apariencia del sistema |

---

## Inicio rápido

Este es un **Swift Package** puro — no se necesita `.xcodeproj`.

```
1. Abrir Package.swift en Xcode
2. Esperar la resolución de dependencias (SwiftTerm — requiere acceso a github.com)
3. Seleccionar el esquema "LiteSSH" → ▶ Ejecutar
4. Hacer clic en "+" para agregar un servidor — host, puerto, usuario y credenciales, una sola vez
```

---

## Arquitectura

LiteSSH no implementa el protocolo SSH por sí mismo. Delega todo al OpenSSH integrado en macOS (`/usr/bin/ssh`, `/usr/bin/sftp`).

**Reutilización de conexión.** La primera conexión se convierte en ControlMaster. Todas las operaciones de archivos posteriores comparten el mismo socket ControlPath — sin reautenticación.

**Seguridad de credenciales.** Las contraseñas y frases se almacenan en el Llavero de macOS. En tiempo de ejecución, `AskPassHelper` proporciona un script `SSH_ASKPASS` temporal para que el subproceso ssh/sftp obtenga el secreto mediante una variable de entorno — nunca aparece en los argumentos del proceso.

**Transferencia de archivos.** Utiliza `sftp -b <batchfile>` (no scp) para evitar problemas de análisis de rutas con espacios. La transferencia recursiva de directorios usa `get -r` / `put -r`. La transferencia entre servidores pasa por un directorio temporal local.

**Seguridad de pipes.** Ambas tuberías stdout y stderr se leen de forma concurrente mediante `readabilityHandler` durante la ejecución del proceso, evitando el bloqueo por desbordamiento del búfer de pipe de 64 KB.

---

## Estructura del proyecto

```
Sources/LiteSSH/
├── Models/
│   ├── ServerProfile.swift          # Modelo de configuración del servidor
│   └── RemoteFile.swift             # Entrada de archivo remoto
├── Services/
│   ├── SSHConnection.swift          # Núcleo de conexión + gestión de ControlMaster
│   ├── ProcessRunner.swift          # Envoltorio de subprocesos (lectura paralela de pipes)
│   ├── ProfileStore.swift           # Persistencia de configuración
│   ├── KeychainHelper.swift         # Lectura / escritura del Llavero
│   └── AskPassHelper.swift          # Suministro no interactivo de credenciales SSH_ASKPASS
├── ViewModels/
│   ├── SessionStore.swift           # Mapeo Profile → SSHConnection
│   └── FileBrowserStore.swift       # Estado del explorador (ruta + pila de retorno)
├── Views/
│   ├── Sidebar/
│   │   ├── ServerListView.swift     # Barra lateral: lista de servidores + columna explorador
│   │   └── ServerEditView.swift     # Formulario agregar / editar servidor
│   ├── Terminal/
│   │   ├── TerminalContainerView.swift
│   │   └── TerminalViewRegistry.swift
│   ├── Files/
│   │   └── CrossTransferSheet.swift # Interfaz de transferencia entre servidores
│   ├── DetailView.swift
│   └── ContentView.swift
├── Localization.swift               # L10n.s(chino, inglés)
└── LiteSSHApp.swift                 # Punto de entrada @main + AppDelegate
```

---

## Crear DMG

```bash
cd "SSH tool/LiteSSH"
chmod +x build_dmg.sh
./build_dmg.sh
```

Genera `LiteSSH-1.0.dmg` y `LiteSSH.app` en la raíz del proyecto. El script compila el binario en modo release, genera el ícono de la app, firma ad-hoc y empaqueta el DMG con un enlace simbólico a Aplicaciones. Para distribuir a otros equipos, reemplaza la firma ad-hoc por un certificado Developer ID.

---

## Dependencias

| Dependencia | Versión | Rol |
|---|---|---|
| [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) | ≥ 1.0 | Emulador de terminal |
| macOS OpenSSH | Integrado | Protocolo SSH / SFTP |
| macOS Keychain | Integrado | Almacenamiento seguro de credenciales |

**Requisitos:** macOS 13 Ventura o posterior · Xcode 15+ (solo desarrollo)

---

## Licencia

Apache 2.0
