# 🧠 Emkiwear Care — App de Apoyo para Pacientes con Parkinson

> Aplicación móvil multiplataforma construida con **Flutter + Firebase**, diseñada para ayudar a personas con Parkinson a monitorear su temblor, gestionar medicamentos, registrar hábitos de vida y conectarse con una comunidad de apoyo. Integra un **asistente de voz con IA** (Gemini via Firebase Vertex AI) para consultas en lenguaje natural.

---

## 📑 Tabla de Contenidos

- [Visión General](#-visión-general-del-proyecto)
- [Arquitectura](#-arquitectura-del-proyecto)
- [Estructura de Directorios](#-estructura-de-directorios)
- [Stack Tecnológico](#-stack-tecnológico)
- [Funcionalidades](#-funcionalidades-principales)
- [Configuración Firebase](#-configuración-firebase)
- [Instalación y Ejecución](#-guía-de-instalación-y-ejecución)
- [Depuración por USB](#-depuración-por-usb-en-android)
- [Solución de Problemas](#-solución-de-problemas)

---

## 🌟 Visión General del Proyecto

**Emkiwear Care** es una aplicación de salud que integra múltiples funcionalidades orientadas al autocuidado de pacientes con enfermedad de Parkinson:

| Módulo | Descripción |
|---|---|
| 📊 **Monitoreo de Temblor** | Graficación en tiempo real de datos recibidos desde un sensor ESP32 vía Firestore |
| 💊 **Gestión de Medicamentos** | Programación de tomas con calendario, confirmación y seguimiento |
| 🍎 **Registro de Hábitos** | Control de alimentación y actividad física |
| 🤖 **Asistente de Voz IA** | Consultas por voz en español procesadas por Gemini (Firebase Vertex AI) |
| 👥 **Comunidad** | Perfiles públicos, grupos de apoyo y lecciones educativas |
| 👤 **Perfil de Usuario** | Datos médicos, especialista, grupo de apoyo y foto |

---

## 🏗️ Arquitectura del Proyecto

El proyecto sigue un patrón **MVVM simplificado** con separación clara de responsabilidades en tres capas:

```
┌─────────────────────────────────────────────────┐
│                    UI Layer                      │
│  ┌───────────────────────────────────────────┐   │
│  │ screens/      →  Pantallas completas      │   │
│  │ theme.dart    →  Estilos globales (Material3)│ │
│  └───────────────────────────────────────────┘   │
├─────────────────────────────────────────────────┤
│                 Service Layer                    │
│  ┌───────────────────────────────────────────┐   │
│  │ firebase_service.dart        → Auth,      │   │
│  │                                Firestore,  │   │
│  │                                Storage     │   │
│  │ voice_assistant_service.dart → Speech,    │   │
│  │                                TTS, Gemini │   │
│  └───────────────────────────────────────────┘   │
├─────────────────────────────────────────────────┤
│                  Model Layer                     │
│  ┌───────────────────────────────────────────┐   │
│  │ activity_habit.dart   ← Hábito de         │   │
│  │                          actividad física  │   │
│  │ food_habit.dart       ← Hábito alimenticio│   │
│  │ medication.dart       ← Medicamento + logs│   │
│  │ medication_task.dart  ← Tarea programada  │   │
│  │ tremor_data.dart      ← Lectura sensor    │   │
│  │                          ESP32            │   │
│  │ user_profile.dart     ← Perfil completo   │   │
│  └───────────────────────────────────────────┘   │
├─────────────────────────────────────────────────┤
│               Firebase Backend                   │
│  ┌───────────────────────────────────────────┐   │
│  │  Firebase Auth      → Email + Google      │   │
│  │  Cloud Firestore    → Base de datos NoSQL │   │
│  │  Firebase Storage   → Imágenes de perfil  │   │
│  │  Firebase Vertex AI → Gemini (IA)         │   │
│  └───────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

### Flujo de Navegación

```
main.dart
  │
  ├─ Firebase.initializeApp()
  │
  └─ StreamBuilder<FirebaseAuth.authStateChanges()>
       │
       ├─ [No autenticado] → LoginScreen
       │      │
       │      ├─ Email/Password → signIn()
       │      ├─ Google         → signInWithGoogle()
       │      └─ "Regístrate"   → RegisterScreen
       │
       └─ [Autenticado] → HomeScreen
              │
              ├─ "Mi Temblor"    → TremorChartScreen
              ├─ "Mi Medicación" → MedicationScreen
              ├─ "Mis Hábitos"   → HabitsScreen
              ├─ "Comunidad"     → CommunityScreen
              └─ "Mi Perfil"     → ProfileScreen
```

---

## 📁 Estructura de Directorios

```
mi_primer_app/
├── android/                          # 🔧 Configuración nativa Android
│   ├── app/
│   │   ├── build.gradle.kts          # Build Gradle (compileSdk=36, minSdk Flutter)
│   │   ├── google-services.json      # ⚠️ Config Firebase (NO compartir)
│   │   └── src/
│   │       ├── main/
│   │       │   ├── AndroidManifest.xml       # Permisos y actividades
│   │       │   ├── kotlin/emkiwear/app/
│   │       │   │   └── MainActivity.kt       # Activity principal (Flutter)
│   │       │   └── res/                      # Recursos nativos Android
│   │       ├── debug/AndroidManifest.xml     # Manifest debug
│   │       └── profile/AndroidManifest.xml   # Manifest profile
│   ├── build.gradle.kts              # Build Gradle del proyecto
│   ├── settings.gradle.kts           # Versiones plugins (AGP 9.1, Kotlin 2.4)
│   ├── gradle.properties             # JVM args, AndroidX
│   └── gradle/wrapper/
│       └── gradle-wrapper.properties # Gradle 9.3.1
│
├── ios/                              # Configuración nativa iOS
│
├── lib/                              # 📌 Código fuente principal (Dart)
│   ├── main.dart                     # Punto de entrada + init de Firebase
│   ├── models/                       # 🗃️ Modelos de datos
│   │   ├── activity_habit.dart       # Hábitos de actividad física
│   │   ├── food_habit.dart           # Hábitos alimenticios
│   │   ├── medication.dart           # Medicamentos + logs
│   │   ├── medication_task.dart      # Tareas de medicación
│   │   ├── tremor_data.dart          # Datos de temblor (ESP32)
│   │   └── user_profile.dart         # Perfil de usuario
│   ├── services/                     # ⚙️ Capa de servicios
│   │   ├── firebase_service.dart     # 🔥 CRUD Firestore + Auth + Storage
│   │   └── voice_assistant_service.dart # 🤖 Voz + Gemini + TTS
│   ├── ui/                           # 🎨 Interfaz de usuario
│   │   ├── theme.dart                # Tema global Material 3
│   │   └── screens/                  # Pantallas
│   │       ├── login_screen.dart     # Inicio de sesión
│   │       ├── register_screen.dart  # Registro
│   │       ├── home_screen.dart      # Menú + asistente de voz
│   │       ├── tremor_chart_screen.dart  # Gráficas de temblor
│   │       ├── medication_screen.dart    # Calendario de medicación
│   │       ├── habits_screen.dart        # Hábitos comidas/ejercicio
│   │       ├── community_screen.dart     # Comunidad y lecciones
│   │       └── profile_screen.dart       # Perfil de usuario
│   └── viewmodels/                   # (Reservado para futuros ViewModels)
│
├── assets/                           # 🖼️ Recursos estáticos
│   ├── logo.png                      # Logo de la app
│   └── google_logo.webp              # Logo Google (botón login)
│
├── test/                             # Pruebas unitarias
├── web/  ├── windows/  ├── linux/  ├── macos/   # Otras plataformas
│
├── pubspec.yaml                      # 📦 Dependencias y assets
├── analysis_options.yaml             # Reglas de análisis Dart
├── .gitignore                        # Archivos ignorados
└── README.md                         # Este archivo
```

---

## 🛠️ Stack Tecnológico

### Framework y Lenguaje

| Componente | Versión |
|---|---|
| **Flutter SDK** | ≥ 3.13.0 |
| **Dart SDK** | ^3.13.0 |
| **Kotlin** (Android) | 2.4.0 |
| **Java compatibility** | 17 |

### Firebase

| Servicio | Paquete | Uso |
|---|---|---|
| Firebase Core | `firebase_core: ^3.3.0` | Inicialización del SDK |
| Firebase Auth | `firebase_auth: ^5.1.4` | Autenticación email + Google |
| Cloud Firestore | `cloud_firestore: ^5.2.0` | Base de datos principal |
| Firebase Storage | `firebase_storage: ^12.1.2` | Almacenamiento de imágenes |
| Firebase Vertex AI | `firebase_vertexai: ^0.2.0` | Modelo Gemini (IA) |

### Dependencias Principales

| Paquete | Versión | Función |
|---|---|---|
| `google_sign_in` | ^6.2.1 | Login con Google |
| `fl_chart` | ^0.68.0 | Gráficas de temblor |
| `table_calendar` | ^3.1.2 | Calendario de medicación |
| `image_picker` | ^1.1.2 | Fotos de perfil |
| `speech_to_text` | ^7.2.0 | Reconocimiento de voz |
| `flutter_tts` | ^4.2.1 | Text-to-Speech en español |
| `permission_handler` | ^11.3.1 | Gestión de permisos |
| `intl` | ^0.19.0 | Formateo de fechas (es_ES) |
| `provider` | ^6.1.2 | Gestión de estado |
| `flutter_local_notifications` | ^17.2.2 | Notificaciones locales |

### Configuración Android Nativa

| Configuración | Valor |
|---|---|
| **compileSdk / targetSdk** | 36 |
| **AGP** | 9.1.0 |
| **Gradle** | 9.3.1 |
| **Google Services Plugin** | 4.5.0 |
| **MultiDex** | ✅ Habilitado |
| **Package / Namespace** | `emkiwear.app` |
---

## ✨ Funcionalidades Principales

### 🔐 Autenticación
- Registro con email y contraseña.
- Inicio de sesión con email o **Google Sign-In**.
- Recuperación de contraseña por correo.
- `StreamBuilder` en `main.dart` escucha `authStateChanges()` y redirige automáticamente entre Login y Home.

### 📊 Monitoreo de Temblor
- Gráfica en **tiempo real** (`StreamBuilder` → Firestore) con datos del sensor **ESP32**.
- Colección Firestore: `tremor_readings` (`intensity`, `timestamp`).
- Gráfica semanal demo con `BarChart` y resumen de intensidad.

### 💊 Medicación
- Calendario interactivo (`table_calendar`) para seleccionar días.
- Programar medicamentos (Levo / personalizados) con hora específica.
- Confirmación de toma con fecha/hora registrada.
- Colección Firestore: `medication_tasks`.

### 🍎 Hábitos
- **Alimentación**: comidas por tipo (Desayuno, Almuerzo, Cena, Merienda).
- **Actividad Física**: tipo, duración e intensidad, con recomendaciones educativas.
- Colecciones Firestore: `food_habits`, `activity_habits`.

### 🤖 Asistente de Voz (IA)
- Captura de voz en español con `speech_to_text`.
- Consultas a **Gemini** (Firebase Vertex AI) con respuesta en streaming.
- Síntesis de voz con `flutter_tts` (velocidad lenta 0.45x para pacientes).
- Integrado en `HomeScreen` con indicador de escucha y chat visual.

### 👥 Comunidad
- Perfiles públicos de otros pacientes (demo + Firestore).
- Pestañas: **Compañeros**, **Grupos**, **Lecciones** educativas.
- Toggle de privacidad (público/privado) que guarda en Firestore.

---

## 🔥 Configuración Firebase

### ⚠️ Archivos Sensibles

Este proyecto incluye un archivo de configuración Firebase que **NO debe compartirse públicamente**:

```
android/app/google-services.json
```

> 🔒 No subas este archivo a repositorios públicos ni lo incluyas en commits compartidos. Ya está ignorado en la mayoría de `.gitignore` de Flutter, pero verifica si tu repo lo admite.

### Si deseas usar tu propio proyecto Firebase:

1. **Crea un proyecto** en la [Firebase Console](https://console.firebase.google.com/).
2. **Habilita los servicios**: Authentication, Cloud Firestore, Storage y Vertex AI.
3. **Registra la app Android** con el paquete `emkiwear.app`.
4. **Descarga `google-services.json`** y reemplázalo en `android/app/`.
5. **Genera el SHA-1** para Google Sign-In (obligatorio):
   ```bash
   # En la carpeta android/ del proyecto
   ./gradlew signingReport
   ```
   Copia el **SHA1** del variant `debug` y pégalo en:
   `Firebase Console > Project Settings > Your app > SHA certificate fingerprints`.
6. En **Authentication > Sign-in method** habilita **Email/Password** y **Google**.
7. Configura las reglas de **Firestore** y el bucket de **Storage** según tu caso.

### Colecciones Firestore Utilizadas

| Colección | Campos principales | Usada por |
|---|---|---|
| `users` | name, email, isPublic, photoUrl, specialist... | Profile, Community |
| `tremor_readings` | intensity, timestamp | TremorChart |
| `medication_tasks` | name, scheduledDateTime, isTaken, userId | Medication |
| `food_habits` | food, mealType, timestamp, userId | Habits |
| `activity_habits` | activityType, duration, intensity, timestamp, userId | Habits |

---

## 🚀 Guía de Instalación y Ejecución

### 1. Requisitos Previos

| Herramienta | Versión mínima | Enlace |
|---|---|---|
| **Flutter SDK** | 3.13.0+ | [Guía oficial](https://docs.flutter.dev/get-started/install) |
| **Android Studio** | Última estable | [developer.android.com/studio](https://developer.android.com/studio) |
| **Android SDK** | API 36 (compileSdk) | Se instala con Android Studio |
| **Java / JDK** | 17 | Incluido con Android Studio |
| **Git** | — | [git-scm.com](https://git-scm.com/) |

### 2. Verificar el Entorno Flutter

```bash
flutter doctor
```

Todos los ítems deben aparecer con ✅. Si `Android toolchain` presenta problemas:

```bash
flutter doctor --android-licenses
```

### 3. Obtener el Proyecto

```bash
git clone <URL_DEL_REPOSITORIO>
cd mi_primer_app
```

### 4. Instalar Dependencias Dart

```bash
flutter pub get
```

### 5. Configurar Android Studio

1. Abre el proyecto: **File > Open** y selecciona la carpeta `mi_primer_app`.
2. Espera a que **Gradle sincronice** (descarga AGP 9.1.0, Gradle 9.3.1, etc.).
3. Verifica los plugins en **File > Settings > Plugins > Marketplace**:
   - ✅ **Flutter** (incluye Dart)
   - ✅ **Firebase** (recomendado)
4. Confirma el SDK de Android en **File > Project Structure > SDK Location**.

### 6. Ejecutar la Aplicación

**Opción A — Android Studio:**
1. Conecta tu celular por USB (con depuración activada).
2. Selecciónalo en el dropdown de dispositivos.
3. Presiona ▶️ **Run**.

**Opción B — Terminal:**
```bash
flutter run
```

**Opción C — Generar APK:**
```bash
flutter build apk --debug
# Resultado: build/app/outputs/flutter-apk/app-debug.apk
```

> 💡 **Consejo**: Con el APK puedes instalar la app en el celular incluso sin Android Studio:
> copia `app-debug.apk` al celular y tócalo para instalarlo (habilita "orígenes desconocidos").

---

## 📱 Depuración por USB en Android

> La depuración por USB permite ejecutar, probar y depurar tu app directamente en tu celular físico desde Android Studio.

### Paso 1 — Activar Opciones de Desarrollador

1. Ve a **Ajustes > Acerca del teléfono (Acerca del dispositivo)**.
2. Toca **7 veces seguidas** sobre **Número de compilación / Build number**.
3. Verás el mensaje: *"¡Ya eres desarrollador!"*.

> 📱 Varía según la marca (Xiaomi: Ajustes > Mi dispositivo > Todas las especificaciones; Samsung: Ajustes > Acerca del teléfono > Información de software).

### Paso 2 — Activar la Depuración USB

1. Entra a **Ajustes > Opciones de desarrollador**.
2. Activa **Depuración por USB (USB debugging)**.
3. Acepta la advertencia de seguridad.
4. *(Opcional)* Activa **Permanecer despierto (Stay awake)** para que la pantalla no se apague durante las pruebas.

### Paso 3 — Conectar el Celular

1. Usa un **cable USB con capacidad de datos** (no solo de carga; idealmente el del cargador original).
2. Conecta el celular al computador.
3. En el celular, acepta el diálogo *"¿Permitir depuración USB?"* marcando **Permitir siempre**.
4. El dispositivo aparecerá en el dropdown de Android Studio.

### Paso 4 — Verificar la Conexión

```bash
adb devices
```

Salida esperada:
```
List of devices attached
XXXXXXXX    device
```

> ⚠️ Si aparece `unauthorized`, acepta el permiso en la pantalla del celular y vuelve a comprobarlo.

### Paso 5 — Ejecutar y Depurar

1. Con el dispositivo seleccionado, presiona el botón **Run ▶️**.
2. Usa **Hot Reload (⚡)** para recompilar instanteáneamente sin reiniciar la app.
3. Coloca **puntos de interrupción (breakpoints)** en el código Dart para inspeccionar variables.

### 🔧 Solución de Problemas de USB

| Problema | Solución |
|---|---|
| Dispositivo no aparece en `adb devices` | Cambia el cable (usa uno de datos). Prueba otro puerto USB. Desconecta y vuelve a conectar. |
| Aparece `unauthorized` | Acepta el diálogo en el celular; en Opciones de desarrollador revoca autorizaciones y repite. |
| Error de controladores en Windows | Instala los [Google USB Drivers](https://developer.android.com/studio/run/win-usb) o los drivers oficiales de tu marca (Samsung, Xiaomi, Motorola…). |
| `Device offline` | Reinicia el servidor ADB: `adb kill-server` y luego `adb start-server`. |
| Celular no conecta | Verifica que el cable soporte **transferencia de datos**. Algunos cables solo cargan. |
| Con Android Studio no lo detecta pero `adb devices` sí | En Android Studio: **File > Invalidate Caches / Restart**. |

---

## 🔧 Solución de Problemas

### Errores de Build Gradle

```
Could not resolve com.google.android.gms or com.google.firebase:firebase-bom
```
**Solución**: Verifica tu conexión a internet. Gradle descarga dependencias desde `google()` y `mavenCentral()` al primer build. Puede tardar varios minutos la primera vez.

### Error: "No Firebase App has been created"

```
The default Firebase app has not been created
```
**Solución**: Asegúrate de que `android/app/google-services.json` exista y que el plugin `com.google.gms.google-services` esté declarado en `android/app/build.gradle.kts` (línea 3) y en `android/settings.gradle.kts` (línea 24).

### Error de versiones Pigeon / Firebase

```
firebase_core_platform_interface: ... is incompatible
```
**Solución**: El `pubspec.yaml` fija `firebase_core_platform_interface: 5.4.1` (pin exacto). **No modifiques** esa línea sin verificar la compatibilidad de canales de Pigeon con el código nativo del proyecto.

### Builds antiguos corruptos

```bash
flutter clean
flutter pub get
cd android
./gradlew clean
cd ..
flutter run
```

### El login de Google falla

1. Verifica que el **SHA-1** de depuración esté registrado en Firebase Console.
2. Regenera el SHA-1 después de cambios de keystore:
   ```bash
   ./gradlew signingReport
   ```
3. Confirma que la **huella SHA-1** corresponde al keystore `debug.keystore` (el default para desarrollo).

### La app se cierra al abrirla en el celular

1. Revisa los **Logcat** en Android Studio (pestaña `Logcat`), o ejecuta:
   ```bash
   flutter run --verbose
   ```
2. Comprueba que el `minSdk` del dispositivo sea compatible con el `minSdk` del proyecto.


## 📄 Nota Legal

Esta aplicación se desarrolló con fines educativos y de acompañamiento para pacientes con Parkinson en Colombia. **No sustituye la opinión ni el tratamiento de un profesional de la salud.** El monitoreo de temblor usa datos demo y lecturas de hardware de desarrollo (ESP32); consulta siempre con tu médico.

---

*Desarrollado con ❤️ usando Flutter + Firebase.*