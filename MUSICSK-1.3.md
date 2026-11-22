# Musicsk 1.3.0 — estabilidad y validación

## Base auditada

El punto de partida es `2c3c6ae` de `musicsk/1.2.1-hotfix`. GitHub Actions archivó ese mismo commit como 1.2.1 build 4, con iOS 18 como mínimo. [Archivado de la base](https://github.com/he553484-oss/MusicSK/actions/runs/45052421229)

| Referencia | Hallazgos de la comparación |
| --- | --- |
| BitChord Apple `9c20ef3` | `HeroArtwork` compone carátula, vídeo y máscara de desvanecimiento en una sola región. El port ya trae un reproductor visual silenciado separado del audio. Las letras originales usaban peso fuerte, énfasis fijo, una interpolación de escala y una curva de seguimiento definida. |
| Musicsk 1.0 `a83e698` | Conserva `HeroArtwork`. Introduce identidad y empaquetado propios y controla la lectura manual de letras. |
| Musicsk 1.1 `9336e74` | Añade publicación de portadas animadas nativas y conserva el vídeo en `HeroArtwork`. Sus transiciones compactas siguen usando la presentación modal de esa versión. |
| Musicsk 1.2 `80072df` | Adopta el cover nativo y mueve una única carátula entre anclas. En compacto coloca el vídeo en una capa distinta que omite la parte común de la máscara original. Añade comprobaciones de generación, sincronización de letras y verificación de la IPA. |
| Musicsk 1.2.1 `2c3c6ae` | Extiende la portada por detrás de la barra de estado. El vídeo mantiene explícitamente el marco anterior con relleno arriba. El karaoke distingue el inicio real de palabra, el fin explícito y el solapamiento entre voces. |

Los diffs entre estas referencias dejan los directorios `shared`, `native-core` y `vendor` intactos. El volumen a través del motor, los diagnósticos de audio y los contratos de navegación se revisaron por separado de las diferencias visuales. [Historial del hotfix base](https://github.com/he553484-oss/MusicSK/commits/musicsk/1.2.1-hotfix/)

## Arquitectura e inventario funcional

| Área | Recorrido auditado | Funciones preservadas |
| --- | --- | --- |
| Vistas y navegación | `RootView`, `NavigationStack`, `PlaybackPill`, `NowPlayingView`, `DetailView`, `SettingsView` | Inicio, Explorar, Biblioteca, búsqueda, historial, listas, álbumes, artistas, ajustes y menús. Minirreproductor, pantalla completa, zoom nativo y áreas seguras del hotfix. |
| Audio | `PlaybackController`, `AudioSessionManager`, UniFFI `PlayerEngine`, `native-core/src/{engine,mixer,output,decode}` | Cola, avance y retroceso, gapless, crossfade, ecualizador, ganancia de la aplicación, normalización, Dolby Atmos, audio espacial, Automix y salida bit-perfect compatible. |
| Vídeo | `VideoPlayback`, `VideoSideController`, `VideoSurfaceState`, `VideoSurface`, AVFoundation y AVKit | Reproducción de vídeo en el reproductor, modo teatro, PiP donde iOS lo permite y selección explícita de otra versión de la canción. La cola y el reloj permanecen en el controlador de audio. |
| Catálogo y cuentas | `AuthController`, Keychain, `PageSession`, `InnertubeSearch`, `InnertubeDetail`, `SourceResolver` e InnerTubeX | YouTube Music con o sin cuenta, perfiles y cuentas, descargas y catálogo, resolución de fuentes, módulos configurables y bibliotecas WebDAV. |
| Música local y almacenamiento | `LocalLibrary`, `DownloadStore`, `StreamFileCache`, `LastPlayed` | Selección de carpeta, metadatos locales, descargas, reproducción offline, caché de audio con manifiesto y restauración de cola y ajustes. |
| Letras | `LyricsBridge` y analizadores Kotlin, `LyricsClock`, `PreparedLyrics`, `LyricTimingIndex`, `LyricsPane` | Proveedores, subtítulos y alineación disponibles, sincronización por línea o palabra, fragmento compacto, traducción, desfase y tarjetas para compartir. |
| Pantalla de bloqueo | `NowPlayingController`, `NowPlayingLifecycle`, `NowPlayingArtworkLoader`, `CanvasFileCache` | Cambios de pista, tiempos, carátula estática, clips compatibles, mandos remotos y metadatos en segundo plano. MediaPlayer en sistemas anteriores y MediaSession a partir de iOS 27. |
| Rendimiento y concurrencia | `PageRequestCoordinator`, cachés de arte, actor `StreamFileCache`, tareas de precarga y decodificador visual | Particiones de sesión, solicitudes coalescentes, cachés acotadas, descarga y arte de respaldo. El vídeo y los efectos de letras se evalúan según sus estados de presentación. |
| Widget y servicios | `WidgetStatePublisher`, `Widget/BitChordWidget.swift`, App Group, App Intents y Handoff | Widget y acciones, entrega entre dispositivos, Listen Together, Discord Rich Presence, Last.fm y ListenBrainz. Los resultados del widget dependen de la firma y del App Group. |
| Localización y distribución | `Localizable.xcstrings`, `AppleApp/project.yml`, Rust/Kotlin XCFrameworks, flujo Release | Español e inglés, mínimos de iOS 18 y macOS 15, app y widget arm64, distribución sin firma para re-firmar, avisos GPLv3 y licencias de terceros. |

El inventario enumera rutas y funciones comprobadas en código. La matriz distingue las que además se ejercitaron.

## Registro de problemas

| ID | Severidad | Reproducción y evidencia | Corrección y prueba |
| --- | --- | --- | --- |
| M13-01 | Alta | En el marco compacto, alternar portada, vídeo y Letras. Los diffs de 1.2 y 1.2.1 confirman que el vídeo perdió la máscara compartida y conserva el marco previo a fullscreen. | Portada y vídeo comparten marco y máscara. Los botones se mantienen dentro del área segura. Las pruebas verifican geometría, exclusión de tramas antiguas y formatos verticales. |
| M13-02 | Alta | Activar vídeo para una toma que no se puede alinear. El camino de resolución podía decidir el cambio de toma musical. `readyToPlay` tampoco asegura que la capa ya tenga un fotograma visible. | La capa espera el primer fotograma tras sincronizarse con el reloj de audio. El controlador conserva su AVPlayer silenciado y libera el recurso al ocultar la última superficie. Otra toma requiere pulsar **Reproducir versión de vídeo**. |
| M13-03 | Alta | El slider fullscreen escribe `PlaybackController.volume`, que aplica una curva cúbica al motor. Los botones físicos modifican el volumen de salida. | `MPVolumeView` visible en iOS y lectura de `AVAudioSession.outputVolume` para el icono. La ganancia sigue en controles de salida. `check-system-volume.sh`. |
| M13-04 | Alta | Una carga de portada A puede terminar tras A → B → A. El identificador y la URL por sí solos coinciden aunque la carga pertenezca a la primera selección. Un arte embebido inválido también puede suprimir el respaldo remoto. | Revisar identidad de la solicitud, selección, recurso y publicación. Probar cambios rápidos y rendimiento del respaldo. |
| M13-05 | Media | Varias notificaciones de categoría o configuración pueden repetir el retorno desde Bluetooth. La ruta anterior persistía y cada recuperación podía reofrecer la mejora. | La oportunidad se conserva mientras termina la recuperación y se consume una vez. La prueba cubre rutas vacías, cambios rápidos y repeticiones. |
| M13-06 | Media | Una mutación de biblioteca llama al coordinador con una partición. En la base el coordinador cancela también solicitudes de otras particiones. Las solicitudes ignoraban `force` y podían permanecer vivas al cancelarse el último consumidor. | Separar invalidación, generaciones y consumidores. Probar cancelación, recargas y finalizaciones tardías. |
| M13-07 | Media | Los checks heredados de calidad de stream y ruta fallaron en build 4. `5b56e72` renombró la fila a «Requested Source Quality» y la cancelación vive en `PlaybackController+QualityUpgrade.swift`. | Se comprueba la distinción entre preferencia y medición y se refuerza la prueba de la oportunidad de ruta. PASS local. |
| M13-08 | Media | El aspecto y el movimiento original de BitChord difieren de los estilos 1.0–1.2.1. La base ofrece preferencias globales de letras, sin selector de estilo. | Añadir tres presentaciones y preferencias locales. Verificar que el reloj, el analizador y la selección de proveedor son compartidos. |
| M13-09 | Pendiente de confirmar | El reporte de portada animada en pantalla de bloqueo no especifica versión, origen o recurso. La API depende de los formatos aceptados y de iOS. | Verificar primero portada estática, mandos y segundo plano. Probar después un Canvas conocido, una pista sin clip y otra con vídeo musical. |

La captura de «Sangre» citada en la solicitud no estaba entre los archivos disponibles del turno. El caso se conserva como prueba física de seguimiento del reporte.

### APIs del sistema

El slider de iOS usa la vista pública de MediaPlayer que gestiona la ruta y los botones físicos. La ganancia de Musicsk continúa en Salida de audio. [MPVolumeView](https://developer.apple.com/documentation/mediaplayer/mpvolumeview)

La app publica carátulas estáticas con MediaPlayer en iOS 18–26. En iOS 26, las variantes animadas solo se ofrecen si el sistema anuncia su clave y la app puede entregar la imagen de previsualización y el archivo local asociado. En iOS 27 la sesión moderna publica y arbitra los metadatos. El vídeo musical convencional sigue siendo una superficie visual de AVFoundation. [MPMediaItemAnimatedArtwork](https://developer.apple.com/documentation/mediaplayer/mpmediaitemanimatedartwork) · [Claves compatibles](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter/supportedanimatedartworkkeys)

La preparación del archivo de vídeo y la aparición de un fotograma en una capa son eventos distintos. La geometría de la carátula y el reloj de audio pueden seguir disponibles durante ambos. [AVPlayerLayer.isReadyForDisplay](https://developer.apple.com/documentation/avfoundation/avplayerlayer/isreadyfordisplay)

## Configuración de letras

La ruta es **Configuración → Letras → Estilo de letras**. El selector y la vista previa usan la misma presentación que el reproductor. La vista previa usa un ejemplo silencioso. La canción sigue usando su reloj, su proveedor y sus marcas de tiempo.

| Estilo | Presentación |
| --- | --- |
| Musicsk | Mantiene el foco y el desvanecimiento de build 4, las letras por palabra y el brillo moderado en notas largas. |
| BitChord Original | Recupera del port `9c20ef3` el tamaño y peso de los versos, los márgenes de ambas voces, la escala inactiva, el contraste por distancia y la curva de seguimiento de 400 ms. Conserva el enfoque de 1.2.1 y el espacio estable para pausas instrumentales. |
| Personalizado | Tamaño, grosor, alineación, blur, brillo, opacidad inactiva, suavidad, fondo, iluminación por palabra y reducción de efectos. Los valores se acotan y el restablecimiento afecta únicamente el ajuste personalizado. |

Las preferencias se guardan con claves locales separadas. La preferencia de desenfoque de versiones anteriores sigue aplicándose. Las filas conservan su identidad al cambiar el estilo. Las palabras activas siguen la planificación de SwiftUI, las pausadas e inactivas evitan un reloj de fotogramas propio y el scroll se alimenta del cambio de foco.

## Matriz de verificación

| Área | Resultado local | Alcance |
| --- | --- | --- |
| Letras | PASS | Foco, verso inicial, final explícito, dúos, RTL, manual, geometría, curvas, límites, persistencia y compartición. |
| Vídeo y geometría | PASS | 27 comprobaciones de visibilidad, generación y formato de vídeo. 57 comprobaciones de layout, aspecto y gestos. |
| Volumen | PASS | Prueba de que iOS monta MPVolumeView, observa salida y deja la ganancia accesible. |
| Now Playing | PASS | Lógica de sesión, reloj, cambios A → B → A, identidad de una nueva representación, reserva y política de archivo. |
| Páginas | PASS | Swift 6 con concurrencia estricta y 32 repeticiones. SHA-256 de OpenSSL solo en el adaptador local de pruebas. El runner Apple usa CryptoKit. |
| Audio y cola | PASS | Políticas de ruta, diagnóstico, cola, restauración, transporte, biblioteca local y recuperación de stream. |
| Analizador TTML | PASS | 17 casos JUnit en Kotlin. |
| Distribución | PASS | Verificador de la estructura de IPA, 17 casos. El estado del archivado se registra aparte. |
| Cuenta, rutas físicas, mandos, widget y sistema | NOT TESTED | Funcionamiento en iPhone con fuentes, cuenta, ruta y firma reales. |
| Captura activa de vídeo, letras con pista y PiP | NOT TESTED | El protocolo físico usa la misma pista y proveedor en ambos builds. |
| CPU, GPU, temperatura, energía y ProMotion | BLOCKED | Falta un iPhone conectado a Instruments. El benchmark en Mac, cuando está disponible, solo mide la decodificación de una muestra. |

Los archivos Swift se comprueban en Linux con destino iOS y macOS para detectar errores sintácticos. Ese paso precede a la compilación con SDK Apple y al lanzamiento en simulador. Los casos de autenticación y proveedores externos dependen de sus servicios y de credenciales de prueba autorizadas.

## Validación en iPhone 15 Pro

1. Guardar número de build, versión de iOS, ruta y origen de cada prueba. Instalar sobre la misma firma para comprobar persistencia. Añadir el widget y abrir el reproductor desde él.
2. Reproducir un archivo local, una pista de YouTube Music como invitado y otra con cuenta. Alternar cuenta, borrar el estado de sesión y volver a iniciar. Verificar que cola, vídeo, mini, búsqueda y descargas siguen operativos.
3. Con «Sangre» de Méne y una pista con vídeo horizontal compatible, grabar la secuencia portada → vídeo → Letras → vídeo. Verificar aspecto, respaldo al esperar el primer fotograma, gesto de cierre, posición y ausencia de una segunda pista de audio. Repetir 20 veces, saltar de canción durante la espera y pasar por bloqueo, segundo plano y suspensión. Repetir con vídeo no alineado y confirmar que la opción explícita de otra toma actúa solo al pulsarla.
4. En altavoz, audífonos, Bluetooth, AirPods y AirPlay disponibles, alternar botones físicos, Control Center y slider diez veces. Comprobar el mismo valor de salida en una ruta ajustable. Confirmar que el ajuste independiente de Volumen de la app y los controles de ecualización conservan su valor.
5. Probar bloqueo y Control Center para archivo local, YouTube Music invitado y cuenta. Pausar, retomar, cambiar de pista y pasar por A → B → A. Comprobar título, duración, avance, portada y mandos. Repetir con un clip de portada compatible, con vídeo musical completo, con batería baja, con Reducir movimiento y sin conexión.
6. Cambiar el estilo de letras durante una palabra larga, al adelantar, durante scroll manual y tras cambiar de proveedor. Repetir con letra por línea, por palabra, dúo, RTL y sin sincronizar. Cambiar cada ajuste personalizado, reiniciar y restablecer. Revisar dinámica, contraste y VoiceOver.
7. Para rendimiento, usar la misma pista, cuenta, ruta, temperatura y brillo en build 4 y build 5. Medir tiempo al primer fotograma, interrupciones, memoria y actividad sostenida visual en Instruments. Grabar al menos una secuencia que incluya minirreproductor, fullscreen, vídeo y Letras. Separar la medición de hardware de la prueba del decodificador y del simulador.

## Instalación y compilación

Descomprime el artefacto de GitHub Actions. Abre `Musicsk-1.3.0-build5-ios-unsigned.ipa` desde **My Apps → +** en AltStore o SideStore. Para conservar datos al actualizar, usa la misma cuenta de firma y las mismas asignaciones del identificador y del App Group.

El proyecto usa `app.musicsk.player` y `app.musicsk.player.widget`. La firma para funcionamiento del widget debe incluir el App Group en app y extensión. [Construir el port en Apple](README.md#build-from-source)

## Integración

Los agentes prepararon cambios en worktrees separados. Integré el volumen de salida y Now Playing del agente A, la superficie de vídeo del agente B, los estilos y la configuración de letras del agente C, el coordinador de páginas del agente D y la compilación y las capturas del agente E. Tras integrar, añadí la deduplicación de la mejora de ruta, la sustitución de lecturas pendientes en una recarga y el fondo de letras de iOS. [Commits de la candidata](https://github.com/he553484-oss/MusicSK/commits/musicsk/1.3-stability/)
