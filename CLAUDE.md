# Imagined Speech Psychtoolbox Task

## Project goal

Build a MATLAB/Psychtoolbox experiment for an imagined-speech study. The launcher opens a small experimenter GUI with five buttons, numbered 0 through 4. Selecting a button runs that block independently so a session can begin or resume at any block.

The experiment must be data-driven. Instructions, stories, questions, words, phrases, audio, image sequences, survey items, and answer choices belong under `task_data/`; they must not be embedded in MATLAB source. All assets needed by a block are validated and loaded into memory before its first timed trial.

The repository now contains the launcher/configuration scaffold and placeholder runners for all five blocks. Current source material includes:

- `task_info/experimentalstructure.txt`: the original experiment outline.
- `task_info/Vividness of Visual Imagery Questionnaire (VVIQ) (PaperSurvey.io).pdf`: the survey reference.
- `task_data/speech/AAC_trial_schedule.csv`: a randomized 540-trial Block 2 schedule.
- `task_data/stories/`: two MP3 stories and their DOCX source texts.
- `task_data/images/`: currently awaiting image stimuli/schedule.

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

1. Present the word/phrase and play its associated audio for the audio duration.
2. Black-screen silence for the row/configured duration.
3. Reveal the requested action for 500 ms by default.
4. Show the action cue (a green square on black) for up to 2 s for words or 3 s for phrases by default. The participant speaks, imagines speaking, or visually imagines as requested and may press Enter to end this phase early.
5. Black-screen inter-trial interval for the row/configured duration.

Stimulus-to-audio mapping must be explicit in task data; do not derive correctness-critical filenames ad hoc. Store exactly one audio file per unique stimulus and join each schedule row to that file through the audio manifest. Decode every unique audio file before the first trial and fill PsychPortAudio buffers in advance where supported. The ElevenLabs utility is an offline preparation tool only and must never make network calls during an experiment.

### Block 3 — Image encoding / one-back task

Present a task-data-defined image sequence. Default timing from the existing outline is image on for 500 ms, then image off for 500 ms. The participant presses Enter when the current image is identical to the immediately preceding image. Preload all image pixels and create all Psychtoolbox textures before the first timed presentation. Log stimulus identity, one-back target status, response, accuracy, response time, and flip timestamps.

### Block 4 — VVIQ survey

Administer the Vividness of Visual Imagery Questionnaire using task-data-defined instructions, items, response labels, values, and presentation order. The PDF in `task_info/` is a reference; survey content must be represented in a runtime data file rather than hardcoded in MATLAB. Log item-level responses and response times, and compute scores only according to an explicitly documented scoring definition in task data.

## Configuration

Use one human-readable versioned config file (prefer JSON for built-in MATLAB support) with validation and documented defaults. It should control at least:

- display selection, resolution behavior, background/text/cue/photodiode colors, fonts, and text sizes;
- keyboard mappings, including Enter and an emergency abort key;
- audio device, sample rate, channel handling, and volume;
- all default phase durations and whether schedule values override defaults;
- photodiode enablement, rectangle position/size, and phase/event behavior;
- Cbmex enablement and event/comment behavior;
- debug/windowed mode and timing-check policy;
- output directory and safe resume/overwrite policy.

Timing values in a schedule take precedence only when the config explicitly selects schedule-driven timing. Never scatter adjustable constants through block code.

## Synchronization and event model

Photodiode and Cbmex support must be independently configurable. The photodiode patch is positioned at the bottom-left of the stimulus display. Both backends should consume the same canonical event structure so logged behavioral events, photodiode transitions, and neural comments can be aligned. Define stable event names/codes centrally and include at least block start/end, trial start/end, stimulus onset, audio onset, action-type reveal, action-cue onset/offset, response, and abort.

Block 2 emits paired flash/comment events at spoken-audio onset (including the word/phrase), silent-interval onset, trial-type reveal, action-cue onset, and inter-trial-interval onset. Block 3 emits them at image onset (including image ID) and every Enter response. Block 4 emits them at question onset, answer selection, and answer submission, including stable question and answer IDs. For every paired event, execute the visual photodiode flip first and send the higher-latency Cbmex comment immediately after the flip returns.

When Cbmex comments are enabled, the master launcher owns the NSP connections and task lifecycle. At block start it mirrors `TaskComment('start')`: send `$TASKSTART EMU-####` and `$TASKID ...` to all detected NSP instances and append exactly one entry to `+CurrentPatientLog` with `setNextLogEntry`. On normal completion send `$TASKSTOP`; on Escape send `$TASKKILL`; on any other uncaught block error send `$TASKERR`. Terminal lifecycle events reuse the same EMU number and do not increment the patient log.

Photodiode changes must occur on the same `Screen('Flip', ...)` as the visual event they mark. Cbmex calls must be isolated behind an adapter so the task runs normally when Cbmex is unavailable and disabled. If synchronization is enabled but initialization fails, fail before the block starts rather than silently running unsynchronized.

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

Require a Patient ID in the master block-selection GUI. Create one unique time-indexed session directory at `<configured patient-data root>/<Patient ID>/<timestamp>/` and never overwrite existing participant data. The default root is `C:\Users\EMU - Behavior\Documents\MATLAB\PatientData`. Blocks 1, 3, and 4 write behavioral responses into this patient session. Save:

- participant/session/block identifiers and timestamps;
- config snapshot and task-data manifest/version information;
- MATLAB, OS, Psychtoolbox, display, audio, and synchronization metadata;
- scheduled values and actual event/flip/audio timestamps;
- responses, correctness, and response times;
- errors, warnings, dropped/missed timing indicators, and abort state.

Use incremental tabular logging plus a final MAT file as appropriate. Preserve the original randomized Block 2 row order and record the schedule filename/hash so a run is reproducible.

## Secrets and generated assets

`task_data/speech/eleven_labs_api.txt` is a secret and must remain untracked and unread by task runtime code. The ElevenLabs generation script also remains untracked under `task_data/speech/`. It reads the key locally, generates only missing unique audio, and produces/updates an explicit one-row-per-stimulus audio manifest. Never log, print, commit, or embed the key.

## Implementation plan

1. **Scaffold and contracts** — establish launcher/GUI, config loader and schema validation, task-data manifests, output naming, logging, cleanup, and a dry-run validator.
2. **Hardware adapters** — implement Psychtoolbox display/audio/input wrappers plus no-op/real photodiode and Cbmex synchronization adapters with canonical events.
3. **Block 0** — implement data-driven paged instructions.
4. **Block 1** — implement story manifests, audio preload/playback, multiple-choice UI, scoring, and logging.
5. **Block 2** — implemented: validates the 540-row schedule and shared audio manifest, preloads all 45 unique recordings, presents all five timed phases and three action types, supports Enter-to-end-early, and logs/synchronizes every phase transition.
6. **Block 3** — define the image manifest/sequence, preload textures, implement one-back responses and timing.
7. **Block 4** — transcribe/verify the VVIQ runtime data, implement survey navigation, validation, logging, and documented scoring.
8. **Stimulus preparation** — after ElevenLabs requirements arrive, add the untracked generator and verify sample rate, channels, loudness, clipping, duration, and manifest coverage offline.
9. **Verification** — add loader/config/event unit tests, simulated short-block smoke tests, missing/corrupt-asset tests, abort/cleanup tests, and on-hardware timing/synchronization checks.

## Decisions still required

Before finalizing behavior, confirm:

- exact Block 0 instruction text and navigation rules;
- story order, comprehension questions, choices, correct answers, replay policy, and response keys;
- Block 2 on-screen wording and whether visually imagined trials also use spoken audio;
- ElevenLabs voice/model/settings and desired audio normalization/file format;
- Block 3 image set, sequence/repetition construction, response window, and late-response policy;
- authoritative VVIQ wording, scale direction, item grouping, scoring, and whether backtracking is allowed;
- lab display/audio device choices, trigger/event codes, photodiode patch geometry/polarity, and the exact Cbmex comment API expected by the acquisition setup;
- participant/session naming and required output format/location.
