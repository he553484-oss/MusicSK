# Musicsk 1.4 · candidato de estabilización

La rama `musicsk/1.4-development` parte del build 5 de 1.3 (`0ef9b68`). `main` y `musicsk/1.3-stability` siguen disponibles para volver atrás. El commit `abbb28e` no apareció en los objetos ni en los respaldos locales. GitHub respondió HTTP 422 al consultarlo en MusicSK. [Cambios desde 1.3](https://github.com/he553484-oss/MusicSK/compare/musicsk/1.3-stability...musicsk/1.4-development)

## Diagnóstico y correcciones

| ID | Evidencia | Cambio y verificación |
| --- | --- | --- |
| M14-01 · crítico | Biblioteca carga Replay. Si el archivo del mes actual contiene dos filas con el mismo ID, `ListeningStore.OpenBucket.from` aborta. El ejecutable de prueba con el código de 1.3 salió con 132 y `Fatal error: Duplicate values for key`. Sin el informe `.ips` del iPhone, la relación con el cierre reportado queda pendiente. | `ListeningStore` agrega las sesiones por ID y conserva los metadatos disponibles y la fecha de reproducción más reciente. El caso verifica una sola pista, 60 segundos, dos reproducciones, portada y fecha. También se ejecutaron los casos anteriores de Replay. |
| M14-02 · alta | Replay calculaba los agregados al construir el `@State` y al aparecer. Cuando el historial estaba vacío, el banner repetía ambos pasos. | `ReplayHeroSection` carga una vez por aparición y cambio de titular. El banner muestra la misma invitación de estado vacío. El diagnóstico conserva etapa, cantidad y estado, sin incluir cuentas, pistas, URLs ni rutas. |
| M14-03 · alta | El registro `quality-start` consultaba la salida de Rust incluso durante Dolby en AVFoundation. La pantalla de diagnóstico ocultaba los metadatos Dolby y mostraba contadores Rust. | El diagnóstico identifica el renderer activo. La frecuencia de `AVAudioSession` se informa aparte del formato negociado por Rust. En Dolby se usan los metadatos leídos por AVFoundation, con su salida gestionada por el sistema. El panel reserva los contadores y la captura PCM para Rust. |
| M14-04 · alta | El teatro medía el marco del vídeo y los mandos juntos dentro del área segura y después pedía ignorarla para todo el grupo. Cada movimiento del slider también emitía una orden de salto. | `VideoTheaterView` mide el vídeo hasta los bordes y mantiene los mandos en las áreas seguras. Conserva la proporción con `VideoSurface` en modo ajustado. La previsualización del salto sigue el dedo y el salto se aplica al soltar. El teatro comparte el reproductor visual silenciado y el reloj del audio. |
| M14-05 · por verificar | 1.3 ya tiene `MPVolumeView`, volumen interno independiente, una superficie inmersiva compartida y publicación nativa de carátulas compatibles. La ausencia de una portada o un vídeo en el dispositivo puede depender del recurso, la cuenta, la política de iOS o la sesión. | Se conservaron esas rutas. Los casos de estado de vídeo, volumen y Now Playing pasan en las comprobaciones disponibles. La salida física, el bloqueo y el vídeo activo necesitan una prueba en dispositivo. |

## Recorrido de audio

1. `PlaybackController+SourceResolution` acepta archivos locales y descargas o pide un stream al resolver de Kotlin/InnerTube. La calidad elegida condiciona la solicitud y la selección de formato. El resultado disponible puede diferir del solicitado. Las descargas parciales se exponen al decodificador conforme llegan los datos.
2. `PlaybackController+Loading` activa `AVAudioSession`, obtiene la frecuencia negociada y pasa fuente, características y configuración de salida al `PlayerEngine` de UniFFI antes de iniciar la pista. Un archivo local y un stream corriente entran al mismo motor Rust. Dolby compatible con URL autorizada y sin cabeceras privadas en la petición de AVFoundation toma la rama `AppleDolbyRenderer`.
3. En Rust, `decode` usa Symphonia, el adaptador libopus o el decodificador AAC nativo cuando se selecciona. El mixer lee PCM, convierte de frecuencia con libsoxr cuando la salida lo requiere y aplica los efectos habilitados y compatibles con la ruta. El ring buffer abastece al callback CoreAudio. La ruta bit-perfect que requiere exclusividad es de macOS.
4. `PlaybackController+Preferences` configura ganancia, normalización, EQ, transiciones y efectos del motor. `MPVolumeView` modifica el volumen de salida que permite iOS. La ganancia de la app sigue disponible en los ajustes de audio.
5. La comprobación de macOS pasa un WAV por el motor compilado y observa posición, nivel de muestras, salida, conversión y estado del procesado. Otra prueba abre WAV y ALAC de 24 bits a 96 kHz. Estas comprobaciones se distinguen de la calidad acústica, de las pruebas de red de YouTube Music y del funcionamiento en iPhone.

El [inventario de 1.3](MUSICSK-1.3.md) sigue vigente. Este candidato mantiene Kotlin, Rust, los proveedores de letras, los estilos Musicsk y BitChord, la cola, los adaptadores de cuentas, las descargas y el widget. Now Playing conserva MediaPlayer en iOS anteriores a 27 y MediaSession desde iOS 27. Los clips animados siguen condicionados a un recurso compatible, sus políticas de accesibilidad y el comportamiento de iOS.

## Correspondencia Auden → Musicsk

Se auditó la fuente de Android en `d53ae77`. El proyecto declara GPLv3. Un port deberá conservar la atribución y el código fuente correspondiente. [Auden auditado](https://github.com/Yahel0506/Auden/tree/d53ae77e8a0c482ecf9037fa2ab29261511bd931)

| Fuente Compose | Vistas y servicios en iOS | Comportamiento que debe implementarse en la edición |
| --- | --- | --- |
| `MainActivity.kt`, `GlassNavBar.kt`, `MiniPlayer.kt` | `RootView`, `AppModel`, `PlaybackPill` | Barra y mini agrupados, estado expandido y contraído en scroll, gestos de cola y conservación de historial de navegación. Las dos ediciones leerían el mismo `PlaybackController`. |
| `HomeScreen.kt`, `ExploreScreen.kt`, `SearchScreen.kt` | `HomeView`, `ExploreView`, `SearchView`, `FeedLoader`, `InnertubeFeed` | Composición híbrida con música en dispositivo, secciones de recomendaciones y estados realistas con y sin cuenta, sin catálogos ficticios. |
| `LibraryScreen.kt`, `LibraryPhoneParts.kt`, `LibraryBanners.kt` | `LibraryView`, `LocalLibrary`, `DownloadStore`, `PlaylistPinning` | Replay arriba, rejilla de hasta seis listas fijadas en tres columnas, enlaces de categorías editables, grupos por carpeta y género y conservación de listas offline. Los adaptadores Room y MediaStore de Android requieren equivalentes sobre datos iOS. |
| `NowPlayingScreen.kt`, `LandscapePlayer.kt`, `MusicVideoPlayer.kt` | `NowPlayingView`, `VideoPlayback`, `LyricsPane`, `PlaybackController` | Matriz de layouts, composición de portada y paneles, transiciones y mandos de la edición. El audio, la posición, el vídeo silenciado y las letras siguen siendo servicios compartidos. |
| `DetailScreen.kt`, `SettingsSheet.kt`, `Theme.kt` | `DetailView`, `SettingsView`, catálogos de traducción y accesibilidad de iOS | Tratamiento de álbumes y artistas, jerarquía de ajustes, tipografía y persistencia de la edición desde Apariencia. |

El código de Auden incluye dependencias de datos exclusivas de Android. Su port visual debe partir de comportamientos y datos reales que puedan mantener las dos ediciones. La entrega de estabilización deja el selector y ese port pendientes de cerrar la validación crítica.

## Validación e instalación

| Comprobación | Resultado | Entorno |
| --- | --- | --- |
| Archivo del mes actual con IDs duplicados | FAIL en 1.3 y PASS en 1.4 | Ejecutable Swift con la implementación de cada versión y datos sintéticos persistidos. |
| Replay, descarga de páginas, vídeo, letras, cola, recuperación, Now Playing y contratos de volumen | PASS | Pruebas ejecutables y comprobaciones de código en Linux. Las pruebas de páginas usan un adaptador SHA-256 de OpenSSL fuera del proyecto. |
| TTML | PASS | 17 casos JUnit en Kotlin. |
| Verificador de IPA | PASS | 17 casos de empaquetado válidos e inválidos. |
| Biblioteca real, YouTube Music con y sin cuenta, vídeo activo, AirPlay, botones físicos, Control Center, bloqueo y widget instalado | NOT TESTED | Requieren el dispositivo, la fuente activa y las rutas de salida. |
| Fluidez, CPU, GPU, consumo y latencia en iPhone | BLOCKED | Instrumentación física pendiente. |

El artefacto de GitHub Actions se crea en macOS con el flujo **Release → build-ios**, versión `1.4.0`, rama `musicsk/1.4-development`. Usa las XCFrameworks del proyecto, iOS mínimo 18, app `app.musicsk.player` y widget `app.musicsk.player.widget`. La verificación del archivo inspecciona estructura, binarios e identidad. [Flujo de compilación](https://github.com/he553484-oss/MusicSK/actions/workflows/release.yml)

Para repetir la compilación en macOS desde la rama indicada, con Xcode 27, XcodeGen, CMake, JDK 21 y Rust instalados:

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios
NATIVE_TARGETS="aarch64-apple-darwin aarch64-apple-ios" scripts/build-native-core.sh
CONFIG=release scripts/build-shared-framework.sh
xcodegen generate --spec AppleApp/project.yml
scripts/package-ios-ipa.sh 1.4.0 --output-dir build/release
shasum -a 256 build/release/Musicsk-1.4.0-build6-ios-unsigned.ipa
```

Para instalar, descarga y descomprime el artefacto. Selecciona `Musicsk-1.4.0-build6-ios-unsigned.ipa` en **My Apps → +** de AltStore o SideStore y fírmala con tu cuenta. Usa las mismas asignaciones de firma al actualizar para conservar los datos. El widget requiere el App Group en la app y la extensión. El archivo se genera para instalación sin JIT ni jailbreak.

En iPhone 15 Pro, abre Biblioteca tras actualizar con una biblioteca existente y prueba también después de iniciar sesión y cambiar de cuenta. Si se cierra, busca el `.ips` de Musicsk en **Ajustes → Privacidad y seguridad → Análisis y mejoras → Datos del análisis** y exporta el diagnóstico de la app para comparar la traza con `ListeningStore`. Repite la secuencia portada → vídeo → Letras → vídeo, abre el teatro y arrastra el progreso. Verifica audio local y YouTube Music, cola, volumen físico, AirPlay o Bluetooth, portada y controles en bloqueo o Control Center. Comprueba el registro `quality-start` por fuente y ruta y contrasta las peticiones de calidad con el formato recibido. Para medir cortes, latencia, memoria o consumo, utiliza el mismo dispositivo, pista y ruta en 1.3 y 1.4.
