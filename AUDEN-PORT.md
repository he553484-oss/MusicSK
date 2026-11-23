# Auden Edition para Musicsk

## Base y atribución

La base binaria es `ffee2a7ff8718293bb40630283dff55740ce4727`. GitHub Actions documenta el archivado de Musicsk 1.4.0 build 6 en ese commit. La rama incorpora los cambios posteriores de documentación y comprobación en simulador de `musicsk/1.4-development`. `abbb28e` sigue ausente tanto del clon como del API de commits de MusicSK. [Archivado de build 6](https://github.com/he553484-oss/MusicSK/actions/runs/45118654596)

La referencia es Auden GPLv3 en `d53ae77e8a0c482ecf9037fa2ab29261511bd931`, por Yahel0506 y sus colaboradores a partir de BitChord. Se consultaron el módulo de teléfono `app`, los composables comunes de `sharedUi`, los contratos de `shared`, la relación con `native`, los módulos TV, Wear y web, y las dependencias de la biblioteca local de Android. Esta edición usa la tipografía del sistema y SF Symbols de iOS. Los archivos OTF, iconos de marca y vídeos de arranque de Android permanecen en la referencia. [Código y licencia de Auden](https://github.com/Yahel0506/Auden/tree/d53ae77e8a0c482ecf9037fa2ab29261511bd931)

## Correspondencia de componentes

| Auden Compose | Implementación iOS y contrato |
| --- | --- |
| `Theme.kt`, `FrostedTopBar`, `FloatingTabBar` | Paleta adaptable, materiales SwiftUI, SF del sistema y encabezados iOS con áreas seguras y Dynamic Type. |
| `MainActivity.kt`, `GlassNavBar.kt`, `MiniPlayer.kt` | Shell de Auden con cuatro pestañas, navegación de cada página, barra que cambia de dos filas a una, botón de búsqueda y controles conectados al único `PlaybackController`. La expansión usa la transición nativa compatible con la ventana y Reducir movimiento. |
| `HomeScreen.kt`, `ExploreScreen.kt` | Inicio híbrido de archivos locales y recomendaciones. El catálogo de Explorar mantiene los destinos y servicios de Musicsk. |
| `LibraryScreen.kt`, `LibraryPhoneParts.kt`, `LibraryBanners.kt` | Replay y cuadrícula de fijados al comienzo, enlaces editables, acceso a descargas, álbumes, artistas, playlists y fuentes de Musicsk. Room y MediaStore se sustituyen por la biblioteca y descargas iOS existentes. |
| `SearchScreen.kt`, `PillSegmentedControl` | Campo fijo y selector de fuentes. Los resultados, sugerencias, filtros y el historial provienen del buscador existente. |
| `NowPlayingScreen.kt`, `LandscapePlayer.kt`, `MusicVideoPlayer.kt` | Composición Auden del reproductor, con el mismo transporte, vídeo silenciado, teatro, volumen del sistema, cola y motor de letras. El entorno de edición se aplica a la presentación. |
| `DetailScreen.kt`, `SettingsSheet.kt` | Composición y jerarquía iOS de páginas de catálogo y ajustes. Las acciones, rutas y preferencias funcionales conservan sus propietarios actuales. |
| `AudenDb`, MediaStore, DJ Android, sincronización Drive, TV y Wear | Esos servicios y destinos requieren componentes independientes de Android. El port de presentación usa las operaciones y datos que Musicsk ya ofrece. |

El objeto de reproducción, el reloj, la cola y los coordinadores se crean en `BitChordApp`. El selector escribe una preferencia de presentación y el shell cambia las vistas que consumen esos objetos. Las superficies de audio y las sesiones no dependen de la edición.

## Diferencias y alcance

- El plegado reproduce los estados expandido y compacto de Compose. SwiftUI interpola el tamaño y la posición de la misma superficie del minirreproductor en una animación nativa. Queda pendiente igualar y comparar las tres curvas de plegado, anchura y descenso de Android.
- Auden en Android dispone de un índice MediaStore y Room, listas locales y destinos de carpetas y géneros ligados a ese índice. Esta rama muestra el contenido real de `LocalLibrary` y `DownloadStore`, junto con el catálogo y las listas existentes de Musicsk. El límite de fijados sigue siendo el del almacenamiento compartido de Musicsk.
- Las vistas de cola, letras, menús de pista, AVFoundation, volumen y edición avanzada de ajustes se reutilizan con sus acciones. Los contextos de vídeo activo, autenticación, bloqueo, cambios de ruta y gestos físicos requieren una prueba del nuevo build en el iPhone 15 Pro.
- La auditoría comparó layouts, constantes y estados de Compose. La comparación lado a lado con la app Android en ejecución sigue pendiente.

## Verificación

`scripts/check-auden.sh` comprueba el valor predeterminado de edición, la lectura de preferencias, plegado por desplazamiento gradual, tolerancia a pequeñas inversiones, categorías persistidas y geometría del reproductor. En Linux pasaron también las suites locales de vídeo, letras, volumen, Now Playing, rutas, cola, recuperación, Replay, ajustes y menús. El verificador de IPA pasó sus 17 casos de paquete.

El candidato build 8 se archivó con el flujo Release en modo `build-ios`. El modo `capture-ios` abre Original, repite la regresión de Biblioteca de build 6 e intenta reproducir un WAV local sintético antes de cambiar varias veces el mismo binding que usa el selector. Comprueba la generación de reproducción, el identificador de pista, los identificadores de la cola y el avance del playhead Rust. Tras relanzar comprueba la edición persistida. Los argumentos de prueba solo se compilan para el simulador.

| Validación | Resultado |
| --- | --- |
| Regresiones antes del archivado | PASS. 21 suites en Xcode 27.2. |
| IPA de dispositivo | PASS. Build 8 de `c5f665b`, arm64, iOS 18.0 mínimo, app `app.musicsk.player` y WidgetKit. |
| Motor nativo en macOS | PASS. 47 comprobaciones y archivos WAV y ALAC de 24 bits / 96 kHz. |
| Primer ensayo de audio en simulador | FAIL antes del primer cambio de edición en build 7. Original superó la prueba de Biblioteca con historial duplicado. El ensayo del WAV no observó avance de la salida. La primera repetición tampoco produjo el marcador de finalización. En la siguiente ejecución las capturas y la persistencia se verifican antes de iniciar el motor. |
| Paridad visual con Android, bloqueo, vídeo activo y rutas físicas en build 8 | Pendiente de validación en dispositivos. |

El ZIP de GitHub Actions incluye `Musicsk-1.4.0-build8-ios-unsigned.ipa` y `SHA256.txt`. SHA-256 de la IPA `3a6888f5d462e726de988469f07fe25867a871ce3342734c1c9a70280812dbec`. Extrae la IPA y ábrela en AltStore o SideStore desde **My Apps → +**. Conserva la misma firma al actualizar de build 6 para mantener sus datos y vínculos con el widget. [Artefacto de build 8](https://github.com/he553484-oss/MusicSK/actions/runs/45138041693/artifacts/14801229961) · [Log de compilación](https://github.com/he553484-oss/MusicSK/actions/runs/45138041693)
