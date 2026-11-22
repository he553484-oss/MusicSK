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

