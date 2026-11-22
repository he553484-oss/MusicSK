# Musicsk 1.2.0

## Auditoría previa

La rama `musicsk/1.2-ultimate-fix` parte de `9336e7494cea75995caab6774f909801e7dfc700`. GitHub Actions confirma ese SHA para el [archivo 1.1.0 build 2](https://github.com/he553484-oss/MusicSK/actions/runs/44986765528). Se comparó con Musicsk 1.0 (`a83e698`) y el port BitChord (`9c20ef3`). La interfaz y los adaptadores de Apple están en `AppleApp/Sources`. Kotlin entrega catálogo, sesión de cuenta, letras y resolución de fuentes. Rust hace la reproducción y el procesamiento de audio. El proyecto produce los frameworks y la app mediante XcodeGen y Xcode 27. El deployment target sigue siendo iOS 18.

| Área | Hallazgo previo a los cambios | Riesgo |
| --- | --- | --- |
| Now Playing | El backend exclusivo de MediaSession en iOS 27 era anterior a 1.1. La rama 1.1 añadió leases, relojes y claves de portada. `UIBackgroundModes` declara `audio`. La activación lee `mix_with_other_audio` y la publicación tiene sus propias condiciones de elegibilidad. | Confundir una pérdida de titularidad del sistema con un fallo de metadatos. Registrar dos backends haría competir las sesiones. |
| Portadas | La resolución Canvas usa metadatos del catálogo. La capa nativa necesita un archivo local con forma admitida y puede recibir HLS o una imagen estática como entrada del catálogo. | El inicio de sesión, un cambio de portada, un caché frío y una pista sin animación pueden producir el mismo síntoma. |
| Letras | 1.1 aplica un recorte a la fila ya desenfocada y un margen de dibujo al renderizador. El componente compacto obtiene un `String` de la línea activa, sin marcas por palabra. Los paneles compactos se reemplazan con fundidos consecutivos. | Cambiar ancho, altura o identidad durante seguimiento puede provocar clipping y saltos. La corrección debe conservar el reloj, formato y tiempos del proveedor. |
| Reproductor | En ancho compacto se monta una hoja grande con radio 24. En regular se monta un cover. | Cambiar el contenedor altera el gesto de cierre, el área segura y la navegación interna. |
| Álbum y artista | El álbum de iOS usa un ancho acotado con una máscara redondeada. La foto del artista tiene otro tratamiento, con acciones y título fuera de la imagen. | Cambiar la cabecera puede afectar visibilidad del vídeo, acciones de catálogo, contraste y accesibilidad. |
| Localización | El catálogo de Xcode conserva el inglés como fuente. Hay claves y frases visibles que requieren español. Parte de los valores se presenta desde código de cliente. | Traducir claves, nombres propios o especificadores de formato rompería la selección de cadenas. |

Se conservaron las referencias recibidas por Drive en 1.1. Incluyen letras a 30 fps y capturas de «mosca», Biblioteca y Nsqk. La comparación reproducible usa el mismo verso con tiempos independientes. Las capturas del build nuevo y el renderizado en un iPhone 15 Pro requieren el mismo contenido. Los originales quedan fuera del código fuente.

El integrador asignó archivos en seis worktrees. Sistema posee la integración Swift de reproducción. Letras posee scroll, render y snippet. Reproductor posee el contenedor, la geometría y la transición compartida. Detalle posee `DetailView` y sus pruebas. Localización posee el catálogo y sus pruebas. QA posee el workflow, empaquetado y verificación del artefacto. Los cambios entran en ese orden.

## Referencias y reproducción de las regresiones

La captura nueva de Musicsk 1.1 («7-3», 590 × 1280 px) muestra la hoja debajo de una franja negra de aproximadamente 89 px. Las esquinas redondeadas y el tirador separan visualmente la vista del área superior. El verso activo de varias líneas empieza alrededor de x=33 px. En varios renglones inactivos alineados a la derecha se pierden caracteres al llegar al borde. También se ve una línea inactiva detrás de la cabecera. La captura verifica esos síntomas. El recorte izquierdo del verso activo y la ausencia de controles nativos se reportaron por separado.

- **Geometría del reproductor.** Abrir desde la píldora, comprobar continuidad del fondo hasta las áreas de sistema y recorrer apertura, arrastre, inversión, cancelación y cierre. Repetir al abrir la letra directamente, con Rotación y Reducir movimiento.
- **Letras.** Reproducir «7-3» con el mismo proveedor. Recorrer texto largo y corto, alineación de duetos, idiomas de derecha a izquierda, emojis, pausas instrumentales y palabras mantenidas. Repetir al adelantar, retroceder y cambiar de tema. Revisar el borde superior y ambos márgenes.
- **Vídeo comparable.** Para «Te dejo de estorbar», usar como inicio 25,000 s en Apple Music y 14,000 s en la grabación de Musicsk 1.0. Elegir el mismo momento vocal de cada nuevo vídeo. El script conserva tamaño, relación de aspecto, tiempos independientes y hash de origen. La tasa de 30 fps de las referencias solo describe esos archivos.
- **Álbum y artista.** Comparar la continuidad superior con «mosca» y Nsqk. Repetir con arte blanco, oscuro y saturado, Dynamic Type, Alto contraste y Reducir transparencia. Las fotos y metadatos disponibles pueden diferir entre catálogos.
- **Now Playing.** Desde una sesión sin otra app de audio, alternar música local, YouTube Music sin sesión y YouTube Music con sesión. Pausar, reanudar, saltar, bloquear, abrir Control Center, cambiar de aplicación y conectar o desconectar audífonos. Después repetir con otro audio activo y con la opción de mezclar habilitada. Probar una portada animada conocida, una estática, cambio entre ambas, caché caliente, pérdida de red, Bajo consumo y Reducir movimiento.

Vuelve a generar las hojas desde capturas del mismo dispositivo antes de evaluar proporciones o velocidad. Las comparaciones calculadas a partir de código no sustituyen el renderizado ni la interacción. [Comparaciones de origen](MUSICSK-1.1.md#comparación-reproducible)

## Instalación

La IPA de Release conserva `app.musicsk.player` y `app.musicsk.player.widget`. Descarga el artefacto de GitHub Actions, descomprime el ZIP y selecciona la IPA desde **My Apps** en AltStore o SideStore. Si actualizas una instalación, conserva la misma identidad del firmador y el mismo equipo para mantener los datos.

Para compilar en un Mac Apple Silicon con Xcode 27, XcodeGen, JDK 21, Rust, CMake y Python 3:

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios
NATIVE_TARGETS="aarch64-apple-darwin aarch64-apple-ios" ./scripts/build-native-core.sh
CONFIG=release ./scripts/build-shared-framework.sh
xcodegen generate --spec AppleApp/project.yml
./scripts/package-ios-ipa.sh 1.2.0
shasum -a 256 build/release/Musicsk-1.2.0-build3-ios-unsigned.ipa
```

## Cambios integrados

| Fase | Causa o condición verificada | Implementación y alcance de la prueba |
| --- | --- | --- |
| A · Sistema | El valor implícito de mezclar audio modificaba la categoría de sesión sin una elección expresa. Los cambios repetidos podían reiniciar un intento pendiente de publicar Now Playing. Una pausa o cambio de velocidad sin posición explícita reutilizaba un ancla anterior. | `AudioSessionManager` conserva la preferencia guardada. `NowPlayingLifecycle` conserva la espera de reintento. `NowPlayingController` toma una posición estable al cambiar el ritmo. La suite reproduce esos estados con un reloj y sesiones controladas. |
| A · Portadas | La identidad de la búsqueda omitía el origen y el ID de la pista. Un resultado tardío podía aplicarse con datos anteriores. El caché exigía una extensión de vídeo y no identificaba algunos archivos con URL firmada. | `PlaybackController+Canvas`, `QueueEntry`, `StreamFileCache` y `NowPlayingArtwork` validan la identidad, consultan el álbum como respaldo y conservan la extensión de un contenedor admitido. Se preservan la imagen estática y el tratamiento de HLS. Las pruebas del contenedor no reproducen vídeo real. |
| B · Letras | El recorte de fila afectaba los píxeles que el desenfoque dibujaba fuera de su marco. El adelanto compacto convertía el verso a texto plano. | `LyricsRows`, `LyricsPane`, `LyricsPresentation` y `NowPlayingView+Lyrics` acotan el ancho para ambas voces, reservan los márgenes del efecto, recortan verticalmente frente a la cabecera y comparten reloj y marcas temporales con el snippet. Las pruebas verifican anchura, renglones, texto RTL, enfoque, avance y recuperación del seguimiento tras la inercia. |
| C · Reproductor | Una hoja de tamaño grande dejaba una franja y esquinas visibles. El cambio a letras intercambiaba paneles y portadas. | `RootView` usa una presentación nativa de pantalla completa. `NowPlayingView+Layouts`, `PlayerArtwork` y `PlayerLayout` conservan el área de controles y mueven una portada entre dos marcos medidos en orientación compacta vertical. La apertura y el cierre de la presentación siguen siendo nativos. Las pruebas de geometría validan márgenes y decisión de cierre. |
| D · Detalle | Una cabecera acotada con máscara aislaba arte y texto en Álbum. El Artista separaba nombre e imagen. | `DetailView` y `DetailHeaderLayout` extienden las cabeceras en iOS, mantienen proporciones del vídeo admitido y dan contraste constante a los textos superpuestos. Las pruebas verifican anchos, alturas, proporciones, acciones y cambio de barra al desplazar. |
| E · Español | Faltaban traducciones en el catálogo y algunos valores dinámicos evitaban la búsqueda localizada. | `Localizable.xcstrings` y las vistas de Ajustes amplían cobertura de 134 a 372 claves con español. Se comprobó la equivalencia de los especificadores de los 241 registros editados. El inglés sigue siendo el idioma fuente. |
| F · Release | El empaquetado no validaba íntegramente el archivo antes de publicarlo como IPA. | `scripts/package-ios-ipa.sh` y `scripts/verify-ios-ipa.py` comprueban ZIP, app, widget, ejecutables arm64, iOS 18, audio en segundo plano y ausencia de perfiles. Se comprueba también SHA-256 al empaquetar. El flujo de simulador captura el binario en español cuando puede ejecutarlo. |

El análisis de código identifica causas corregidas. Para bloqueo y Control Center falta reproducir la pérdida de titularidad en el dispositivo. Los caminos de archivo local y streaming comparten la publicación. Las pistas de catálogo descargadas conservan su identidad de catálogo. La sesión de YouTube Music y las cookies de autenticación permanecen en su flujo existente. El motor Rust, Kotlin, los proveedores y las licencias conservan el código de la base.

## Matriz de validación

| Comprobación | Estado | Evidencia |
| --- | --- | --- |
| Forma del reproductor, anclas de portada y decisión de cierre | PASS | 51 comprobaciones de Swift con las funciones de producción. |
| Cabecera de álbum y artista | PASS | Prueba de geometría de producción y comprobación de acciones preexistentes. |
| Karaoke y snippet | PASS | Anchura de ambas voces, altura reservada, renglones RTL, reloj y brillo, seguimiento manual e inercia. Alcance de lógica y geometría. |
| TTML | PASS | 17 pruebas JUnit sobre el analizador Kotlin existente. |
| Exportación de fragmentos de letras | PASS | Comprobación de código de las reglas de compartir. |
| Now Playing y portadas | PASS | Prueba de reloj, pausa, cambio de identidad, cancelación, reintentos y tipo de contenedor compatible. |
| Cola, restauración de sesión y recuperación de stream | PASS | Pruebas de lógica de Swift. |
| Transporte, archivos locales, ajustes de audio y menús | PASS | Pruebas de lógica y contratos de código. |
| Español e inglés | PASS | El catálogo se analiza y los formatos de las claves editadas se conservan. La inspección de todas las pantallas queda aparte. |
| Swift iOS y macOS | PASS | Análisis sintáctico de los archivos editados en Linux, con los destinos de Apple. |
| Verificador IPA | PASS | 17 pruebas positivas y negativas del formato y los metadatos. |
| Aserciones de registro de calidad y recuperación de ruta cableada | FAIL | Dos comprobaciones heredadas fallan también en la base 1.1. |
| Suites con un .app de macOS, CryptoKit o BitChordShared | BLOCKED | El entorno local es Linux. No dispone del ejecutable, SDK ni framework de Apple. |
| Audio local, YouTube Music con y sin sesión, cola y audífonos | NOT TESTED | Falta ejecutar la matriz funcional completa en iPhone. |
| Control Center, pantalla bloqueada, controles remotos, audio en segundo plano | NOT TESTED | Falta iPhone físico. |
| Portadas animadas en iOS, vídeo, caché, ausencia de red, Bajo consumo | NOT TESTED | Falta iPhone físico y medios compatibles confirmados. |
| Clipping renderizado, karaoke con ambos formatos y gesto durante reproducción | NOT TESTED | Falta repetir la grabación del mismo contenido en iPhone. |
| Álbum, artista, Biblioteca y Búsqueda con datos reales | NOT TESTED | Falta repetir las capturas con el catálogo. |
| Dynamic Type, VoiceOver, Reducir transparencia y alto contraste | NOT TESTED | Falta revisión interactiva. |
| Instruments, memoria, carga GPU y ProMotion | BLOCKED | Linux carece de Instruments y no hay iPhone conectado. No se midieron FPS. |

Aún se deben comprobar la continuidad al abrir desde el minirreproductor y la transición en orientación horizontal. En compacto vertical la portada se transforma durante el cambio entre reproductor y letras. Las letras, los recursos por catálogo y la pantalla de bloqueo siguen sujetos a la disponibilidad del proveedor y a decisiones de iOS.
