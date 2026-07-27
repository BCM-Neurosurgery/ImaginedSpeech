# Repository Working Agreement

## Mission

Implement the MATLAB/Psychtoolbox imagined-speech experiment described in `CLAUDE.md`. Read `CLAUDE.md` before changing runtime behavior. Keep the task runnable by block (0–4), deterministic, data-driven, preload-first, timing-aware, and safe around participant data and lab hardware.

## Current repository state

This repository begins with task assets/reference material and no MATLAB implementation. Do not assume every asset is finalized merely because a file exists. In particular, stories and the Block 2 schedule exist, image content is not yet populated, story questions/instructions are not yet in runtime format, and VVIQ currently exists only as a reference PDF.

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
