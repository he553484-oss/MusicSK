# Diferencias visuales de Auden en iOS

La referencia es el código de Auden en `d53ae77`. La comparación siguiente usa geometría y estados del código de Compose, MusicSK build 8 y el nuevo SwiftUI. Para reproducirla con imágenes queda pendiente ejecutar Android y iOS con contenido y condiciones equivalentes. [Matriz de paridad](AUDEN_PARITY_MATRIX.md) · [Historial de build 8](AUDEN-PORT.md)

| Pantalla | Diferencia observada en el código de build 8 | Cambio en la nueva compilación | Diferencia aún abierta |
| --- | --- | --- | --- |
| Reproductor vertical | El diseño Auden invocaba `positionControls`, `playerTransport` y `playerActionRow` de Original. Su centro agrupaba salida, mezcla, vídeo y sesión conjunta. | Transporte y barra propios, medidas de Compose, cambio de pista al deslizar, cola interactiva y salida centrada. | Malla, recorte de vídeo, animación entre canciones y composición horizontal sin comparación de fotogramas. El volumen sigue siendo el nativo de iOS. |
| Cola | Los modos de reproducción sustituían la salida en el dock y conservaban las filas de Original. | Cuatro cápsulas antes de la lista, márgenes de 30 pt, portada actual de 44 pt y la jerarquía de texto de `InlineQueueRow`. | Reordenamiento y gestos de listas SwiftUI. El agrupamiento por origen y AutoPlay todavía difiere. |
| Letras | Auden heredaba el mismo seguimiento y atenuación que los demás estilos. | Escala tipográfica y falloff Auden, scroll adelantado, esqueleto y separadores propios. El resaltado permanece ligado a los tiempos del proveedor. | SwiftUI usa el barrido de MusicSK. El crecimiento de palabras y las animaciones de voces todavía difieren de Compose. |
| Barra y mini reproductor | La transición reducía simultáneamente el bloque en una animación. | Distintos resortes para ancho, posición y navegación. Cápsulas nativas en iOS 26+, material de respaldo para iOS 18 y sólido con Reducir transparencia. | El efecto de unión de Liquid Glass sustituye el shader de Android. La profundidad, la separación en temas claros y el gesto completo necesitan comparación. |
| Catálogo, búsqueda y ajustes | Adaptaciones iniciales de build 8 sobre vistas compartidas. | Comparten el dock refinado. | Pendiente completar cabeceras, tarjetas, hojas, botones, vacíos y errores propios de Auden. |

## Método de comparación en dispositivo

1. Abrir Auden Android en el commit de referencia y MusicSK en la edición Auden. Usar un viewport comparable con 393 pt de ancho en iOS, es-ES, apariencia oscura y escala de texto estándar. Repetir con apariencia clara, Reducir movimiento y Reducir transparencia.
2. Cargar el mismo álbum o archivo y la misma portada. Tomar fotogramas del reproductor en pausa, reproduciendo, con vídeo y durante carga. Marcar límites de arte, créditos y centro de cada control. Normalizar las coordenadas con el ancho útil y las áreas seguras.
3. Para Letras, usar el mismo documento con tiempos por palabra. Comparar el instante anterior al verso, comienzo de la primera palabra, mitad de una palabra larga, final y regreso tras un seek. Registrar la posición del verso por separado del brillo. Incluir dúos, RTL, scroll manual, versos largos y cabecera visible y oculta.
4. Grabar navegación, plegado del dock, apertura y cierre, arrastre parcial, reversión, transición a letras y cola. Comparar trayectorias y respuesta bajo el dedo con fotogramas correlacionados a la entrada.
5. Repetir en iOS 18 y en una versión con Liquid Glass. Capturar un caso de álbum, artista, playlist y búsqueda con resultados. Para rendimiento y lock screen, validar en iPhone 15 Pro.

Las capturas de simulador documentan la versión iOS. El ensayo de playback utiliza un WAV local sintético sin letras ni vídeo, de modo que solo verifica el estado de reproducción y el cambio de edición. Las capturas con la pestaña Letras vacía no acreditan karaoke activo ni paridad. La comparación Android–iOS y las mediciones de ProMotion permanecen pendientes.
