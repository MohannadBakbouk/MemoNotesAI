# 🎙️ MemoNotesAI

> 📱 A production-grade iOS recording & transcription app engineered for **16+ hour sessions**, **zero audio loss across segment boundaries**, and **graceful degradation** under thermal, network, memory, and call-interruption pressure.

MemoNotesAI captures long-form audio, slices it into rolling **30-second segments**, transcribes them through a **☁️ Groq-primary / 🧠 on-device WhisperKit-fallback** pipeline, persists everything in **SwiftData**, and reactively streams updates into SwiftUI — all built on **modern Swift Concurrency** (`actor`, `@MainActor`, `AsyncStream`) with **no `DispatchQueue` mutexes for shared state** and **no `@unchecked Sendable` shortcuts where actor isolation can do the job**.

---

## 📺 App Demo Video

<div align="center">

| 📱 MemoNotesAI in Action |
| :---: |
| <video src="https://github.com/user-attachments/assets/e024271b-d2b1-496c-a757-f61fd3e1f082" controls width="80%"> </video> |

</div>

---

## 📑 Table of Contents

1. [📺 App Demo Video](#-app-demo-video)
2. [🎯 Purpose & Capabilities](#-purpose--capabilities)
3. [✨ Key Features](#-key-features)
4. [🏛️ Architecture Overview](#️-architecture-overview)
5. [🧭 Architectural Decisions](#-architectural-decisions)
6. [🗂️ Project Structure](#️-project-structure)
7. [🧩 Design Patterns](#-design-patterns)
8. [🔄 Data Flow & State Management](#-data-flow--state-management)
9. [⚙️ Concurrency Model](#️-concurrency-model)
10. [🛟 Error Handling Strategy](#-error-handling-strategy)
11. [🧪 Edge Cases & Production Considerations](#-edge-cases--production-considerations)
12. [📈 Scalability, Maintainability, Testability](#-scalability-maintainability-testability)
13. [💎 Noteworthy Technical Implementations](#-noteworthy-technical-implementations)

---

## 🎯 Purpose & Capabilities

MemoNotesAI is a long-form audio capture and transcription app targeted at journalists, researchers, students, and professionals who need **reliable multi-hour recording** with **searchable transcripts**, without trusting a single point of failure.

The app captures audio continuously, ships each 30-second segment to **Groq Whisper** for low-latency cloud transcription, and falls back to a **bundled on-device WhisperKit model** (`openai_whisper-base.en`) when the network or remote service is unavailable. Audio segment files are deleted only after the transcript is durably persisted — so transcripts survive crashes, kills, and OS evictions.

## ✨ Key Features

- ⏱️ **Continuous 30-second rolling segmentation** with zero-loss boundary swap (double-buffer file rotation)
- 🔀 **Hybrid transcription pipeline** — ☁️ **Groq Whisper as primary**, 🧠 **on-device WhisperKit (`openai_whisper-base.en`) as fallback** when Groq is unreachable, rate-limited, or returns an error
- 🔁 **Per-segment manual retry** — explicit "Retry with Groq" / "Retry with WhisperKit" affordances on failed or silent segments
- 🛟 **Crash & kill recovery** — interrupted sessions are detected on launch and stranded segments re-queued automatically
- 📞 **Call-interruption resilience** — recording auto-pauses on phone calls / Siri / alarms and resumes when the system signals `.shouldResume`
- 🎧 **Route-change handling** — AirPods disconnect, CarPlay, wired-headphone unplug — no silent session drops
- 🌡️ **Thermal / battery / memory pressure monitoring** — `SystemCore` exposes structured signals consumed by the pipeline
- ⏳ **Background task continuation** — `BackgroundTaskManager` keeps the upload queue alive across app backgrounding
- ⚡ **Reactive UI** — SwiftUI views subscribe to repository `AsyncStream<Void>` change feeds; no polling, no manual refresh
- 〰️ **Live waveform & level metering** during recording
- 🚦 **Per-segment status surfacing** — `pending` / `transcribing` / `completed` / `failed` / `silent` — with retry affordances

---

## 🏛️ Architecture Overview

MemoNotesAI is composed of **eight local Swift Package Manager modules** assembled by a thin `App` target. Dependencies flow strictly **downward** through layers — features and infrastructure depend on `PersistenceCore` and `NetworkCore`, **never the reverse** — and **`App` is the only place cross-module wiring lives**.

```
        ╔══════════════════════════════════════════════╗
        ║                    App                        ║
        ║   (thin shell — DI, @main, navigation,        ║
        ║    cross-module wiring, launch recovery)      ║
        ╚══════════════════════════════════════════════╝
                            │ owns & wires
        ┌───────────────────┼─────────────────────────┐
        ▼                                             ▼
 ┌──────────────────┐                       ┌──────────────────┐
 │  FEATURE LAYER   │                       │ INFRASTRUCTURE    │
 │  (SwiftUI / VM)  │                       │   (services)      │
 ├──────────────────┤                       ├──────────────────┤
 │ RecordingFeature │                       │ AudioCore         │
 │ SessionsFeature  │                       │ TranscriptionCore │
 └────────┬─────────┘                       │ SystemCore        │
          │                                 └────────┬─────────┘
          │       depends on contracts in            │
          ▼                                          ▼
        ┌────────────────────────────────────────────────┐
        │            CORE / FOUNDATION LAYER              │
        ├────────────────────────────────────────────────┤
        │  PersistenceCore   (SwiftData, repositories,    │
        │                     domain models, protocols)   │
        │  NetworkCore       (APIClient, multipart,       │
        │                     KeychainTokenStore)         │
        └────────────────────────────────────────────────┘
```

**Concrete module edges** (`A ──► B` means `A imports B`):

| Module | Imports |
|---|---|
| `App` | every other module (composition root) |
| `RecordingFeature` | `PersistenceCore` (+ protocol-shaped view of `AudioCore` via `RecordingServiceProtocol`) |
| `SessionsFeature` | `PersistenceCore` |
| `AudioCore` | `PersistenceCore` |
| `SystemCore` | `PersistenceCore` |
| `TranscriptionCore` | `PersistenceCore`, `NetworkCore`, `AudioCore`, `SystemCore`, `WhisperKit` (SPM) |
| `NetworkCore` | *(no local deps)* |
| `PersistenceCore` | *(no local deps — foundation)* |

**Why eight modules?** Each compiles independently, has a single non-overlapping responsibility, and is unit-testable in isolation. Build times stay flat as the codebase grows because changes to a feature module never force `PersistenceCore` or `NetworkCore` to recompile.

## 🧭 Architectural Decisions

| 🧠 Decision | 💡 Why |
|---|---|
| **Local SPM modules, not folder-grouping** | Enforces dependency direction at compile time. You cannot accidentally import a feature module from a core module. |
| **No standalone `Domain` SPM** | Use cases live next to the feature that owns them (vertical slices). Avoids ceremony for a two-screen app while keeping the use-case pattern. |
| **Repository protocols in `PersistenceCore`** | Features depend on `SessionRepositoryProtocol`, not on SwiftData — keeps features testable with in-memory fakes and shields them from the SwiftData type system. |
| **Groq primary, WhisperKit fallback** | Cloud Whisper is faster and more accurate for long-form English. On-device exists for offline resilience and rate-limit safety, not as the default. |
| **Bundled WhisperKit model, lazy-initialized** | Avoids a first-launch model download UX and gives a deterministic offline experience. Lazy init keeps cold start fast. |
| **Single serial transcription queue (`@MainActor`)** | Eliminates races on audio files and repository rows without locks. Throughput is bounded by Groq RTT anyway. |
| **`AsyncStream<Void>` change feeds (not polling, not Combine)** | Repositories publish change tokens; ViewModels `for await` inside `.task { }`. SwiftUI cancels the loop on view disappearance — zero subscription bookkeeping. |
| **Delete audio only after transcript is persisted** | Guarantees retry capability across crashes. Audio is the source of truth until the transcript row exists. |
| **`httpMaximumConnectionsPerHost = 1` for Groq uploads** | Mitigates `NSURLErrorHTTPTooManyRedirects (-1017)` flakiness observed against Groq's edge under burst load. Combined with jittered exponential backoff. |
| **`os_unfair_lock` inside the real-time audio path** | The render thread *cannot* hop actors; an unfair lock is the lightest, render-safe primitive for the tiny `levelMonitor` / `currentFile` snapshots. |

---

## 🗂️ Project Structure

> 🎨 **Layout philosophy:** every module is a sibling folder under `MemoNotesAI/`. The `App/` target is intentionally tiny — it only owns DI wiring, the SwiftUI entry point, navigation shell, and a single launch-time recovery use case. **All business logic lives in SPM modules**, which means each one compiles, tests, and ships independently. You can drag any module into another iOS app and it works.

```text
📦 MemoNotesAI/                              ← Xcode project root
│
├── 🚀 App/                                  ← Thin composition root
│   ├── MemoNotesAIApp.swift                 # @main SwiftUI entry
│   ├── AppDependencies.swift                # @MainActor DI graph + wiring
│   ├── ContentView.swift                    # TabView navigation shell
│   └── Domain/UseCases/
│       └── RecoverInterruptedSessionUseCase.swift
│
├── 🗄️ PersistenceCore/                      ← Foundation layer · no local deps
│   ├── SwiftDataStack.swift                 # ModelContainer factory
│   ├── FileStore.swift                      # Disk-side audio file ops
│   ├── PersistenceError.swift
│   ├── Models/                              # @Model SwiftData types
│   │   ├── RecordingSessionModel.swift
│   │   ├── AudioSegmentModel.swift
│   │   ├── TranscriptionModel.swift
│   │   ├── SegmentProcessingStatus.swift    # pending|transcribing|completed|failed|silent
│   │   └── TranscriptionMethod.swift        # .groq | .whisperKit
│   ├── DTOs/                                # Cross-actor value types
│   │   ├── NewSegmentRecord.swift
│   │   └── RecordingSessionStateUpdate.swift
│   ├── Protocols/                           # Repository contracts
│   │   ├── SessionRepositoryProtocol.swift
│   │   ├── SegmentRepositoryProtocol.swift
│   │   ├── TranscriptionRepositoryProtocol.swift
│   │   └── FileStoreProtocol.swift
│   └── Repositories/                        # Concrete SwiftData impls + AsyncStream feeds
│       ├── SessionRepository.swift
│       ├── SegmentRepository.swift
│       └── TranscriptionRepository.swift
│
├── 🌐 NetworkCore/                          ← HTTP transport · no local deps
│   ├── APIClient.swift                      # retry + jittered backoff
│   ├── NetworkClient.swift
│   ├── Endpoint.swift
│   ├── MultipartFormData.swift              # Groq multipart audio uploads
│   └── KeychainTokenStore.swift             # API key in Keychain (not UserDefaults)
│
├── 🎙️ AudioCore/                            ← AVAudioEngine recording stack
│   ├── AudioRecordingService.swift          # start/stop/pause/resume + tap install
│   ├── SegmentWriter.swift                  # Option B double-buffer file swap
│   ├── SegmentTimer.swift                   # 30s rollover, pause-aware
│   ├── AudioSessionConfigurator.swift       # AVAudioSession category/options
│   ├── AudioInterruptionHandler.swift       # AVAudioSession interruption events
│   ├── AudioRouteChangeHandler.swift        # Route change events (AirPods, etc.)
│   ├── AudioLevelMonitor.swift              # RMS metering · os_unfair_lock
│   ├── Models/
│   │   ├── ClosedSegmentInfo.swift          # Value emitted on each rollover
│   │   ├── RecordingState.swift             # .idle/.recording/.paused
│   │   └── AudioCoreError.swift
│   ├── Protocols/AudioRecordingServiceProtocol.swift
│   └── Domain/UseCases/
│       ├── HandleAudioInterruptionUseCase.swift
│       └── HandleRouteChangeUseCase.swift
│
├── 🌡️ SystemCore/                           ← OS-signal monitoring
│   ├── SignalMonitor.swift                  # Shared monitor protocol
│   ├── ThermalMonitor.swift                 # actor
│   ├── BatteryMonitor.swift                 # actor
│   ├── MemoryPressureMonitor.swift          # actor
│   ├── BackgroundTaskManager.swift          # actor wrapping UIBackgroundTaskIdentifier
│   ├── PermissionsService.swift             # mic permission gate
│   └── Domain/UseCases/HandlePowerStateUseCase.swift
│
├── 🧠 TranscriptionCore/                    ← Provider abstraction + pipeline
│   ├── TranscriptionService.swift           # Provider protocol (Strategy pattern)
│   ├── GroqTranscriptionService.swift       # ☁️ remote provider
│   ├── WhisperKitTranscriptionService.swift # 🧠 on-device fallback (lazy init)
│   ├── TranscriptionQueue.swift             # @MainActor serial AsyncStream runner
│   ├── TranscriptionPipeline.swift          # AudioCore → Repo → Queue bridge
│   ├── TranscriptionError.swift
│   ├── GroqConstants.swift
│   └── Domain/UseCases/
│       ├── TranscribeSegmentUseCase.swift   # Groq → WhisperKit fallback + retention policy
│       ├── RetryFailedTranscriptionsUseCase.swift
│       └── DeleteSegmentAudioUseCase.swift
│
├── 🎬 RecordingFeature/                     ← Recording screen (SPM)
│   └── Sources/RecordingFeature/
│       ├── RecordingServiceProtocol.swift   # Insulates feature from AudioCore concretes
│       ├── Presentation/
│       │   ├── RecordingView.swift
│       │   ├── RecordingViewModel.swift     # @Observable
│       │   └── Components/
│       │       ├── WaveformView.swift
│       │       └── RecordButton.swift
│       └── Domain/UseCases/
│           ├── StartRecordingUseCase.swift
│           └── StopRecordingUseCase.swift
│
└── 📋 SessionsFeature/                      ← Sessions list + detail (SPM)
    └── Sources/SessionsFeature/
        ├── Models/
        │   ├── SessionDisplayModel.swift
        │   └── SegmentDisplayModel.swift
        ├── Presentation/
        │   ├── SessionListView.swift / ViewModel
        │   ├── SessionDetailView.swift / ViewModel
        │   └── Components/
        │       ├── SessionRowView.swift
        │       └── SegmentTranscriptRow.swift    # status + retry buttons
        └── Domain/UseCases/
            ├── FetchSessionsUseCase.swift
            ├── FetchSegmentsUseCase.swift
            └── DeleteSessionUseCase.swift
```

## 🧩 Design Patterns

- 🏗️ **Clean Architecture (lite) / Vertical Slices** — each feature owns its own `Presentation` and `Domain/UseCases`. No god-domain layer.
- 📦 **Repository pattern** — `SessionRepository`, `SegmentRepository`, `TranscriptionRepository` hide SwiftData behind protocols.
- 🎯 **Strategy pattern** — `TranscriptionService` protocol with `GroqTranscriptionService` and `WhisperKitTranscriptionService` as interchangeable strategies; `TranscribeSegmentUseCase` selects between them.
- ✅ **Use Case pattern** — every meaningful action (`StartRecordingUseCase`, `TranscribeSegmentUseCase`, `RecoverInterruptedSessionUseCase`, `HandlePowerStateUseCase`, …) is an explicit object with a single `execute(...)` entry point.
- 📡 **Observer / Reactive feeds** — repositories expose `AsyncStream<Void>` change tokens; ViewModels reload on each tick.
- 🎭 **Façade** — `TranscriptionPipeline` is a thin façade over the queue + retry use case + repository; `AudioCore` callers see one entry point.
- 🧵 **Producer–Consumer queue** — `TranscriptionQueue` is a single-consumer `AsyncStream` driven by audio segment events.
- 💉 **Dependency Injection (constructor-based)** — `AppDependencies` builds and wires the full graph; no service locator, no singletons.
- 🌱 **Composition root** — only `App/AppDependencies` knows about every module.

---

## 🔄 Data Flow & State Management

```
👆 User taps Record
        │
        ▼
🎬 StartRecordingUseCase ─► SessionRepository.create
                        └► AudioRecordingService.start
                                  │
                                  ▼
                          AVAudioEngine tap → SegmentWriter
                          (writes to fileA; at 30s, opens fileB
                           BEFORE closing fileA — no gap)
                                  │
                                  ▼  segmentClosedHandler(ClosedSegmentInfo)
                          🧠 TranscriptionPipeline.segmentClosed
                                  │  (creates AudioSegmentModel row,
                                  │   then enqueues onto queue)
                                  ▼
                          🔁 TranscriptionQueue (serial · @MainActor)
                                  │
                                  ▼
                          🎯 TranscribeSegmentUseCase
                              ├─► ☁️ GroqTranscriptionService  (primary)
                              │      └─ success → TranscriptionRepository.save
                              │                 → DeleteSegmentAudioUseCase  🗑️
                              └─► 🧠 WhisperKitTranscriptionService (fallback)
                                                      ↓
                                       TranscriptionRepository.save
                                       (audio kept — user can still retry Groq)
                                  │
                                  ▼
                          📡 SegmentRepository emits ()-tick on AsyncStream
                                  │
                                  ▼
        🖼️ SessionListVM / SessionDetailVM wake, reload, SwiftUI re-renders.
```

**State ownership:**
- 💾 **Durable state** — SwiftData (`@Model` types in `PersistenceCore`).
- 🎙️ **In-flight session state** — `AudioRecordingService` (`RecordingState` enum) + `state` on the active `RecordingSessionModel`.
- 🖼️ **View state** — `@Observable` ViewModels; SwiftUI views never read repositories directly.
- 📊 **Cross-cutting signals** — `ThermalMonitor`, `BatteryMonitor`, `MemoryPressureMonitor` as `actor`s, surfaced via `AsyncStream<Value>`.

## ⚙️ Concurrency Model

- 🧷 **`@MainActor`** isolates: every ViewModel, every Repository, `AppDependencies`, `TranscriptionQueue`, `TranscriptionPipeline`, `HandlePowerStateUseCase`. SwiftData `ModelContext` access is always main-actor.
- 🎭 **`actor`** isolates: `BackgroundTaskManager`, `ThermalMonitor`, `BatteryMonitor`, `MemoryPressureMonitor`.
- 🔓 **`os_unfair_lock`** is used **only inside the real-time audio path** — `AudioLevelMonitor` (RMS write/read) and `SegmentWriter.write` (snapshot of `currentFile` and frame counters). The audio render thread cannot `await`, cannot hop actors, and any blocking primitive would risk audio glitches. `os_unfair_lock` is the lightest non-blocking-in-the-uncontended-path primitive that's safe to take from a real-time thread.
- 📡 **`AsyncStream`** is the only cross-actor pub/sub mechanism. No `NotificationCenter` plumbing for app-internal events, no Combine, no `@Published`.
- 🪢 **Structured concurrency.** Long-running observation lives inside `.task { }` (SwiftUI cancels on disappear) or actor-owned `Task` handles cancelled on `deinit`.
- 🚦 **Single serial pipeline for transcription.** `TranscriptionQueue` consumes one job at a time — order preserved, no file-level locking needed.

## 🛟 Error Handling Strategy

- 🏷️ **Typed errors per module** — `AudioCoreError`, `PersistenceError`, `TranscriptionError`. No `Error` leaking across module boundaries unwrapped.
- 🔁 **Retry where retry is meaningful.** `APIClient` retries on the well-known Groq `-1017` and on transport errors with **jittered exponential backoff**; it does not retry on 4xx.
- 🪂 **Fall back, don't fail.** `TranscribeSegmentUseCase` only marks a segment `.failed` after **both** Groq and WhisperKit have refused it.
- 🗃️ **Audio retention until persisted.** A segment's audio file is deleted **only** after the Groq transcript row is saved. WhisperKit fallback intentionally **keeps** the audio so the user can manually retry Groq later.
- 👀 **Status visible to the user.** `SegmentProcessingStatus` (`pending`, `transcribing`, `completed`, `failed`, `silent`) surfaces in `SegmentTranscriptRow`, with explicit retry buttons on failure states.
- 🩺 **Recovery on launch.** `RecoverInterruptedSessionUseCase` runs in `AppDependencies` bootstrap to close orphaned sessions and re-queue stranded segments left by a crash, force-quit, or OOM kill.

---

## 🧪 Edge Cases & Production Considerations

| 🧨 Concern | 🛠️ Handling |
|---|---|
| **Segment-boundary audio loss** | Double-buffer file swap in `SegmentWriter` — a new file is opened **before** the old one is closed, so no audio frame is dropped at rollover. |
| **Incoming phone call** | `AudioInterruptionHandler` observes `AVAudioSession` interruption notifications; `HandleAudioInterruptionUseCase` pauses the engine and auto-resumes on `.shouldResume`. |
| **Audio route changes** (AirPods, CarPlay) | `AudioRouteChangeHandler` + `HandleRouteChangeUseCase` decide whether to keep, pause, or stop the session, and force a clean segment boundary. |
| **App killed mid-session** | `RecoverInterruptedSessionUseCase` runs at launch, closes the abandoned session, and re-enqueues any segments that never reached `.completed`. |
| **App backgrounded during upload** | `BackgroundTaskManager` (actor) requests and releases `UIBackgroundTaskIdentifier` so the upload completes before suspension. |
| **Thermal throttle / low battery** | `ThermalMonitor` + `BatteryMonitor` feed `HandlePowerStateUseCase`, which can throttle or surface warnings without aborting the session. |
| **Memory pressure** | `MemoryPressureMonitor` (actor) exposes a stream; consumers can drop optional buffers. |
| **Network flakiness / `-1017`** | `APIClient` pins `httpMaximumConnectionsPerHost = 1` and retries with jittered exponential backoff specifically on transport / `-1017` errors. |
| **Groq 429 rate-limit** | `TranscriptionQueue` honors `Retry-After`; recording is never paused — segments accumulate on disk and drain when quota resets. |
| **WhisperKit hallucination on silence** | `noSpeechThreshold: 0.3` marks empty segments as `.silent` instead of inventing text. |
| **Microphone permission revoked** | `PermissionsService` re-checks before each session; the recording flow refuses to start without authorization. |
| **API key handling** | `KeychainTokenStore` — no plaintext in `UserDefaults`, no key committed to source. |
| **SwiftData write contention** | All repositories are `@MainActor`; writes serialize on the main actor, eliminating context-race bugs. |
| **Real-time audio thread safety** | The tap callback only copies the buffer into `SegmentWriter`; no SwiftData, no I/O, no `await`. |

## 📈 Scalability, Maintainability, Testability

- 🧱 **Scales by module, not by file.** Adding "ExportFeature" or "CloudSyncFeature" is a new SPM target with a one-line dependency edge — no edits to existing modules.
- ⚡ **Build performance.** Independent SPM modules compile in parallel; touching `RecordingFeature` does not recompile `PersistenceCore` or `NetworkCore`.
- 🔌 **Provider extensibility.** Adding a third transcription provider is one new conformance of `TranscriptionService`; `TranscribeSegmentUseCase` is the only call site to update.
- 🧪 **Repository protocols enable test doubles.** Features run against in-memory fakes; SwiftData is never mocked directly.
- 🧼 **No global mutable state.** Every dependency is constructed in `AppDependencies` and injected. Tests instantiate their own graph.
- 🔭 **`@Observable` ViewModels are trivially testable** — plain classes with async methods; no view lifecycle required.
- 🎯 **`AsyncStream` change feeds are easy to assert against** — `for await _ in feed.prefix(n)` deterministically verifies reactive behavior.

## 💎 Noteworthy Technical Implementations

- 🔁 **Double-buffer segment rollover (`SegmentWriter`)** — the next `.caf` file is opened *before* the previous file is closed, eliminating the audio gap that naive segmenters drop at the boundary. The closed file is published via `ClosedSegmentInfo` to the transcription pipeline.
- 🎼 **Single-consumer serial transcription queue (`TranscriptionQueue`)** — an `AsyncStream`-backed `@MainActor` runner with `forcedProvider` support for user-initiated retries and `pause(until:)` for Groq `Retry-After`. Ordering is preserved naturally; no locks needed.
- 🌉 **`TranscriptionPipeline` façade** — bridges `AudioCore`'s `segmentClosedHandler` callback to the `SegmentRepository` insert and the queue enqueue, owning `activeSessionID` so segments are correctly attributed to the current session.
- 🪂 **Provider fallback with audio-retention semantics (`TranscribeSegmentUseCase`)** — Groq success deletes the audio; WhisperKit success keeps it so the user can still try Groq later. Encodes a subtle product decision in the use case itself rather than scattering it across services.
- 📡 **Reactive repositories without Combine** — repositories emit `AsyncStream<Void>` change tokens; the ViewModel's `observeAndLoad()` re-fetches on every tick. SwiftUI's `.task` cancels the loop on disappearance for free.
- 🌡️ **Actor-isolated OS signal monitors** — `ThermalMonitor`, `BatteryMonitor`, `MemoryPressureMonitor` conform to a uniform `SignalMonitor` protocol; consumers compose them identically.
- 🩺 **Crash-tolerant recovery (`RecoverInterruptedSessionUseCase`)** — declarative reconciliation at launch: close orphan sessions, re-enqueue stranded segments. The app heals itself.
- 🛰️ **`-1017` mitigation in `APIClient`** — pinned single-connection-per-host plus jittered retry, derived from observed Groq edge behavior under burst multipart uploads.
- 🧵 **`os_unfair_lock` only on the real-time audio path** — the audio render thread cannot await; an unfair lock is the lightest render-safe primitive for the tiny `level` and `currentFile` snapshots in `AudioLevelMonitor` and `SegmentWriter`. Everywhere else, actor or `@MainActor` isolation does the job.
- 🌱 **Composition root in `AppDependencies`** — a single `@MainActor` object instantiates every service, repository, use case, and wiring closure. There is exactly one place to reason about object lifetimes.
