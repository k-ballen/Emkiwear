# Plan de Implementación: App Parkinson Care

Esta aplicación está diseñada para pacientes con Parkinson y sus cuidadores, integrando monitoreo continuo a través de wearables y sincronización con Firebase para el seguimiento médico.

## User Review Required

> [!IMPORTANT]
> **Integración con Wearable:** El monitoreo automático del temblor requiere definir el hardware específico o usar APIs estándar como Health Connect (Android) o Apple Health (iOS). En este plan, asumiremos una abstracción para el servicio del wearable.
> **Privacidad de Datos:** Al tratarse de datos de salud, se debe cumplir con normativas locales de protección de datos.

## Propuesta de Arquitectura

Utilizaremos una arquitectura **MVVM (Model-View-ViewModel)** o **Clean Architecture** simplificada para facilitar el mantenimiento y las pruebas.

### 1. Modelos de Datos
Definiremos entidades para:
- `Usuario` (Paciente/Cuidador)
- `Medicamento` (Nombre, dosis, horario, registro de toma)
- `Sintoma` (Rigidez, temblor manual, episodios anormales)
- `EstadoEmocional` (Ánimo, intensidad)
- `Actividad` (Tipo, relación con temblor)
- `Salud` (Ejercicio, digestión)

### 2. Capa de Servicios
- **Firebase Service:** Autenticación y sincronización con Firestore.
- **Wearable Service:** Conexión Bluetooth o integración con APIs de salud para obtener datos de temblor.
- **Notification Service:** Recordatorios de medicamentos y alertas de síntomas.

---

## Cambios Propuestos

### Componente: Infraestructura y Configuración

#### [MODIFY] [pubspec.yaml](file:///C:/Users/USER/Documents/FlutterProjects/mi_primer_app/pubspec.yaml)
Añadir dependencias necesarias:
- `firebase_core`, `cloud_firestore`, `firebase_auth`
- `provider` o `flutter_bloc` para gestión de estado.
- `flutter_local_notifications` para recordatorios.
- `health` o `flutter_blue_plus` para el wearable.

### Componente: Interfaz de Usuario (UI)

#### [NEW] `lib/ui/screens/home_screen.dart`
Pantalla principal con acceso rápido a registros. Diseño con botones grandes y alto contraste.

#### [NEW] `lib/ui/screens/medication_screen.dart`
Gestión de medicamentos y registro de efectos.

#### [NEW] `lib/ui/screens/symptoms_screen.dart`
Registro manual de rigidez y episodios anormales.

#### [NEW] `lib/ui/screens/emotional_screen.dart`
Selector de emojis/colores para el estado de ánimo.

---

## Plan de Verificación

### Pruebas Automatizadas
- Unit tests para el cálculo de metas de ejercicio (150 min/semana).
- Pruebas de mapeo de datos de Firestore.

### Verificación Manual
- Simulación de recepción de datos de temblor desde el wearable.
- Verificación de notificaciones locales para toma de medicamentos.
- Comprobación de que los datos llegan correctamente a Firebase.
