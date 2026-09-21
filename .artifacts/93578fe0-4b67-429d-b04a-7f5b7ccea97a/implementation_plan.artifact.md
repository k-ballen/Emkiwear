# Plan de Implementación: Almacenamiento Estructurado RAW IMU en Firestore

Este plan detalla la transición del almacenamiento de archivos CSV en Storage a un modelo de datos estructurado en Firestore utilizando el patrón de "Minute-Bucket" con arrays paralelos.

## User Review Required

> [!IMPORTANT]
> Los datos RAW (ax, ay, az, gx, gy, gz) ahora se guardarán directamente en Firestore en la colección `raw_readings`.
> Se agruparán en documentos de 1 minuto para optimizar costos y velocidad de consulta desde la web.
> Cada bloque RAW estará vinculado a su SUMMARY de 5 minutos correspondiente mediante el campo `summaryId`.

## Proposed Changes

### 1. Eliminación de Almacenamiento en Archivos
*   **[DELETE] [raw_upload_service.dart](file:///C:/Users/USER/Documents/Emkiwear-master/lib/services/raw_upload_service.dart)**: Se reemplazará por la lógica de Firestore.

### 2. Nuevo Servicio de Datos Estructurados
*   **[NEW] [firestore_raw_service.dart](file:///C:/Users/USER/Documents/Emkiwear-master/lib/services/firestore_raw_service.dart)**:
    *   Manejar buffers de arrays para los 6 ejes de la IMU.
    *   Implementar la lógica de "corte" cada minuto o al desconectar.
    *   Generar el `summaryId` dinámico para mantener la relación temporal.
    *   Subir el documento a Firestore en la colección `raw_readings`.

### 3. Actualización de Servicios BLE y Proveedores
*   **[MODIFY] [ble_service.dart](file:///C:/Users/USER/Documents/Emkiwear-master/lib/services/ble_service.dart)**: Cambiar la inyección de `RawUploadService` por `FirestoreRawService`.
*   **[MODIFY] [tremor_provider.dart](file:///C:/Users/USER/Documents/Emkiwear-master/lib/services/tremor_provider.dart)**: Instanciar y gestionar el ciclo de vida del nuevo servicio de Firestore.
*   **[MODIFY] [background_service.dart](file:///C:/Users/USER/Documents/Emkiwear-master/lib/services/background_service.dart)**: Asegurar que el monitoreo en segundo plano también use la estructura de Firestore para datos RAW.

## Verification Plan

### Manual Verification
1. Abrir la app y conectar el wearable.
2. Verificar que el icono de analítica esté activo.
3. Esperar al menos 1 minuto de medición.
4. Entrar a Firebase Firestore y verificar la aparición de la colección `raw_readings`.
5. Comprobar que un documento de `raw_readings` contiene los arrays de datos y el campo `summaryId` que coincide con un documento en `tremor_summaries`.
