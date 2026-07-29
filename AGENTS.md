# Repository Working Agreement

## Mission

Implement the MATLAB/Psychtoolbox imagined-speech experiment described in `CLAUDE.md`. Read `CLAUDE.md` before changing runtime behavior. Keep the task runnable by block (0–4), deterministic, data-driven, preload-first, timing-aware, and safe around participant data and lab hardware.

## Current repository state

The launcher, config loading/validation, hardware adapters, and all five block runners are implemented (`run_imagined_speech.m`, `src/config/`, `src/core/`, `src/io/`, `src/blocks/`). All five blocks have finalized `task_data/` content (instructions, story manifests with answer keys, the 540-trial speech/imagery schedule with its 45-clip audio manifest, the 200-trial image one-back sequence with 90 images, and the 16-item VVIQ survey transcribed from the reference PDF) and their loaders have been smoke-tested via MATLAB `-batch` on this machine. Do not assume every asset is finalized merely because a file exists, though — always spot-check before relying on memory of this state.

Block numbering matches GUI presentation order: 0 Instructions, 1 Speech/Imagery, 2 Image Encoding, 3 Stories & Comprehension, 4 VVIQ. Block 1 supports a configurable `presentation_mode` (`listening`/`reading`/`both`, default `both`) with independently configurable reading-only durations for words vs. phrases; Block 2's on-screen image size is configurable via `block2.image_display_fraction`. Blocks 3 and 4 support a deselect key (`config.keys.deselect`, default BackSpace, never Escape) that clears a picked-but-unsubmitted multiple-choice answer so the participant can reconsider it, emitting a paired photodiode/comment `ANSWER_DESELECT` event. Every block from 1-4 calls `src/core/save_run_snapshot.m` once per run (right after opening its CSV logs, before any timed trial) to write `block{N}_{runId}_config.mat` into the session directory: the full resolved config, MATLAB/OS/Psychtoolbox/hostname metadata, and SHA-256 hashes (via `src/core/compute_file_hash.m`) of every task-data file that determined that run's content — so which manifest/schedule/survey version produced a given dataset is always reconstructable, without duplicating that into the already-incremental per-trial CSVs. Cbmex `$TASKID` naming uses a compact per-block name (`src/core/task_block_name.m`: `Instructions`, `SpeechImagery`, `ImageEncoding`, `StoriesComprehension`, `VVIQ`) rather than a bare block number, e.g. `ImaginedSpeech_SpeechImagery_<PatientID>`.

A third sync channel, `audio_sync` (default disabled), plays short synthesized pure tones through a dedicated PsychPortAudio device — separate from any block's stimulus-audio handle — via `src/core/{build_sync_tone,init_sync_tones,play_sync_tone,finish_sync_tones}.m`. All 5 blocks play `block_start`/`block_end` (the latter via `onCleanup`, so it fires on success/abort/error alike); Block 1 adds `block1_reading_stimulus_onset` (reading-mode only) and `block1_early_response` (distinct tone), Block 2 adds `block2_image_onset` and `block2_response` (distinct tones), Block 3 adds `block3_question_onset`, Block 4 adds `block4_question_onset`. Confirmed on this machine that PsychPortAudio — unlike `Screen('OpenWindow', ...)` — works fine from this non-interactive shell (no interactive-desktop dependency), including two simultaneous handles to the same default device, so all audio-sync tone playback was verified end-to-end (audibly played, and config validation exercised for missing/invalid tone specs) rather than only statically checked.

These changes were verified via MATLAB static code check (`checkcode`), config-validation tests (valid and invalid values), a full loader regression pass, and end-to-end snapshot-save/read and tone-playback tests. Opening a real `Screen('OpenWindow', ...)` window still hangs when attempted from this non-interactive shell, so any change touching Block 0/1/2/3/4 visuals, timing, or key handling still needs a live check at the physical console before being trusted on hardware — audio-only changes (the sync tones) do not have this limitation. No `tests/` directory exists yet; verification so far has been manual data-loader smoke tests plus static checks, not an automated suite.

**Important discovery**: unlike `Screen`, `cbmex` genuinely works from this non-interactive shell when `config.cbmex.enabled` is true — it connects to this machine's real NSP1/NSP2 hardware and can append real entries to the live `+CurrentPatientLog`. Be careful with any script that calls `start_task_lifecycle`/`finish_task_lifecycle` against the live config: an uncaught bug in a *test* script (e.g. forgetting to set `config.session.patient_id`) can trigger a real `$TASKSTART`/`$TASKID`/`$TASKERR` cycle and increment the real patient log, not a harmless no-op — this happened twice while testing. Always use an obviously-fake patient ID and get explicit confirmation before running lifecycle code against the live config from this environment.

A prior end-of-block crash (MATLAB dying outright instead of sending `$TASKSTOP`) was traced to Block 2 (Image Encoding) closing its Psychtoolbox textures twice — once explicitly at the end of the trial loop, again via the `onCleanup` handler that already runs on every exit path. Double-closing a texture handle is a double-free that can crash the process rather than raising a catchable MATLAB error, which is why it bypassed `run_imagined_speech.m`'s try/catch entirely. Fixed by removing the redundant explicit close; all blocks' screen-cleanup calls were also hardened with individual try/catch. Verified end-to-end against live NSP hardware (see above) that normal completion, Escape, and error paths now correctly send `$TASKSTOP`/`$TASKKILL`/`$TASKERR` and close connections without crashing.

Separately, every photodiode flash was widened from exactly one refresh frame to `photodiode.flash_frames` frames (default 3) — a single-frame pulse was the leading suspect for flashes intermittently not registering on the physical photodiode. Blocks 3 and 4 gained a `HIGHLIGHT_MOVE` flash/comment on every Up/Down navigation press. Trying `display.skip_sync_tests: false` was a further diagnostic attempt but backfired hard: on this machine it makes Psychtoolbox hard-abort every block with a `SYNCHRONIZATION FAILURE` against the Windows DWM desktop compositor (which cannot be fully disabled on Windows 10/11) — a well-documented PTB-on-Windows false positive, not evidence of an actual presentation-timing problem — so it's back to `true`. Keep `skip_sync_tests: true` on this machine unless someone specifically wants to fight the DWM/PTB interaction; `flash_frames` is the fix that actually matters for the photodiode symptom and doesn't depend on it.

Block 2 kept proccing inconsistently even after `flash_frames`, for a reason specific to it: it's the only block where a participant response can land at an arbitrary time inside an otherwise fixed-schedule phase, so its `RESPONSE` flash could end up close enough to a scheduled transition's own flash to blend together on the photodiode. A briefly-added `IMAGE_OFFSET` flash on the image-off transition made this worse (it collided with `RESPONSE` flashes from the on-phase); it was removed, that transition is now flash/comment-silent, and the *following* trial's `IMAGE_ONSET` is delayed until any pending `RESPONSE` flash has fully completed (see `respFlashEnd` handling in `run_block_2.m`) so a late off-phase response can't collide with it either. General lesson for any future sync work here: two flashes close in time is the failure mode to watch for, not missing code — one comes from a fixed schedule, the other from an unpredictable participant action, and they need either a guaranteed minimum gap or one of them dropped.

Block 2 was still reported as intermittently dropping flashes after that fix, with `$TASKSTART`/`$TASKID`/comments during the block otherwise sending fine. Found that none of the five blocks ever actually raise MATLAB's OS scheduling priority, despite every block's cleanup resetting `Priority(0)` — a leftover expectation from priority having been raised that was apparently never implemented. Added `Priority(MaxPriority(window))` right after each block opens its window. `send_task_event_comment.m` is architecturally decoupled from Screen/the compositor — a `cbmex('comment', ...)` failure is uncaught and propagates to a visible `$TASKERR`/crash, so there's no path for a comment to silently drop while the block keeps running; a trial with a missed visual flash should still have a comment logged on the NSP side, which is worth cross-checking empirically against the physical photodiode channel if the intermittency persists. None of this has been visually verified against a live Psychtoolbox window or physical photodiode from this environment — needs a console check.

## Non-negotiable constraints

- Never hardcode participant-facing stimuli, instructions, questions, choices, answer keys, image order, story order, or survey content in MATLAB.
- Put runtime content in validated manifests/schedules beneath `task_data/`. Code may contain only generic UI labels and stable event identifiers.
- Load and validate every asset required by the chosen block before the block begins. Do no file/network/document parsing or media decoding during timed trials.
- Treat timing as scheduled Psychtoolbox activity: anchor durations to measured flip/audio timestamps, not chained wall-clock pauses.
- Photodiode and Cbmex must be independently toggleable in config and routed through a shared canonical event layer.
- The master launcher, not individual blocks, owns Cbmex connections and lifecycle comments. With comments enabled it must mirror the lab `TaskComment` contract: TaskStart/TaskID plus one patient-log increment, then exactly one of TaskStop, TaskKill, or TaskErr using the same EMU number.
- When a configured synchronization backend fails to initialize, stop before collecting block data. Disabled backends must use no-op adapters without requiring lab hardware.
- Always provide a single emergency-abort path and guaranteed cleanup for `Screen`, PsychPortAudio, cursor visibility, keyboard restrictions/queues, priority, and Cbmex resources. Use `onCleanup` and top-level `try/catch` protection.
- Save incrementally to the launcher-created, time-indexed patient session path. Blocks 1, 3, and 4 must write behavioral data there. Do not overwrite or delete participant results.
- Do not read, print, copy, or commit `task_data/speech/eleven_labs_api.txt`. Do not commit the future ElevenLabs generation script or generated speech files unless the user explicitly changes this policy.

## Preferred architecture

Keep the public entry point small. A suitable decomposition is:

```text
run_imagined_speech.m       launcher, participant/session input, block GUI
config/                     versioned runtime configuration
src/config/                 loading and validation
src/core/                   PTB setup, cleanup, clocks, logging, events
src/io/                     block-specific manifests and preloaders
src/sync/                   photodiode, Cbmex, and no-op adapters
src/blocks/                 one runner per block
tests/                      unit tests and short fixture-based smoke tests
task_data/                  external runtime content and media
```

This layout is a guide, not permission to create empty abstractions. Prefer small MATLAB functions with explicit inputs/outputs over scripts, globals, persistent hidden state, or a single monolithic task file.

Represent loaded state explicitly, for example with `config`, `session`, `devices`, `buffers`, and `logger` structs. Block runners should not reinitialize shared hardware unnecessarily and should not access secrets.

## Data contracts

Define and validate schemas before implementing each block. Prefer JSON for nested manifests/questions and CSV for trial schedules. Store relative asset paths relative to the manifest (or define one documented project-root convention); reject traversal outside approved task-data roots.

At minimum:

- Block 0 manifest: ordered page IDs and page content (or referenced UTF-8 text files).
- Block 1 manifest: ordered story IDs, audio paths, ordered questions, choices, and optional correct-choice IDs.
- Block 2 schedule: `trial_number`, `word`, `trial_type`, `silent_period_duration`, `inter_trial_interval_duration`, plus an explicit one-row-per-unique-stimulus audio manifest mapping stable stimulus ID/text to one shared file.
- Block 3 manifest/schedule: trial number, image ID/path, and intended one-back target status (or enough explicit sequence information to validate it).
- Block 4 manifest: survey/version metadata, ordered item IDs/text, response labels/values, and documented scoring metadata.

Use stable IDs in logs; display text is not a safe primary key. Validate schedules for row count/order, allowed trial types, finite nonnegative durations, referenced files, duplicate IDs, expected repetitions, and consistency between declared and computed targets.

## Timing and input rules

- Use `Screen('Flip', window, when)` and returned timestamps for visual timing.
- Use PsychPortAudio for low-latency playback and capture actual start timing when available.
- Use keyboard queues for responses when timing matters; debounce launcher/survey navigation.
- Normalize key names with `KbName('UnifyKeyNames')`.
- Convert desired durations to refresh-aware deadlines and log missed flips.
- Create textures and decoded audio buffers before the ready screen, then reuse and explicitly release them.
- The experiment display remains black unless task data/config specifies otherwise. The green action cue and photodiode patch must be drawn before the same flip used to timestamp their onset.

## Event and logging rules

Maintain a central event dictionary with stable, documented names/codes. A single event emission call should:

1. timestamp the behavioral event;
2. append it to the recoverable log;
3. issue the configured Cbmex comment;
4. coordinate the configured photodiode state for flip-bound visual events.

Do not claim sub-frame simultaneity between software comments, audio, and display. Log the distinct timestamps and measured relationships. Include block/trial/stimulus/action identifiers in events without exceeding acquisition-system comment limits.

## Development sequence

Follow the implementation stages in `CLAUDE.md`. Before building a block, first add its schema/validator and a minimal fixture. Before running a full 540-trial block, prove the same path with a short schedule. Hardware-free development must work in debug mode with synchronization disabled; hardware integration is a separate verification step, not a reason to bypass validation.

Do not invent missing scientific content or acquisition codes. Add an explicit placeholder/schema and surface a clear preflight error describing what is missing. Ask the user when a decision changes experimental meaning.

## Verification expectations

For every material change:

- run MATLAB unit tests when MATLAB is available;
- otherwise perform static/data validation that is possible locally and state what could not be run;
- test success, abort, missing asset, malformed schedule/config, disabled hardware, and enabled-but-unavailable hardware paths as relevant;
- keep test fixtures small and synthetic; do not duplicate participant stimuli into source code;
- inspect Git status and avoid modifying unrelated/user-owned files.

Timing acceptance must ultimately be checked on the actual acquisition computer with its display, audio interface, photodiode, and Blackrock/Cerebus setup. Desktop smoke tests cannot establish neural synchronization accuracy.

## Secrets and generated files

The ElevenLabs API key and local generator are preparation-only artifacts. Ensure ignore rules cover the exact secret/script/generated-output patterns before generator work begins. Prefer a manifest/checksum report that verifies complete stimulus coverage without exposing credentials. Never use live generation as a fallback for a missing experiment asset.

## Documentation discipline

Update `CLAUDE.md` when the experimental contract changes and update this file when repository-wide implementation rules change. Document schema versions and event-code changes alongside code. Keep unresolved experimental choices visible; do not quietly convert assumptions into protocol.
