# Musicsk 1.0

## Auditoría inicial

Base inspeccionada: `9c20ef3` de `bagumamartin/BitChord`. El proyecto XcodeGen de `AppleApp` genera una app y una extensión WidgetKit multiplataforma. El mínimo es iOS/iPadOS 18 y macOS 15. El workflow original selecciona Xcode 27 para enlazar MusicUnderstanding débilmente. SwiftUI presenta la UI, BitChordShared (Kotlin Multiplatform) conecta servicios y NativeCoreFFI (Rust) mantiene el motor de audio.

| Área | Implementación encontrada | Cambio previsto |
| --- | --- | --- |
| Navegación | RootView utiliza TabView, pilas y destinos tipados de BrowseDestination. Los menús de acciones usan componentes nativos. | Conservar las rutas y el comportamiento del sistema. Limitar animaciones propias a cambios visibles y ajustarlas a Reducir movimiento. |
| Reproductor | PlaybackPill y RootView ya enlazan la hoja de iPhone con la transición de zoom del sistema. El cover de ancho regular descarta con un gesto que solo actúa al soltar. NowPlayingView monta otra pila dentro de la pila del reproductor. | Reutilizar la interacción nativa del iPhone, dar seguimiento al dedo en ancho regular y unificar el alojamiento de rutas para evitar reinicios superfluos. |
| Letras | LyricsPane usa el reloj existente y LyricsRows ya distingue versos y palabras reales. | Ajustar el seguimiento, cancelar el movimiento pendiente al desplazar a mano y mantener marcas y proveedores. |
| Inicio, biblioteca y búsqueda | Hay contenedores perezosos, caché de portadas, estados de carga y paginación existentes. | Intervenir en los puntos de coste o movimiento excesivo detectados en el código. |
| Rendimiento | Existen capas Core Animation para barras y marquesina, procesamiento de audio fuera de la UI y un modo de frecuencia sostenida opcional. | Aprovechar el planificador de pantalla del sistema y conservar el modo opcional. |

Revisé README, APPLE_RELEASES, LICENSE y THIRD_PARTY_NOTICES. El port está bajo GPLv3 y mantiene avisos adicionales, entre ellos los de Orchard, libsoxr, Sparkle, el solver de YouTube y las traducciones. Las afirmaciones anteriores describen el código existente. La ejecución de las funciones del port requiere validación en Apple.

No encontré capturas de referencia de movimiento en los archivos versionados. No pude observar Apple Music en un iPhone desde el entorno Linux. La referencia orienta el comportamiento general. La paridad visual y temporal requeriría una comparación directa en el dispositivo.


## Identidad

Musicsk usa la versión 1.0.0 (build 1). La app y el widget del proyecto compartido usan `app.musicsk.player` y `app.musicsk.player.widget`, con el App Group `group.app.musicsk.player`. Esta identidad también se aplica a la compilación de Mac. El esquema URL registrado es `musicsk` y la actividad Handoff es `app.musicsk.playback`. Los enlaces de Listen Together se convierten al formato del cliente compartido al entrar a la capa Kotlin. Los módulos BitChordShared y NativeCoreFFI, los créditos y las licencias siguen identificados por sus nombres originales.

Una instalación firmada con identidad propia puede convivir con BitChord. Los datos y credenciales de BitChord quedan en su contenedor, por lo que Musicsk requiere iniciar sesión por separado. Las actualizaciones usan un repositorio Musicsk configurado durante el build. Sparkle requiere el feed y la clave pública propios de esa publicación.

## Cambios de movimiento

- **Motion Core.** Separamos el fundido de los paneles, la apertura de los controles y el retorno de un arrastre. Reducir movimiento desactiva el zoom propio del reproductor, el desplazamiento de marquesinas y la contracción de portada al pausar. La extracción de los colores del fondo se ejecuta en una tarea de utilidad. La app permite que iOS elija frecuencias de pantalla altas cuando están disponibles.
- **Reproductor.** En ancho compacto, SwiftUI controla la transición de zoom y el gesto de cierre de la hoja. El accesorio tapado por el teclado en iOS 26.0 cede el identificador de la transición a la píldora visible. La presentación conserva su modalidad al cambiar de tamaño y una sola pila aloja sus rutas. En ancho regular, el tirador mueve la vista en coordenadas globales durante el arrastre. La proyección al soltar decide entre cerrar y retornar. La portada grande puede dibujar primero la miniatura que ya está en memoria mientras se resuelve su tamaño definitivo.
- **Letras.** El seguimiento se suspende durante el contacto, el desplazamiento y la deceleración. Un temporizador cancelable vuelve al verso activo al quedar en reposo. La lista monta filas de forma perezosa. En pausa, buscar otra posición actualiza el verso sin un reloj periódico. Se conserva el barrido continuo de palabras reales; con Reducir movimiento el mismo progreso cambia la opacidad de cada palabra. Se conservan las marcas, formatos y proveedores existentes.
- **Navegación.** Inicio y Biblioteca montan las secciones al acercarse a la ventana visible. Los carruseles conservan los destinos y el ajuste nativo. La paginación mediante puntero lee la posición cuando sus controles están visibles. Los filtros de búsqueda cambian de inmediato y la animación se aplica al estilo del botón. El campo de iPad usa las finalizaciones de SwiftUI para coordinar el teclado.

## Generar e instalar Musicsk.ipa

En un Mac Apple Silicon, selecciona **Xcode 27** con las herramientas de línea de comandos y el SDK de iOS. Instala XcodeGen, JDK 21, Rust mediante rustup, CMake y las utilidades de empaquetado de macOS. Desde la raíz de esta rama:

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim
NATIVE_TARGETS="aarch64-apple-darwin aarch64-apple-ios" ./scripts/build-native-core.sh
CONFIG=release ./scripts/build-shared-framework.sh
xcodegen generate --spec AppleApp/project.yml
./scripts/package-ios-ipa.sh 1.0.0
cp build/release/Musicsk-1.0.0-build1-ios-unsigned.ipa build/release/Musicsk.ipa
```

Archiva para iPhone con la firma del desarrollador desactivada. El empaquetador comprueba el ejecutable, el widget, ambos identificadores y la ausencia de perfiles incrustados. Abre `build/release/Musicsk.ipa` desde **My Apps** en AltStore o SideStore y usa el flujo habitual de firma del dispositivo. Para actualizar, conserva el mismo equipo y el identificador que asignó el firmador. El objetivo mínimo es iOS 18. La app tiene sus frameworks embebidos y el empaquetado usa el flujo de una app nativa sin JIT.

El App Group debe coincidir en los perfiles de la app y la extensión para publicar estado y recibir comandos del widget. Si el firmador permite instalar la extensión sin el grupo, el widget usa su estado vacío y conserva el enlace para abrir la app. Las funciones de sincronización entre dispositivos requieren sus capacidades de iCloud. El inicio de sesión y los datos se guardan en el contenedor propio de Musicsk. El soporte efectivo de cada capacidad depende del equipo y del firmador.

Para publicar desde un fork, configura `MUSICSK_RELEASE_REPOSITORY` con `propietario/repositorio`. Sparkle usa `MUSICSK_SPARKLE_FEED` y `MUSICSK_SPARKLE_PUBLIC_KEY` en el build. El workflow construye el feed `musicsk-appcast.xml` con `SPARKLE_ED_PRIVATE_KEY` y su clave pública correspondiente. Consulta LICENSE y THIRD_PARTY_NOTICES antes de distribuir binarios y conserva el código fuente correspondiente y los avisos de terceros.

## Verificación

- Swift 6.2.4 en Linux analizó la sintaxis de los Swift modificados con objetivos arm64 iOS 18 y macOS 15. Las pruebas ejecutables de geometría del reproductor pasaron los 41 casos, incluidos cinco casos nuevos del gesto. También pasaron los controles de sesiones, transporte, cola, recuperación, pacing de transiciones, sincronización y habilitación de vídeo, fuentes y orden local.
- Kotlin 2.4.10 y JUnit ejecutaron `scripts/check-ttml.sh`. Pasaron los 17 casos.
- Pasaron las comprobaciones de menús, ajustes, audio y validación de identidad, revisiones y checksums de artefactos. El manifiesto se probó con fixtures.
- `check-quality-log.sh` (fila de calidad declarada), `check-lossless-route.sh` (reoferta al recuperar una ruta con cable) y `check-lyrics.sh` (contrato estático de la tarjeta de letras) fallaron en el mismo punto en el commit base y en Musicsk. El último se detiene antes de las consultas a proveedores.
- El empaquetado se detuvo en `xcodebuild is required`. El wrapper Gradle recibió `Connection refused` al descargar Gradle 9.7.1. Linux tampoco puede generar los frameworks Apple. No se generó una IPA.

Quedan pendientes el type-check y archive con Xcode, la firma e instalación en iPhone y la prueba integral de la reproducción de YouTube Music, login, descargas, bloqueo, widgets y demás funciones que requieren Apple o servicios activos. En iPhone 15 Pro conviene registrar el ciclo abrir, arrastrar, cancelar y cerrar, cambiar de pista o de pestaña durante la presentación, comprobar la reanudación de letras y medir animación y CPU con Instruments. No hubo comparación directa con Apple Music ni medición de FPS.
