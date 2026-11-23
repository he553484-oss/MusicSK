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
