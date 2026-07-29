# Imagined Speech Psychtoolbox Task

## Project goal

Build a MATLAB/Psychtoolbox experiment for an imagined-speech study. The launcher opens a small experimenter GUI with five buttons, numbered 0 through 4. Selecting a button runs that block independently so a session can begin or resume at any block.

The experiment must be data-driven. Instructions, stories, questions, words, phrases, audio, image sequences, survey items, and answer choices belong under `task_data/`; they must not be embedded in MATLAB source. All assets needed by a block are validated and loaded into memory before its first timed trial.

The launcher, config loader, hardware adapters, and all five block runners are implemented. All five blocks are now fully data-driven and preload-validated end to end (instructions, the 540-trial schedule, the 200-trial image sequence, stories/questions, and the VVIQ survey all resolve to real, finalized `task_data/` content and pass their loaders). Current source material includes:

- `task_info/experimentalstructure.txt`: the original experiment outline.
- `task_info/Vividness of Visual Imagery Questionnaire (VVIQ) (PaperSurvey.io).pdf`: the survey reference, transcribed into `task_data/surveys/vviq.json` (4 sections × 4 items, 5-point scale, documented scoring).
- `task_data/speech/AAC_trial_schedule.csv` + `task_data/speech/block1_manifest.json` + `task_data/speech/audio_clips/`: the finalized 540-trial Block 1 schedule and its 45 decoded/mapped audio clips.
- `task_data/images/`: 90 unique images and the finalized `block2_manifest.json` + `image_trial_sequence.csv` (200 trials, one-back targets marked).
- `task_data/stories/`: two MP3 stories, their DOCX source texts, and the finalized `block3_stories.json` manifest (2 stories, comprehension questions with answer keys).
- `task_data/instructions/block0_instructions.json`: finalized instruction deck (7 slides).
- `task_data/surveys/vviq.json`: finalized VVIQ runtime survey data.

Treat source documents as references, not runtime inputs. Runtime-facing instructions and questions should be transcribed into a simple validated data format under `task_data/`.

## Block definitions

Block numbering matches GUI presentation order for consistency: 0 Instructions, 1 Speech/Imagery, 2 Image Encoding, 3 Stories & Comprehension, 4 VVIQ. Blocks are still independently runnable/resumable in any order from the launcher; this ordering is purely for a single consistent numbering scheme across the GUI, config keys, output filenames, and task/Cbmex naming.

### Block 0 — Instructions

Present instruction pages loaded from task data. Support forward/back navigation and an explicit start/finish action. Do not place instruction prose in code.

### Block 1 — Randomized speech/imagery trials

The current schedule has 540 randomized trials:

- 150 spoken-word trials: 30 words × 5 repetitions.
- 150 imagined-speech word trials: 30 words × 5 repetitions.
- 90 visually imagined word trials: 18 words × 5 repetitions.
- 75 spoken-phrase trials: 15 phrases × 5 repetitions.
- 75 imagined-speech phrase trials: 15 phrases × 5 repetitions.

Each row of `AAC_trial_schedule.csv` supplies the stimulus text, trial type, silent-period duration, and inter-trial interval. The intended trial sequence is:

1. Present the word/phrase per `config.block1.presentation_mode` (`"listening"`, `"reading"`, or `"both"` — default `"both"`, matching the original listening+reading behavior) and play its associated audio for the audio duration when the mode includes listening.
2. Black-screen silence for the row/configured duration.
3. Reveal the requested action for 500 ms by default.
4. Show the action cue (a green square on black) for up to 2 s for words or 3 s for phrases by default. The participant speaks, imagines speaking, or visually imagines as requested and may press Enter to end this phase early.
5. Black-screen inter-trial interval for the row/configured duration.

When `presentation_mode` includes listening (`"listening"` or `"both"`), the stimulus presentation period is driven by actual audio playback duration (or `test_audio_max_seconds` in test mode), exactly as before. When `presentation_mode` is `"reading"` (no audio played), the presentation period instead uses the fixed, independently configurable `config.block1.reading_only_word_seconds` (default 0.5 s) or `config.block1.reading_only_phrase_seconds` (default 1.0 s) depending on whether the stimulus is a phrase. The logged onset event is named `AUDIO_ONSET` when audio plays and `STIMULUS_ONSET` otherwise; the per-trial log column is named `stimulus_onset` to cover both cases.

Stimulus-to-audio mapping must be explicit in task data; do not derive correctness-critical filenames ad hoc. Store exactly one audio file per unique stimulus and join each schedule row to that file through the audio manifest. Decode every unique audio file before the first trial and fill PsychPortAudio buffers in advance where supported (skipped entirely when `presentation_mode` is `"reading"`, since no audio device is needed). The ElevenLabs utility is an offline preparation tool only and must never make network calls during an experiment.

`config.block1.start_trial` (default 1) resumes a session partway through the 540-trial schedule instead of always starting at trial 1 — trials before it are never presented or logged (not skipped-and-marked, simply not run at all), matching the block's normal only-log-what-actually-ran behavior. A value exceeding the schedule's row count is a clear preflight error, not a silently empty block.

### Block 2 — Image encoding / one-back task

Present a task-data-defined image sequence. Default timing from the existing outline is image on for 500 ms, then image off for 500 ms. Each image is displayed at `config.block2.image_display_fraction` (default 0.6) of the window's smaller dimension, configurable rather than hardcoded. The participant presses Enter when the current image is identical to the immediately preceding image. Preload all image pixels and create all Psychtoolbox textures before the first timed presentation. Log stimulus identity, one-back target status, response, accuracy, response time, and flip timestamps.

`config.block2.start_trial` (default 1) resumes partway through the 200-trial image sequence, with the same semantics as Block 1's `start_trial` (skipped trials are simply never run, and an out-of-range value is a preflight error).

### Block 3 — Stories and comprehension

Use a black background. Present, in order:

1. Story 1 audio.
2. Story 1 multiple-choice comprehension questions.
3. Story 2 audio.
4. Story 2 multiple-choice comprehension questions.

Preload both decoded audio waveforms and all questions/choices before presentation. Record selected answers, correctness when an answer key is supplied, response times, and timestamps. Story order should come from a manifest rather than filename sorting.

`config.block3.start_position` (one of `"story_1"`, `"comprehension_1"`, `"story_2"`, `"comprehension_2"`; default `"story_1"`) resumes at any of the block's four natural segments. `"comprehension_N"` skips straight to story N's questions, bypassing its ready screen and audio playback entirely; `"story_2"`/`"comprehension_2"` additionally skip story 1 in its entirety (audio and questions both) — story 1 is never touched at all in that case, not merely fast-forwarded through.

### Block 4 — VVIQ survey

Administer the Vividness of Visual Imagery Questionnaire using task-data-defined instructions, items, response labels, values, and presentation order. The PDF in `task_info/` is a reference; survey content is represented in `task_data/surveys/vviq.json` rather than hardcoded in MATLAB. Log item-level responses and response times, and compute scores only according to the documented scoring definition in that file (sum of the 16 item values, range 16–80, higher = more vivid imagery).

## Configuration

Use one human-readable versioned config file (prefer JSON for built-in MATLAB support) with validation and documented defaults. It should control at least:

- display selection, resolution behavior, background/text/cue/photodiode colors, fonts, and text sizes;
- keyboard mappings, including Enter, an emergency abort key, a deselect key (`keys.deselect`, default BackSpace) that lets a participant clear a picked-but-not-yet-submitted multiple-choice answer to reconsider it, and a pause key (`keys.pause`, default `p`) — neither may ever be mapped to Escape, which always means "abort the task";
- audio device, sample rate, channel handling, and volume;
- all default phase durations and whether schedule values override defaults;
- photodiode enablement, rectangle position/size, flash duration (`photodiode.flash_frames`, in refresh frames), and phase/event behavior;
- Cbmex enablement and event/comment behavior, and matcbsdk enablement and event/comment behavior as an alternate NSP comment backend (never both at once — see below);
- audio-sync tone enablement (default off), output device, sample rate, default volume, and each tone's frequency/duration/optional volume override;
- debug/windowed mode and timing-check policy;
- output directory and safe resume/overwrite policy.

Timing values in a schedule take precedence only when the config explicitly selects schedule-driven timing. Never scatter adjustable constants through block code.

`display.screen_index` is a raw Psychtoolbox screen index, not the Windows display number, and the two do not necessarily agree. On this multi-monitor Windows machine, PTB screen 0 is the combined virtual desktop spanning *all* physical monitors (opening fullscreen there stretches across every screen at once, which looks neither properly fullscreen nor windowed); screen 1 is the primary monitor and screen 2 is the secondary monitor. Re-verify this mapping with `Screen('Screens')` / `Screen('Rect', index)` any time monitors, cables, or this machine change, rather than assuming screen 0 means "main screen."

## Synchronization and event model

Photodiode, Cbmex, and audio-sync tones must all be independently configurable. The photodiode patch is positioned at the bottom-left of the stimulus display. All three backends should consume the same canonical event structure so logged behavioral events, photodiode transitions, audio-sync tones, and neural comments can be aligned. Define stable event names/codes centrally and include at least block start/end, trial start/end, stimulus onset, audio onset, action-type reveal, action-cue onset/offset, response, and abort.

Block 1 emits paired flash/comment events at spoken-audio onset (including the word/phrase), silent-interval onset (which doubles as word/phrase offset — the screen transitions directly from stimulus-visible to blank in the same flip), trial-type reveal, action-cue onset, and inter-trial-interval onset (which doubles as action-cue offset). Block 2 emits them only at image onset (`IMAGE_ONSET`) and every Enter response (`RESPONSE`) — the image-off transition is deliberately silent (no flash, no comment): an earlier attempt at a paired `IMAGE_OFFSET` event made proccing worse, not better, because a `RESPONSE` flash landing near that transition would sit close enough to it to blend together on the photodiode. The next trial's `IMAGE_ONSET` is also deliberately delayed past a late `RESPONSE` flash's own completion (participants often react after the image has already gone off-screen) so that flash and the following trial's onset flash can't blend into each other either — see `respFlashEnd`/`flashOff` handling in `run_block_2.m`. Blocks 3 and 4 emit them at question/item onset, every Up/Down highlight-navigation press (`HIGHLIGHT_MOVE`, identifying the direction and resulting highlighted choice), answer selection (`ANSWER_PICK`), an optional answer deselection (`ANSWER_DESELECT`, fired when the participant presses the deselect key to clear a pick and reconsider — this can repeat any number of times before submission) and answer submission (`ANSWER_SUBMIT`), including stable question/item and answer IDs. For every paired event, execute the visual photodiode flip first and send the higher-latency Cbmex comment immediately after the flip returns. More generally: any two flash events that can occur close together in time (one on a fixed schedule, one triggered by an unpredictable participant response) are a proccing-reliability risk — either don't flash the scheduled transition at all (Block 2's image-off), or delay the scheduled one until the response flash has cleared (Block 2's next-trial onset).

Every photodiode flash is held on for `photodiode.flash_frames` refresh cycles (default 3), not just a single frame: the "turn it off" flip is scheduled `(flash_frames - 0.5) * ifi` after the onset flip, using the same "land on the very next eligible vsync" trick as a 1-frame flash, just extended across more frames. A single-frame pulse is right at the edge of what most photodiode/DAQ setups can reliably catch — any minor GPU/OS scheduling jitter and a given pulse may simply not register, which is the leading suspect behind inconsistent photodiode proccing observed in testing. `display.skip_sync_tests` stays `true` (the original default): trying `false` on this machine surfaced Psychtoolbox's `SYNCHRONIZATION FAILURE` hard-abort against Windows' DWM desktop compositor, which cannot be fully disabled on Windows 10/11 — this is a well-known, common PTB-on-Windows false positive (PTB's sync test is often unreliable in the presence of DWM even when actual presentation timing is fine), not evidence the machine can't present timed stimuli, and it blocked every block from opening a window at all. `photodiode.flash_frames` is the actual mitigation for the inconsistent-flash symptom; it does not depend on `skip_sync_tests`.

Every block also raises MATLAB's OS scheduling priority to `MaxPriority(window)` immediately after opening its window (each block's cleanup already reset it to 0, implying this was always intended but had never actually been done). Without it, MATLAB runs at normal OS priority for the entire timed trial loop, making a `Screen('Flip', ...)` call more likely to be delayed past its target by OS-level preemption (background processes, driver activity, the DWM compositor's own scheduling) — a direct, plausible cause of intermittent (not systematic) dropped/mistimed flashes, independent of pulse width. Cbmex comment-sending (`send_task_event_comment.m`) is architecturally independent of the display/compositor pipeline: `cbmex('comment', ...)` either succeeds or throws (uncaught, propagating all the way up to the block's error handler and a visible `$TASKERR`/crash) — there is no code path where a comment is silently dropped while the block keeps running. So a trial where the photodiode fails to visually flash should still have gotten its comment sent and logged; if the NSP-side record doesn't show it, that points to something in the acquisition chain past MATLAB rather than in this codebase.

When Cbmex comments are enabled, the master launcher owns the NSP connections and task lifecycle. At block start it mirrors `TaskComment('start')`: send `$TASKSTART EMU-####` and `$TASKID ...` to all detected NSP instances and append exactly one entry to `+CurrentPatientLog` with `setNextLogEntry`. On normal completion send `$TASKSTOP`; on Escape send `$TASKKILL`; on any other uncaught block error send `$TASKERR`. Terminal lifecycle events reuse the same EMU number and do not increment the patient log. The task/Cbmex identifier (`$TASKID`) is named `<cbmex.task_name>_<BlockName>_<PatientID>` — e.g. `ImaginedSpeech_SpeechImagery_<PatientID>` — using the compact per-block name from `src/core/task_block_name.m` (`Instructions`, `SpeechImagery`, `ImageEncoding`, `StoriesComprehension`, `VVIQ`) rather than a bare block number, so the name alone identifies which block a recording belongs to. `finish_task_lifecycle` sends the terminal comment to every NSP instance first and only closes connections afterward (in a separate pass, after a brief flush pause), rather than interleaving comment-then-close per instance, so a connection teardown cannot race the comment it was supposed to carry.

The `+CurrentPatientLog` EMU-number allocation (`getNextLogEntry`/`setNextLogEntry`) is optional per backend — `cbmex.use_patient_log` / `matcbsdk.use_patient_log` (both required booleans; not every rig has that patient log set up, and `getNextLogEntry` errors outright if it isn't). When a backend's flag is `false`, `start_task_lifecycle` never calls `getNextLogEntry`/`setNextLogEntry` at all, and every `$TASKSTART`/`$TASKID`/`$TASKSTOP`/`$TASKKILL`/`$TASKERR` comment uses the patient ID directly (`lifecycle.id_label`) in place of an `EMU-####` label. When it's `true` (the default for both backends), behavior is unchanged from before this flag existed.

### Comment backend: Cbmex vs. matcbsdk

`config.matcbsdk` is an alternate NSP comment backend to `config.cbmex`, for computers (like this one) where Blackrock Central/cbmex isn't installed but the compiled `matcbsdk` MEX wrapper around `cbsdk.dll` is (`C:\Users\lizzi\Documents\CereLink\Matlab\cerelink`, exposing a `Session` classdef: `s = Session("NSP"); s.send_comment(text, rgba, charset); s.close();`). `load_task_config` errors if `cbmex.enabled` and `matcbsdk.enabled` are both true — exactly one comment backend may be active at a time. Both `Session.m` and `matcbsdk.mexw64` are expected to already be on MATLAB's path (the same assumption already made for `cbmex`/`getIPAddressesFromPortNames`/`getNextLogEntry`/`setNextLogEntry` — none of them are added to path by this project; they're installed once, machine-wide, outside the repo).

Architecturally the two backends are triggered identically from block code (`send_task_event_comment`, `start_task_lifecycle`, `finish_task_lifecycle` all branch on `lifecycle.backend`), but their connection model differs: cbmex addresses each physical NSP by IP (via `getIPAddressesFromPortNames({'NSP1','NSP2'})`) and a numeric `instance`; matcbsdk's `Session` wrapper has no equivalent IP discovery, so it instead opens one `Session` per name in `config.matcbsdk.device_types` (default `["NSP"]`; a multi-NSP Central setup would use e.g. `["HUB1","HUB2"]`, matching `Session`'s supported device-type names). `$TASKID` suffixing for multiple connections uses `_NSP-1`/`_NSP-2` (positional) for cbmex and `_<device_type>` for matcbsdk. The EMU-number allocation and `+CurrentPatientLog` increment (`getNextLogEntry`/`setNextLogEntry`) are backend-agnostic and happen exactly the same way regardless of which is active. `config.comment_lifecycle` (set once by the launcher, read by every block) replaces the old `config.cbmex.lifecycle` slot so blocks don't need to know or care which backend is live.

Photodiode changes must occur on the same `Screen('Flip', ...)` as the visual event they mark. Cbmex/matcbsdk calls must be isolated behind an adapter so the task runs normally when neither is available and enabled. If synchronization is enabled but initialization fails, fail before the block starts rather than silently running unsynchronized. Every block's screen-cleanup routine wraps each of `ShowCursor`/`Priority(0)`/`Screen('CloseAll')`/`Screen('Preference', 'SkipSyncTests', ...)` in its own try/catch so one failing teardown step cannot skip the rest; Block 2 (Image Encoding) additionally must never close its Psychtoolbox textures more than once — they are closed exactly once, via the `onCleanup` handler registered right after they're created, on every exit path (normal completion, Escape, or error), never redundantly at the end of the trial loop, since double-closing a texture handle is a double-free that can crash MATLAB outright.

### Audio sync tones

`audio_sync` (default `enabled: false`) is a third synchronization channel, independent of photodiode and Cbmex/matcbsdk: short synthesized pure tones, played through their own dedicated PsychPortAudio device (`audio_sync.device_index`, default -1 = system default) so tone playback never competes with a block's own stimulus-audio buffer. Every tone's frequency and duration is configured under `audio_sync.tones` and preloaded (synthesized once, with a short fade to avoid clicks) before the ready screen, never during a timed trial. When disabled, no audio device is opened at all — zero overhead or hardware dependency. Each tone plays at `audio_sync.volume` unless it declares its own `audio_sync.tones.<name>.volume` override (validated to the same `(0, 1]` range) — used for tones that are meant to read as quieter/more understated than the block-level default, without changing every other tone's loudness.

Each of Blocks 0-4 plays `block_start` once, right as its timed content begins (after the ready/intro gate, or before the first slide for Block 0), and `block_end` exactly once at the very end of the run — via an `onCleanup`-registered call so it fires on normal completion, abort, and error alike, matching the block's `finish_task_lifecycle` symmetry. Additional per-context tones: `block1_reading_stimulus_onset` (only when `presentation_mode` is `"reading"`, at the same moment the word/phrase appears with no audio); `block1_early_response` (when the participant presses Enter to end the action-cue phase early — deliberately a different tone from the reading-onset one); `block1_action_cue_onset` and `block1_action_cue_offset` (the green action cue appearing, and it disappearing as the inter-trial interval begins — both quieter than the block-level default, per `volume: 0.15`); `block2_image_onset` and `block2_response` (image presentation vs. the one-back Enter response — deliberately distinguishable tones, and Block 2's only two tone triggers by design; also quieter, `volume: 0.15`, matching Block 1's new cue tones); `block3_question_onset` (every comprehension question); `block4_question_onset` (every VVIQ item). Tone playback is fire-and-forget (non-blocking), so it never delays the phase it marks, the same way the Cbmex/matcbsdk comment never blocks on the photodiode flip.

### Pause and resume (Blocks 1-3)

Pressing `keys.pause` (default `p`) during a timed phase in Block 1, Block 2, or Block 3 shows a "PAUSED" screen (via the shared `src/core/wait_for_pause_resume.m`) and blocks until `keys.pause` is pressed again — Escape still aborts immediately even from the pause screen. Every deadline or audio-playback position in flight is shifted forward by exactly the elapsed pause duration before resuming, so the participant picks up exactly where they left off rather than losing the remainder of a phase to the pause. Pausing is available in every one of Block 1's phases (stimulus presentation — including mid-audio-playback, silence, trial-type reveal, action cue, and inter-trial interval) and Block 2's image-on/image-off phases; in Block 3 it is deliberately scoped to story audio playback only, per the original request — the comprehension-question UI is not pausable (there's no time pressure there to begin with; a participant can already leave a question unanswered indefinitely).

All three sync channels fire on pause/resume, handled centrally in `wait_for_pause_resume.m` so callers don't each reimplement it: the photodiode is pulsed on then off at pause-onset, and again at resume, exactly like every other paired visual event; if `audio_sync` is enabled, a low-volume `pause_on` tone plays at pause-onset and `pause_resume` at resume (`volume: 0.1`, quieter than every other tone tier, since these are pure timekeeping markers rather than task-relevant cues); `PAUSE_ON`/`PAUSE_RESUME` are logged/commented through each block's own per-trial emit function (matching every other event in that block, not a special case), since only the caller has the trial/story context needed for that.

Pausing mid-audio (Block 1's word/phrase clips, Block 3's story audio) actually stops the PsychPortAudio buffer at its exact playback position (`GetStatus().PositionSecs`), then on resume re-fills the buffer with only the remaining samples and restarts — genuinely continuing the audio rather than replaying it from the start or leaving a silent gap. The resumed `PsychPortAudio('Start', ..., waitForStart=1)` call deliberately blocks until playback has truly begun: a non-blocking start can return before `GetStatus().Active` flips true, which would make the very next status poll see `Active=0` and exit the wait loop as though the audio had already finished.

**Both Block 1's and Block 3's audio-wait loops were originally driven by `while PsychPortAudio('GetStatus', h).Active`** (i.e., the loop kept polling for keys only as long as the audio device reported itself active). On real hardware this left Block 3's Escape/pause completely undetected for the entire story — reported directly by the user testing live, not caught by static review — while Block 1's word/phrase clips (only ~1-3 s) were short enough that the same latent bug was never actually exercised there, giving the illusion it only affected Block 3. Fixed by making both loops deadline-driven instead: the analytically-known clip/story duration (`size(samples,2)/sample_rate`) sets the stopping condition, exactly like every other already-reliable pausable phase (silence, reveal, ITI, image-on/off), and `GetStatus()` is only ever consulted transiently to read `PositionSecs` when a pause is actually requested — never as the thing deciding whether the wait loop keeps checking for keys at all.

Each pausable wait function redraws its own current phase's visual (stimulus text, the green cue, blank, etc.) immediately after a non-aborted resume, since the pause overlay has overwritten whatever was on screen; this is passed in as a small redraw closure from the call site; `wait_for_pause_resume` itself only knows how to draw the generic pause screen.

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

Require a Patient ID in the master block-selection GUI. Create one unique time-indexed session directory at `<configured patient-data root>/<Patient ID>/ImaginedSpeech/<timestamp>/` and never overwrite existing participant data. The `ImaginedSpeech` subfolder keeps this task's sessions distinguishable from other tasks' output that may also write into the same per-patient directory, rather than every task's timestamp folders being dumped side by side directly under the patient ID. The default root is set in `config/task_config.json` under `paths.patient_data` and must match the Windows profile that actually runs the task on the current machine (currently `C:\Users\EMU - Behavior\Documents\MATLAB\PatientData` on this computer). Blocks 1, 2, 3, and 4 write behavioral responses into this patient session. Save:

- participant/session/block identifiers and timestamps;
- config snapshot and task-data manifest/version information;
- MATLAB, OS, Psychtoolbox, display, audio, and synchronization metadata;
- scheduled values and actual event/flip/audio timestamps;
- responses, correctness, and response times;
- errors, warnings, dropped/missed timing indicators, and abort state.

Each of Blocks 1-4 calls `src/core/save_run_snapshot.m` once, immediately after opening its CSV logs and before the ready screen (i.e., before any timed trial), writing `block{N}_{runId}_config.mat` into the session directory. That MAT file holds the entire resolved `config` struct (so any adjustable setting — Block 1's `presentation_mode`, reading-only durations, and scheduled-vs-default silence/ITI flags; Block 2's `image_display_fraction`; timing/color/size settings for every block — is reconstructable per run), MATLAB/OS/Psychtoolbox/hostname environment metadata, and a `content_sources` list of every task-data file that determined that run's stimuli (manifest, schedule, audio manifest, survey file, story audio), each with a SHA-256 hash via `src/core/compute_file_hash.m`. This directly supports re-running the same speech/imagery schedule, image sequence, or story order later and knowing definitively whether the underlying task-data file changed between runs. The snapshot is written once per run (config/content selection do not change mid-run), while the pre-existing per-trial CSV logs continue to carry the presented-stimulus identity for every trial that actually executed — so an aborted run still leaves an accurate, non-misleading record of only the trials that ran, never a phantom record of trials that didn't.

Use incremental tabular logging plus a final MAT file as appropriate. Preserve the original randomized Block 1 row order and record the schedule filename/hash so a run is reproducible.

## Secrets and generated assets

`task_data/speech/eleven_labs_api.txt` is a secret and must remain untracked and unread by task runtime code. The ElevenLabs generation script also remains untracked under `task_data/speech/`. It reads the key locally, generates only missing unique audio, and produces/updates an explicit one-row-per-stimulus audio manifest. Never log, print, commit, or embed the key.

## Implementation plan

1. **Scaffold and contracts** — done: launcher/GUI, config loader and schema validation, task-data manifests, output naming, logging, cleanup.
2. **Hardware adapters** — done: Psychtoolbox display/audio/input wrappers plus no-op/real photodiode and Cbmex synchronization adapters with canonical events (`send_task_event_comment`, `start_task_lifecycle`, `finish_task_lifecycle`).
3. **Block 0** — done: data-driven paged instructions, 7 slides, forward/back navigation.
4. **Block 1** — done: validates the 540-row schedule and shared audio manifest, preloads all 45 unique recordings, presents all five timed phases and three action types, supports a configurable listening/reading/both presentation mode with independent reading-only durations, supports Enter-to-end-early, and logs/synchronizes every phase transition.
5. **Block 2** — done: 90-image manifest/sequence (200 trials), texture preload, one-back responses (hit/miss/false-alarm/correct-rejection), configurable on-screen image size, and timing/logging.
6. **Block 3** — done: story manifests, audio preload/playback via PsychPortAudio, multiple-choice UI with pick/deselect/submit, scoring against answer keys, and logging.
7. **Block 4** — done: runner, navigation (including pick/deselect/submit), validation, logging, and scoring are implemented, and `task_data/surveys/vviq.json` now holds the full 16-item VVIQ (4 scenarios × 4 items, transcribed from the reference PDF) with the standard Marks (1973) 1–5 vividness scale and documented sum-based scoring (16–80, higher = more vivid).
8. **Stimulus preparation** — after ElevenLabs requirements arrive, add the untracked generator and verify sample rate, channels, loudness, clipping, duration, and manifest coverage offline.
9. **Verification** — loader smoke tests (config, all five block content loaders, patient-session creation), config validation for the Block 1/2/keys fields (valid and invalid values), and end-to-end `save_run_snapshot` writes/reads for Blocks 1-4 have all been run manually via MATLAB `-batch`, most recently after the block renumbering below. Live Psychtoolbox window tests (`Screen('OpenWindow', ...)`) cannot be run from this non-interactive environment (they hang with no attached interactive desktop session) — Block 1/2/3/4 visual/timing changes (presentation modes, image size, deselect control) have been verified by static code check (`checkcode`) and manual logic review only, not a live run. No formal automated test suite exists yet under `tests/`.
10. **Block renumbering** — done: block numbers were reordered so GUI presentation order, config keys (`config.block1`-`config.block3`), `.m` filenames/function names, `task_data/` manifest filenames, output CSV/MAT file prefixes, and audio-sync tone names all agree: 0 Instructions (unchanged), 1 Speech/Imagery (was 2), 2 Image Encoding (was 3), 3 Stories & Comprehension (was 1), 4 VVIQ (unchanged). Cbmex `$TASKID` naming was changed at the same time to use a compact block name (via `src/core/task_block_name.m`) instead of a bare block number.
11. **Task lifecycle crash + photodiode reliability** — done: fixed a double-close-on-textures bug in Block 2 that could crash MATLAB outright at block end (before `$TASKSTOP` could be sent) instead of raising a catchable error; hardened every block's screen-cleanup calls with individual try/catch; split `finish_task_lifecycle`'s comment-send and connection-close into separate passes with a flush pause. Verified end-to-end against this machine's live NSP hardware: normal completion, Escape, and simulated-error paths all correctly send `$TASKSTOP`/`$TASKKILL`/`$TASKERR` and close connections cleanly with no crash. Separately, widened every photodiode flash from a single refresh frame to `photodiode.flash_frames` frames (default 3), since a single-frame pulse is the leading suspect for photodiode flashes intermittently not registering, and added `HIGHLIGHT_MOVE` flash/comment events for Up/Down navigation in Blocks 3 and 4. Trying `display.skip_sync_tests: false` as a further diagnostic step immediately hard-aborted every block on this machine with a PTB `SYNCHRONIZATION FAILURE` against the Windows DWM compositor (a known PTB-on-Windows-10/11 false-positive, not proof of a real presentation problem), so it was reverted back to `true`; `flash_frames` remains the actual fix in place. Block 2 still proc'd inconsistently after `flash_frames` alone, traced to a second, block-2-specific cause: an `IMAGE_OFFSET` flash was briefly added then removed again after root-causing that it (and, separately, the following trial's `IMAGE_ONSET`) could land close enough to an unpredictable `RESPONSE` flash to blend together on the photodiode — Block 2 is the only block where a participant response can occur at an arbitrary time inside a phase that is otherwise on a fixed schedule. Fixed by never flashing the image-off transition and by delaying the next trial's onset until any pending `RESPONSE` flash has fully completed (`respFlashEnd + flashOff`, in `run_block_2.m`). Block 2 was still reported as intermittently missing flashes after that fix; added `Priority(MaxPriority(window))` to every block right after opening its window (all five blocks' cleanup already reset `Priority(0)`, implying this was always intended but had never actually been called), since running at normal OS priority through the whole timed trial loop makes a Flip more likely to be delayed past its target by OS-level preemption — a plausible cause of intermittent, not systematic, dropped flashes, independent of pulse width. None of this has been visually verified against a live Psychtoolbox window or a physical photodiode from this non-interactive environment — needs a console check, including whether `Priority` resolved the remaining Block 2 intermittency or whether `flash_frames` needs to go higher still.

## Decisions still required

Before finalizing behavior, confirm:

- Block 1 on-screen wording and whether visually imagined trials also use spoken audio;
- ElevenLabs voice/model/settings and desired audio normalization/file format;
- lab display/audio device choices, trigger/event codes, photodiode patch geometry/polarity, and the exact Cbmex comment API expected by the acquisition setup;
- participant/session naming and required output format/location;
- a live on-hardware check of Block 1 (all three presentation modes) and Block 2 (new image size) the next time the physical task computer/console is available, since those changes have not yet been visually verified;
- a live check with the actual photodiode/DAQ hardware confirming `photodiode.flash_frames: 3` reliably registers on every event now (vs. the prior single-frame pulse) — if it's still inconsistent, `flash_frames` may need to go higher, or the issue may be elsewhere in the acquisition chain rather than pulse width;
- the stimulus display (`screen_index: 2`) measured its refresh interval at ~31.25 ms (~32 Hz) during a sync-test attempt — unusually low for a modern monitor. Worth confirming in Windows display settings whether that screen is actually intentionally running at ~32 Hz or whether something is misconfigured, since a lower-than-expected refresh rate changes how many milliseconds `flash_frames` frames actually spans.
