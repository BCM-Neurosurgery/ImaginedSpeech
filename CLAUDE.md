# Imagined Speech Psychtoolbox Task

## Project goal

Build a MATLAB/Psychtoolbox experiment for an imagined-speech study. The launcher opens a small experimenter GUI with five buttons, numbered 0 through 4. Selecting a button runs that block independently so a session can begin or resume at any block.

The experiment must be data-driven. Instructions, stories, questions, words, phrases, audio, image sequences, survey items, and answer choices belong under `task_data/`; they must not be embedded in MATLAB source. All assets needed by a block are validated and loaded into memory before its first timed trial.

The launcher, config loader, hardware adapters, and all five block runners are implemented. All five blocks are now fully data-driven and preload-validated end to end (instructions, stories/questions, the 540-trial schedule, the 200-trial image sequence, and the VVIQ survey all resolve to real, finalized `task_data/` content and pass their loaders). Current source material includes:

- `task_info/experimentalstructure.txt`: the original experiment outline.
- `task_info/Vividness of Visual Imagery Questionnaire (VVIQ) (PaperSurvey.io).pdf`: the survey reference, transcribed into `task_data/surveys/vviq.json` (4 sections × 4 items, 5-point scale, documented scoring).
- `task_data/speech/AAC_trial_schedule.csv` + `task_data/speech/block2_manifest.json` + `task_data/speech/audio_clips/`: the finalized 540-trial Block 2 schedule and its 45 decoded/mapped audio clips.
- `task_data/stories/`: two MP3 stories, their DOCX source texts, and the finalized `block1_stories.json` manifest (2 stories, comprehension questions with answer keys).
- `task_data/images/`: 90 unique images and the finalized `block3_manifest.json` + `image_trial_sequence.csv` (200 trials, one-back targets marked).
- `task_data/instructions/block0_instructions.json`: finalized instruction deck (7 slides).
- `task_data/surveys/vviq.json`: finalized VVIQ runtime survey data.

Treat source documents as references, not runtime inputs. Runtime-facing instructions and questions should be transcribed into a simple validated data format under `task_data/`.

## Block definitions

### Block 0 — Instructions

Present instruction pages loaded from task data. Support forward/back navigation and an explicit start/finish action. Do not place instruction prose in code.

### Block 1 — Stories and comprehension

Use a black background. Present, in order:

1. Story 1 audio.
2. Story 1 multiple-choice comprehension questions.
3. Story 2 audio.
4. Story 2 multiple-choice comprehension questions.

Preload both decoded audio waveforms and all questions/choices before presentation. Record selected answers, correctness when an answer key is supplied, response times, and timestamps. Story order should come from a manifest rather than filename sorting.

### Block 2 — Randomized speech/imagery trials

The current schedule has 540 randomized trials:

- 150 spoken-word trials: 30 words × 5 repetitions.
- 150 imagined-speech word trials: 30 words × 5 repetitions.
- 90 visually imagined word trials: 18 words × 5 repetitions.
- 75 spoken-phrase trials: 15 phrases × 5 repetitions.
- 75 imagined-speech phrase trials: 15 phrases × 5 repetitions.

Each row of `AAC_trial_schedule.csv` supplies the stimulus text, trial type, silent-period duration, and inter-trial interval. The intended trial sequence is:

1. Present the word/phrase per `config.block2.presentation_mode` (`"listening"`, `"reading"`, or `"both"` — default `"both"`, matching the original listening+reading behavior) and play its associated audio for the audio duration when the mode includes listening.
2. Black-screen silence for the row/configured duration.
3. Reveal the requested action for 500 ms by default.
4. Show the action cue (a green square on black) for up to 2 s for words or 3 s for phrases by default. The participant speaks, imagines speaking, or visually imagines as requested and may press Enter to end this phase early.
5. Black-screen inter-trial interval for the row/configured duration.

When `presentation_mode` includes listening (`"listening"` or `"both"`), the stimulus presentation period is driven by actual audio playback duration (or `test_audio_max_seconds` in test mode), exactly as before. When `presentation_mode` is `"reading"` (no audio played), the presentation period instead uses the fixed, independently configurable `config.block2.reading_only_word_seconds` (default 0.5 s) or `config.block2.reading_only_phrase_seconds` (default 1.0 s) depending on whether the stimulus is a phrase. The logged onset event is named `AUDIO_ONSET` when audio plays and `STIMULUS_ONSET` otherwise; the per-trial log column is named `stimulus_onset` to cover both cases.

Stimulus-to-audio mapping must be explicit in task data; do not derive correctness-critical filenames ad hoc. Store exactly one audio file per unique stimulus and join each schedule row to that file through the audio manifest. Decode every unique audio file before the first trial and fill PsychPortAudio buffers in advance where supported (skipped entirely when `presentation_mode` is `"reading"`, since no audio device is needed). The ElevenLabs utility is an offline preparation tool only and must never make network calls during an experiment.

### Block 3 — Image encoding / one-back task

Present a task-data-defined image sequence. Default timing from the existing outline is image on for 500 ms, then image off for 500 ms. Each image is displayed at `config.block3.image_display_fraction` (default 0.6) of the window's smaller dimension, configurable rather than hardcoded. The participant presses Enter when the current image is identical to the immediately preceding image. Preload all image pixels and create all Psychtoolbox textures before the first timed presentation. Log stimulus identity, one-back target status, response, accuracy, response time, and flip timestamps.

### Block 4 — VVIQ survey

Administer the Vividness of Visual Imagery Questionnaire using task-data-defined instructions, items, response labels, values, and presentation order. The PDF in `task_info/` is a reference; survey content is represented in `task_data/surveys/vviq.json` rather than hardcoded in MATLAB. Log item-level responses and response times, and compute scores only according to the documented scoring definition in that file (sum of the 16 item values, range 16–80, higher = more vivid imagery).

## Configuration

Use one human-readable versioned config file (prefer JSON for built-in MATLAB support) with validation and documented defaults. It should control at least:

- display selection, resolution behavior, background/text/cue/photodiode colors, fonts, and text sizes;
- keyboard mappings, including Enter, an emergency abort key, and a deselect key (`keys.deselect`, default BackSpace) that lets a participant clear a picked-but-not-yet-submitted multiple-choice answer to reconsider it — never mapped to Escape, which always means "abort the task";
- audio device, sample rate, channel handling, and volume;
- all default phase durations and whether schedule values override defaults;
- photodiode enablement, rectangle position/size, and phase/event behavior;
- Cbmex enablement and event/comment behavior;
- audio-sync tone enablement (default off), output device, sample rate, volume, and each tone's frequency/duration;
- debug/windowed mode and timing-check policy;
- output directory and safe resume/overwrite policy.

Timing values in a schedule take precedence only when the config explicitly selects schedule-driven timing. Never scatter adjustable constants through block code.

`display.screen_index` is a raw Psychtoolbox screen index, not the Windows display number, and the two do not necessarily agree. On this multi-monitor Windows machine, PTB screen 0 is the combined virtual desktop spanning *all* physical monitors (opening fullscreen there stretches across every screen at once, which looks neither properly fullscreen nor windowed); screen 1 is the primary monitor and screen 2 is the secondary monitor. Re-verify this mapping with `Screen('Screens')` / `Screen('Rect', index)` any time monitors, cables, or this machine change, rather than assuming screen 0 means "main screen."

## Synchronization and event model

Photodiode, Cbmex, and audio-sync tones must all be independently configurable. The photodiode patch is positioned at the bottom-left of the stimulus display. All three backends should consume the same canonical event structure so logged behavioral events, photodiode transitions, audio-sync tones, and neural comments can be aligned. Define stable event names/codes centrally and include at least block start/end, trial start/end, stimulus onset, audio onset, action-type reveal, action-cue onset/offset, response, and abort.

Block 2 emits paired flash/comment events at spoken-audio onset (including the word/phrase), silent-interval onset, trial-type reveal, action-cue onset, and inter-trial-interval onset. Block 3 emits them at image onset (including image ID) and every Enter response. Blocks 1 and 4 emit them at question/item onset, answer selection (`ANSWER_PICK`), an optional answer deselection (`ANSWER_DESELECT`, fired when the participant presses the deselect key to clear a pick and reconsider — this can repeat any number of times before submission) and answer submission (`ANSWER_SUBMIT`), including stable question/item and answer IDs. For every paired event, execute the visual photodiode flip first and send the higher-latency Cbmex comment immediately after the flip returns.

When Cbmex comments are enabled, the master launcher owns the NSP connections and task lifecycle. At block start it mirrors `TaskComment('start')`: send `$TASKSTART EMU-####` and `$TASKID ...` to all detected NSP instances and append exactly one entry to `+CurrentPatientLog` with `setNextLogEntry`. On normal completion send `$TASKSTOP`; on Escape send `$TASKKILL`; on any other uncaught block error send `$TASKERR`. Terminal lifecycle events reuse the same EMU number and do not increment the patient log.

Photodiode changes must occur on the same `Screen('Flip', ...)` as the visual event they mark. Cbmex calls must be isolated behind an adapter so the task runs normally when Cbmex is unavailable and disabled. If synchronization is enabled but initialization fails, fail before the block starts rather than silently running unsynchronized.

### Audio sync tones

`audio_sync` (default `enabled: false`) is a third synchronization channel, independent of photodiode and Cbmex: short synthesized pure tones, played through their own dedicated PsychPortAudio device (`audio_sync.device_index`, default -1 = system default) so tone playback never competes with a block's own stimulus-audio buffer. Every tone's frequency and duration is configured under `audio_sync.tones` and preloaded (synthesized once, with a short fade to avoid clicks) before the ready screen, never during a timed trial. When disabled, no audio device is opened at all — zero overhead or hardware dependency.

Each of Blocks 0-4 plays `block_start` once, right as its timed content begins (after the ready/intro gate, or before the first slide for Block 0), and `block_end` exactly once at the very end of the run — via an `onCleanup`-registered call so it fires on normal completion, abort, and error alike, matching the block's `finish_task_lifecycle` symmetry. Additional per-context tones: `block1_question_onset` (every comprehension question); `block2_reading_stimulus_onset` (only when `presentation_mode` is `"reading"`, at the same moment the word/phrase appears with no audio); `block2_early_response` (when the participant presses Enter to end the action-cue phase early — deliberately a different tone from the reading-onset one); `block3_image_onset` and `block3_response` (image presentation vs. the one-back Enter response — deliberately distinguishable tones); `block4_question_onset` (every VVIQ item). Tone playback is fire-and-forget (non-blocking), so it never delays the phase it marks, the same way the Cbmex comment never blocks on the photodiode flip.

## Data loading and validation

Each block follows a strict lifecycle:

1. Load configuration and block manifest/schedule.
2. Validate required columns, allowed values, uniqueness, file existence, answer keys, and numeric ranges.
3. Load/decode all required audio, image, text, and survey content into a block buffer.
4. Initialize display, audio, input, synchronization, and output logging.
5. Show a ready screen; timed execution begins only after successful preload.
6. Run trials while writing incremental, recoverable results.
7. Close textures/audio/devices and restore MATLAB state even after abort/error.

No disk reads, document parsing, image decoding, audio decoding, network access, or dynamic allocation of large assets should occur within a timed trial.

## Results and reproducibility

Require a Patient ID in the master block-selection GUI. Create one unique time-indexed session directory at `<configured patient-data root>/<Patient ID>/<timestamp>/` and never overwrite existing participant data. The default root is set in `config/task_config.json` under `paths.patient_data` and must match the Windows profile that actually runs the task on the current machine (currently `C:\Users\lizzi\Documents\MATLAB\PatientData` on this computer). Blocks 1, 2, 3, and 4 write behavioral responses into this patient session. Save:

- participant/session/block identifiers and timestamps;
- config snapshot and task-data manifest/version information;
- MATLAB, OS, Psychtoolbox, display, audio, and synchronization metadata;
- scheduled values and actual event/flip/audio timestamps;
- responses, correctness, and response times;
- errors, warnings, dropped/missed timing indicators, and abort state.

Each of Blocks 1-4 calls `src/core/save_run_snapshot.m` once, immediately after opening its CSV logs and before the ready screen (i.e., before any timed trial), writing `block{N}_{runId}_config.mat` into the session directory. That MAT file holds the entire resolved `config` struct (so any adjustable setting — Block 2's `presentation_mode`, reading-only durations, and scheduled-vs-default silence/ITI flags; Block 3's `image_display_fraction`; timing/color/size settings for every block — is reconstructable per run), MATLAB/OS/Psychtoolbox/hostname environment metadata, and a `content_sources` list of every task-data file that determined that run's stimuli (manifest, schedule, audio manifest, survey file, story audio), each with a SHA-256 hash via `src/core/compute_file_hash.m`. This directly supports re-running the same story order, speech/imagery schedule, or image sequence later and knowing definitively whether the underlying task-data file changed between runs. The snapshot is written once per run (config/content selection do not change mid-run), while the pre-existing per-trial CSV logs continue to carry the presented-stimulus identity for every trial that actually executed — so an aborted run still leaves an accurate, non-misleading record of only the trials that ran, never a phantom record of trials that didn't.

Use incremental tabular logging plus a final MAT file as appropriate. Preserve the original randomized Block 2 row order and record the schedule filename/hash so a run is reproducible.

## Secrets and generated assets

`task_data/speech/eleven_labs_api.txt` is a secret and must remain untracked and unread by task runtime code. The ElevenLabs generation script also remains untracked under `task_data/speech/`. It reads the key locally, generates only missing unique audio, and produces/updates an explicit one-row-per-stimulus audio manifest. Never log, print, commit, or embed the key.

## Implementation plan

1. **Scaffold and contracts** — done: launcher/GUI, config loader and schema validation, task-data manifests, output naming, logging, cleanup.
2. **Hardware adapters** — done: Psychtoolbox display/audio/input wrappers plus no-op/real photodiode and Cbmex synchronization adapters with canonical events (`send_task_event_comment`, `start_task_lifecycle`, `finish_task_lifecycle`).
3. **Block 0** — done: data-driven paged instructions, 7 slides, forward/back navigation.
4. **Block 1** — done: story manifests, audio preload/playback via PsychPortAudio, multiple-choice UI with pick/deselect/submit, scoring against answer keys, and logging.
5. **Block 2** — done: validates the 540-row schedule and shared audio manifest, preloads all 45 unique recordings, presents all five timed phases and three action types, supports a configurable listening/reading/both presentation mode with independent reading-only durations, supports Enter-to-end-early, and logs/synchronizes every phase transition.
6. **Block 3** — done: 90-image manifest/sequence (200 trials), texture preload, one-back responses (hit/miss/false-alarm/correct-rejection), configurable on-screen image size, and timing/logging.
7. **Block 4** — done: runner, navigation (including pick/deselect/submit), validation, logging, and scoring are implemented, and `task_data/surveys/vviq.json` now holds the full 16-item VVIQ (4 scenarios × 4 items, transcribed from the reference PDF) with the standard Marks (1973) 1–5 vividness scale and documented sum-based scoring (16–80, higher = more vivid).
8. **Stimulus preparation** — after ElevenLabs requirements arrive, add the untracked generator and verify sample rate, channels, loudness, clipping, duration, and manifest coverage offline.
9. **Verification** — loader smoke tests (config, all five block content loaders, patient-session creation), config validation for the new Block 2/3/keys fields (valid and invalid values), and end-to-end `save_run_snapshot` writes/reads for Blocks 1-4 have all been run manually via MATLAB `-batch`. Live Psychtoolbox window tests (`Screen('OpenWindow', ...)`) cannot be run from this non-interactive environment (they hang with no attached interactive desktop session) — Block 1/2/3/4 visual/timing changes (presentation modes, image size, deselect control) have been verified by static code check (`checkcode`) and manual logic review only, not a live run. No formal automated test suite exists yet under `tests/`.

## Decisions still required

Before finalizing behavior, confirm:

- Block 2 on-screen wording and whether visually imagined trials also use spoken audio;
- ElevenLabs voice/model/settings and desired audio normalization/file format;
- lab display/audio device choices, trigger/event codes, photodiode patch geometry/polarity, and the exact Cbmex comment API expected by the acquisition setup;
- participant/session naming and required output format/location;
- a live on-hardware check of Block 2 (all three presentation modes) and Block 3 (new image size) the next time the physical task computer/console is available, since those changes have not yet been visually verified.
