# Walkthrough - Monitoreo de 5 Minutos y Captura RAW IMU

Se han implementado mejoras críticas en la autonomía de la aplicación, la resolución temporal y la captura de datos de alta frecuencia.

## Cambios Realizados

### 1. Resolución y Autonomía
*   **Intervalos de 5 Minutos:** Se actualizó todo el sistema (modelos, proveedor y servicio de fondo) para agrupar los datos en bloques de 5 minutos. Esto permite una monitorización mucho más detallada frente a la medicación.
*   **Corrección de Notificación:** Se corrigió el nombre del icono en la configuración del `ForegroundService`. Ahora aparecerá la notificación "Emkiwear Activo" en la barra de estado, garantizando que Android no cierre el proceso.

### 2. Captura de Datos RAW IMU (50 Hz)
*   **Consumo de Característica:** La app ahora se suscribe a la característica `7A9B0007`.
*   **Decodificación:** Se parsean los 16 bytes de datos crudos (Acelerómetro y Giroscopio) con precisión de milisegundos.
*   **Subida por Lotes (Batching):** Se implementó el `RawUploadService` que acumula 250 muestras (aprox. 5 segundos de datos) y las sube a **Firebase Storage** como un archivo CSV.
*   **Ubicación en Firebase:** Los archivos se guardan en `raw_imu/{userId}/{sessionId}/{timestamp}.csv`.

### 3. Control de Flujo (CMD)
*   Se añadieron controles en la interfaz (icono de analítica en la barra superior) para activar/desactivar la captura de datos RAW.
*   Al activar/desactivar, la app envía los comandos `0x03` (reanudar) o `0x02` (pausar) al canal CMD de la ESP32 para ahorrar batería cuando no se requiere análisis profundo.

### 4. Sincronización Automática
*   Se reforzó la lógica de `_checkAutoUpload`. Ahora, en cuanto se completa un bloque de 5 minutos (ej. pasamos de las 10:04 a las 10:05), la app sube el resumen anterior inmediatamente sin esperar intervención humana.

## Verificación
*   Se verificó la consistencia de los IDs determinísticos: `usr_fecha_hora_minuto`.
*   Se utiliza `Isolate` (vía Foreground Task) para asegurar que la inicialización de Firebase sea independiente en el proceso de fondo.

> [!IMPORTANT]
> Ejecuta `flutter pub get` antes de lanzar la app para instalar `flutter_foreground_task` y `path_provider`.
