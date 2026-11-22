# Musicsk 1.1

## Auditoría de 1.0

La rama `musicsk/1.1-apple-parity` parte de `musicsk/1.0` en `a83e698`. La base del port Apple es `9c20ef3`. Los siete commits de 1.0 son `067e4af` (auditoría), `6c4fb5a` (identidad), `096824c` (movimiento), `2c43151` (reproductor), `044875d` (letras), `52c3407` (navegación) y `efc54ff` (validación). `a83e698` añadió el modo de compilación exclusiva para IPA.

| Área | Evidencia en 1.0 |
| --- | --- |
| Letras | `044875d` introdujo `LazyVStack`, seguimiento por fase de scroll, un reloj estático al pausar y énfasis sin desplazamiento para Reducir movimiento. Las pausas instrumentales ya cambiaban de altura en el port. El seguimiento centrado puede competir con cambios de altura y estimaciones de filas. |
| Reproductor | `2c43151` mantuvo el zoom del sistema para ancho compacto, habilitó el arrastre en ancho regular y reutilizó la miniatura. `efc54ff` sostuvo el tipo de presentación durante cambios de ancho. |
| Navegación | `52c3407` hizo perezosas Inicio y Biblioteca y mantuvo los destinos del sistema. `RootView` define Inicio, Explorar, Biblioteca y Buscar en iPhone. |
| Portadas animadas | `606d99d` y los cambios posteriores del port incorporaron Canvas dentro de la app. El historial versionado de `AppleApp` hasta 1.0 no contiene `MPMediaItemAnimatedArtwork` ni las claves animadas. El diff de `NowPlayingController.swift` entre la base y 1.0 solo cambia el identificador del grupo del widget. `PlaybackController+Canvas.swift` queda intacto en ese intervalo. |

El upstream Android fijado en `fe198ac` contiene repositorios Canvas y un reproductor Compose independiente de MediaPlayer. En el port Apple, `CanvasBridge` entrega una URL principal, una fuente y una URL alternativa opcional. El reproductor y los encabezados ya usan estas fuentes según sus ajustes. Los resultados de YouTube Music y las tarjetas de Inicio no traen una variante animada por elemento. La Live Activity en `f21b111` usaba imágenes JPEG. `5de49c4` la sustituyó por la integración nativa de Now Playing, antes de Musicsk 1.0. La evidencia del historial no permite atribuir a 1.0 la desaparición del movimiento en la pantalla bloqueada. La presentación expandida de una portada estática y la reproducción de un vídeo son pruebas distintas.

## Comparación reproducible

Lee primero `LEEME-REFERENCIAS.md` en el ZIP. Conserva los archivos de referencia fuera del repositorio. Anota versión de iOS, modelo, tamaño de texto, preferencias de accesibilidad, orientación, método de sideloading y datos visibles. Usa la misma pista y el mismo proveedor en las dos capturas de Musicsk. Registra dimensiones en píxeles y convierte a puntos usando la escala del dispositivo.

Con Python 3.11+, Pillow 10.1+ y FFmpeg, la herramienta de comparación conserva la relación de aspecto y guarda dimensiones, tiempos solicitados y SHA-256 de los originales en un manifiesto JSON. Los siguientes nombres y tiempos son ejemplos de uso.

```sh
python3 scripts/compare-musicsk-visuals.py referencia-album.png musicsk-album.png \
  --label 'Álbum mosca' --output comparaciones/album.png

python3 scripts/compare-musicsk-visuals.py referencia-letras.mp4 musicsk-letras.mp4 \
  --reference-at 12.40 --musicsk-at 19.15 --count 7 --interval 0.12 \
  --label 'Mismo verso, tiempos independientes' --output comparaciones/letras.png
```

- **Letras.** Identifica la misma aparición del verso y el inicio de una palabra prolongada. Selecciona por separado el tiempo en cada grabación. Repite con 1.0 y 1.1. Revisa altura de filas, línea activa, opacidad y desenfoque por distancia, palabras, pausas instrumentales y retorno tras un arrastre manual.
- **Reproductor.** Captura apertura, arrastre lento, cancelación, inversión y cierre desde el mismo punto inicial. Marca el inicio del gesto en cada video. Examina continuidad de portada, fondo y controles antes y después de soltar.
- **Álbum mosca y artista Nsqk.** Compara altura de cabecera, posición de nombre y acciones, tratamiento de la imagen, primer título de sección y comienzo de la lista. Registra el recurso realmente disponible en cada servicio.
- **Biblioteca y navegación.** Mide columnas, márgenes laterales, espacio del minirreproductor y posición de las pestañas. Repite con una biblioteca vacía y con datos sincronizados.
- **Pantalla bloqueada.** Prueba primero la expansión de portada estática. Graba después una pista con vídeo autorizado compatible, detén la app y vuelve a reproducir. Haz el recorrido animada → animada → estática, pausa/reanuda, pierde la conexión tras cargar la portada y repite en Bajo consumo y Reducir movimiento. Verifica continuidad del audio y de los controles.

Se descargó el ZIP de Drive y se leyó `LEEME-REFERENCIAS.md`. Los seis JPEG de pantallas miden 709 × 1536 px. Los vídeos de letras miden 512 × 1108 px, a 30 fps, y duran 47,700 s y 36,167 s. El recorte de «Te dejo de estorbar» usa Apple Music a 25,000 s y Musicsk 1.0 a 14,000 s. El verso activo aparece cerca del 28 % de la altura visible de la captura en Apple Music y del 41 % en Musicsk 1.0. Musicsk 1.0 también conserva más contraste en versos periféricos. En la grabación de Musicsk, hacia 1,0 y 1,5 s, se ven el texto de letras y la cabecera del reproductor en el mismo fotograma durante el cambio de panel.

| Pantalla | Referencia y estado de 1.0 |
| --- | --- |
| Álbum «mosca» | La referencia usa un campo azul de ancho completo y acciones sobre el mismo plano. La portada cuadrada de 1.0 ocupa cerca de la mitad del ancho y queda separada de los controles. |
| Biblioteca | La referencia muestra tres columnas de portadas seguidas por categorías. En la captura de 1.0 aparecen primero estadísticas y accesos del dispositivo. |
| Artista «Nsqk» | Las dos capturas usan fotografías distintas. La referencia desvanece la foto sobre el fondo. En 1.0 se distingue un corte horizontal cerca de los controles. |
| Navegación | La referencia tiene cinco destinos, incluida Radio. Musicsk tiene cuatro y ofrece Inicio, Explorar, Biblioteca y Buscar. La barra y el accesorio usan APIs nativas. |
| Pantalla bloqueada | El ZIP no contiene su captura ni un vídeo. La descripción del usuario permite identificar una portada expandida. Para verificar movimiento real hace falta un vídeo de un dispositivo compatible. |

Estas comparaciones registran Apple Music y Musicsk 1.0. Las capturas de 1.1, la verificación visual de las transiciones y las mediciones de rendimiento requieren ejecutar la app. Los 30 fps de la fuente no permiten inferir la frecuencia nativa del dispositivo.

## Compilación

```sh
rustup target add aarch64-apple-darwin aarch64-apple-ios
NATIVE_TARGETS="aarch64-apple-darwin aarch64-apple-ios" ./scripts/build-native-core.sh
CONFIG=release ./scripts/build-shared-framework.sh
xcodegen generate --spec AppleApp/project.yml
./scripts/package-ios-ipa.sh 1.1.0
```

Ejecuta estos comandos con Xcode 27 en macOS Apple Silicon. La IPA esperada es `build/release/Musicsk-1.1.0-build2-ios-unsigned.ipa`. El workflow `release.yml` ofrece `build-ios` para compilar únicamente la IPA como artefacto de Actions. La IPA se firma e instala desde AltStore o SideStore. Usa la misma identidad del firmador de 1.0 para conservar la instalación y los datos.


## Cambios integrados y diferencias pendientes

| Área | Cambio en 1.1 | Verificación pendiente |
| --- | --- | --- |
| Letras | Filas medidas con identidad y altura estables, pausas instrumentales con espacio reservado, blur limitado por línea y énfasis que progresa con los timestamps de palabras reales. Se aplaza el fundido de entrada hasta que sale el panel anterior. El pie se desvanece sobre un área de lectura estable. El seguimiento nativo distingue toques, arrastres e inercia. | Capturar los mismos versos en 1.1. Revisar el blur, el brillo, el cambio reverso de panel, Reducir movimiento y los casos de versos largos y duetos. |
| Reproductor | Conserva el zoom del sistema en compacto y un fondo oscuro entre presentaciones. El gesto ancho mantiene la dirección inicial y decide el cierre por posición proyectada. El mini usa coordenadas globales durante el arrastre. | Probar continuidad entre portada, textos y controles, cancelación y rotación en iPhone. |
| Álbum | Tarjeta enmarcada con arte y crédito en composición continua, degradado basado en el recurso disponible y controles separados. A 393 × 852 pt el cuadro de arte calcula 361 × 296 pt. | Comparar recorte y foco del propio arte con las capturas. El marco, los créditos alineados a la izquierda y el grupo de acciones mantienen la identidad de Musicsk. |
| Biblioteca | Cuadrícula adaptable de datos sincronizados o de música real en el dispositivo. A 393 pt usa tres columnas de 108 pt con texto estándar. Categorías y utilidades, incluido Replay, siguen accesibles. | Capturar una cuenta sincronizada y un dispositivo sin datos. La cuadrícula respeta las agrupaciones y el catálogo de Musicsk. |
| Artista | Transición gradual entre foto y fondo, identidad en el borde de la composición, controles separados y conservación de los lanzamientos y Top Songs disponibles. | Verificar contraste y el recorte de la foto del proveedor. La referencia muestra una foto y metadatos distintos. |
| Navegación | Una sola superficie de material por accesorio, sincronización con el teclado y cuatro destinos nativos. | Revisar temas claro y oscuro. La pestaña Radio de la referencia queda fuera del conjunto funcional actual. |

La reproducción y los proveedores mantienen sus módulos Rust y Kotlin. Cambia la publicación Swift de metadatos nativos.

### Portadas del sistema

iOS 26 publica variantes cuadradas o verticales mediante `MPMediaItemAnimatedArtwork` y las claves admitidas por `MPNowPlayingInfoCenter`. iOS 27 usa `NowPlaying.AnimatedArtwork` en su sesión exclusiva de medios, que ya existía antes de 1.0. La disponibilidad de 1:1 y 3:4 depende del dispositivo. La vista previa usa un fotograma del clip elegido. Los callbacks conservan una referencia al archivo local mientras el sistema puede solicitarlo. El reloj nativo interpola el progreso y la app corrige desviaciones, saltos y cambios de velocidad.

El sistema conserva arte estático con una pista que solo tenga foto, una fuente HLS sin variante local compatible, una forma distinta o un modo que limite la animación. Reducir movimiento, Bajo consumo, temperatura, red restringida y preferencias del usuario limitan la preparación y la reproducción. La expansión y el estilo de la pantalla bloqueada corresponden a iOS. El historial confirma que la antigua Live Activity mostraba JPEG y el upstream Android consumía los vídeos Canvas dentro de la app, con una URI estática en los metadatos de Media3. [Documentación de MediaPlayer](https://developer.apple.com/documentation/mediaplayer/providing-animated-artwork-for-media-items) · [Documentación de NowPlaying](https://developer.apple.com/documentation/nowplaying/animatedartwork)

### Pruebas locales

- Swift 6.2.4 ejecutó las suites de geometría, intención del gesto, separación visual y motor de seguimiento de letras, formas de portada, reloj y ciclo de Now Playing. La geometría cubre 51 casos.
- Kotlin 2.4.10 ejecutó las 17 pruebas TTML. Pasaron los controles de menús, ajustes, Handoff y empaquetado de fixtures.
- `check-lyrics.sh --source-only` pasa tras apuntar la aserción RTL al archivo que dibuja la tarjeta. Las pruebas de proveedores en vivo y la suite Canvas con AVFoundation requieren los frameworks Apple.
- Siguen pendientes dos fallos de contratos estáticos heredados y reproducidos en 1.0. `check-quality-log.sh` espera una fila de calidad declarada. `check-lossless-route.sh` espera la reoferta automática al volver a una ruta con cable.
- No hay medición de FPS. Instalar la IPA, iniciar sesión, reproducir YouTube Music y comprobar la pantalla bloqueada requieren un dispositivo. La gestión de portadas de MediaPlayer también requiere una pista compatible con la fuente habilitada.
