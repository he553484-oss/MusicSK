# MusicSK 1.6 — progreso y límites de verificación

Estado: **trabajo en curso; no es una versión 1.6 terminada**. La base es `musicsk/1.5-project-stability` en `ece24c9`, que conserva el código del build 1.5.0 (commit `7a3c9ec`) y su documentación posterior. El usuario informó que Biblioteca, volumen, presentación del EQ y diagnósticos funcionaban en su iPhone; esta observación no sustituye una prueba de 1.6.

## Cambios y pruebas

- EQ: se ofrece activar Enhanced desde la pantalla de EQ cuando Transparent lo omite; el estado mostrado usa los diagnósticos disponibles del motor. El mezclador ya no informa EQ como activo en Transparent durante la transición de claridad. Se añadió una prueba que mide tonos de graves y agudos en la salida del mezclador real y comprueba el bypass. La primera ejecución falló porque el banco de pruebas no esperaba al decodificador asíncrono; la espera se corrigió y la ejecución posterior es necesaria para validar el resultado. Falta verificar el sonido en un iPhone y demostrar la cadena completa Swift–UniFFI–CoreAudio.
- JioSaavn: se distinguen fallos de acceso, red, servidor, contenido ausente y respuesta inválida, sin mostrar URLs ni credenciales. La tasa solicitada al servicio y el códec no se presentan como datos confirmados en reproducción o descarga. Los comprobadores Swift de respuestas y resolución simuladas pasaron. La red del entorno bloquea el acceso directo; **no se ha demostrado reproducción real ni una reparación del proveedor**.
- Fondo: se conservó el motor existente, con caché de paletas acotada, protección frente a `Int.min`, y respeto de reducir transparencia y condiciones que desaconsejan iniciar movimiento. Se añadieron opciones persistentes de fondo original, portada desenfocada en iOS, degradado estático, color dominante y OLED. No se ha comprobado el aspecto o consumo en dispositivo; los demás controles, perfiles y vista previa del Appearance Lab siguen pendientes.
- Letras: no se modificaron sus componentes internos. Pasaron los comprobadores locales de presentación de letras. También pasaron los comprobadores de historial, orden local, cola y recuperación de streaming; son pruebas automáticas en Linux y no demuestran funcionamiento en un iPhone. Los verificadores previos del primer workflow pasaron en el runner de Apple.
- Compilación: el primer workflow de 1.6, [45439924868](https://github.com/he553484-oss/MusicSK/actions/runs/45439924868), falló en la prueba nueva del mezclador antes de generar la IPA. La prueba se corrigió; la nueva ejecución debe comprobarse. El entorno local no tiene Xcode ni todas las dependencias Rust disponibles sin red.

## Matriz visual

El usuario indicó iOS 27 en iPhone 15 Pro. No se recibieron capturas de referencia ni se dispone de capturas comparables de MusicSK 1.6; por tanto, no se puede afirmar paridad visual ni cuantificarla. Las APIs públicas no permiten controlar todos los materiales de componentes del sistema.

| Pantalla | Estado |
| --- | --- |
| Reproductor | Fondo configurable parcialmente; comparación y verificación pendientes. |
| Cola y minirreproductor | Rediseño y comparación pendientes. |
| Inicio, búsqueda y biblioteca | Comparación pendiente; no se reescribió la lógica de Biblioteca. |
| Menús, álbum, artista y configuración | Comparación y personalización completa pendientes. |

## Pendiente antes de entregar 1.6

Verificar la nueva prueba con el motor, generar e inspeccionar una IPA arm64 del commit correspondiente, probar EQ y JioSaavn con fuentes reales, implementar y validar los hitos visuales y de personalización restantes, y ejecutar regresiones en dispositivo de reproducción, volumen, segundo plano, bloqueo, letras, vídeo, descargas, proveedores, Automix y crossfade. No se ha medido rendimiento gráfico ni demostrado paridad 1:1.
