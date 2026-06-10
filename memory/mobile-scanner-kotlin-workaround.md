---
name: mobile-scanner-kotlin-workaround
description: mobile_scanner v7.2.0 needs a Kotlin version bump in pub cache + gradle.properties config to build with Flutter 3.44.1 Built-in Kotlin
metadata:
  type: reference
---

# mobile_scanner Built-in Kotlin Workaround (2026-06-09)

## Problem

Flutter 3.44.1 uses "Built-in Kotlin" which bundles KGP (Kotlin Gradle Plugin) v2.2.20.
The project's `android/settings.gradle.kts` declares KGP v2.3.20.
But `mobile_scanner` v7.2.0 hardcodes `ext.kotlin_version = "2.1.0"` which creates a KGP version mismatch, causing:

```
e: Daemon compilation failed
java.lang.Exception: Storage is already registered
Could not close incremental caches
```

## Two-part Fix

### 1. Patch pub cache (must re-apply after `flutter pub get`)

File: `%LOCALAPPDATA%\Pub\Cache\hosted\pub.flutter-io.cn\mobile_scanner-7.2.0\android\build.gradle`

Change line 5:
```diff
-    ext.kotlin_version = "2.1.0"
+    ext.kotlin_version = "2.3.20"
```

This matches the version declared in `android/settings.gradle.kts`.

### 2. Project gradle.properties (persistent, checked into repo)

In `android/gradle.properties`, added:
```properties
kotlin.incremental=false
kotlin.compiler.execution.strategy=in-process
```

These disable Kotlin's incremental compilation (which causes "Storage is already registered" cache conflicts when two KGP versions are on the classpath) and force in-process compilation (avoids daemon classloader conflicts).

### 3. JAVA_HOME

Must be JDK 17+. Current system has JDK 21 at `C:\Program Files\Java\jdk-21.0.11`.
Set `JAVA_HOME` environment variable before building:
```
set JAVA_HOME=C:\Program Files\Java\jdk-21.0.11
```

## When to Remove

When `mobile_scanner` releases a version that:
1. Does NOT apply `kotlin-android` via `buildscript { classpath }` + `apply plugin:`
2. Uses the modern `plugins {}` block or relies on Flutter's Built-in Kotlin
3. Explicitly mentions "Flutter 3.44+ Built-in Kotlin" compatibility in changelog

Then:
1. Remove `kotlin.incremental=false` and `kotlin.compiler.execution.strategy=in-process` from `gradle.properties`
2. Remove this memory file
3. The pub cache patch is no longer needed since new version won't need it
