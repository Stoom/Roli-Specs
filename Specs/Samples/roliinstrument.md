# ROLI instrument container: specification for independent implementation

Revision 1.0

## Purpose, scope and provenance

This document describes the observed `.roliinstrument` container, region records and their relationship to sample playback. It is an implementation-neutral handoff based on independent byte examination and the native analysis already documented for loop resolution. It contains no implementation code, decompiler output, executable addresses, personal information or local filesystem paths.

This is an initial, bounded specification. The physical layout below was independently parsed across 21 files containing 751 regions, consuming every byte and matching the earlier region-and-loop extraction. These files include 18 instrument-container version 1 files and three version 2 files. This does not establish every possible record type, variant type, instrument feature or software acceptance requirement.

Instrument-container versions, audio-container versions and document revision numbers are separate. An instrument version does not determine the version of its referenced audio files. For sample payload decoding, see the [ROLI audio specification](roliaudio.md).

This report supplies observations for an independent implementation; it does not assert that a formally separated clean-room development process has already taken place.

## Relationship between the files

A `.roliinstrument` file describes sample regions and their settings. In the examined files, each region contains a `sample` string naming an external `.roliaudio` file. Audio samples are not embedded in these region records.

The `.roliaudio` file supplies the audio data, frame count, channel count, sample rate and optional embedded loop markers. The instrument supplies key mapping and, where present, velocity mapping, loop mode, explicit loop bounds and additional region properties. Recovering only the audio does not reconstruct the instrument mapping.

All 751 examined sample references resolved to adjacent audio files when interpreted relative to the instrument's containing directory. This is the confirmed content arrangement, not proof of the software's complete path-search algorithm. Absolute paths, parent-directory traversal, alternate search roots, missing files and non-audio references were not tested.

## Binary conventions

- Fixed-width header integers and signed integer property values are little-endian.
- Null-terminated names and strings use a final zero byte. The examined strings decode as UTF-8; broader character support was not tested.
- Record order, property order and the distinction between missing and explicitly supplied properties should be preserved.
- Positions described as audio frames are decoded-audio positions, not byte offsets in either file.
- Unknown fields should be retained without assigning an unsupported meaning.

## Outer container

### Shared opening

| Byte offset | Length | Observed field |
|---|---:|---|
| `0x00` | 4 | ASCII `ROLI`, bytes `52 4f 4c 49` |
| `0x04` | 4 | Unsigned instrument-container version: 1 or 2 |
| `0x08` | Variable | Null-terminated identifier string |

In all examined files, the identifier consists of 32 lowercase hexadecimal characters followed by a zero byte. It therefore occupies 33 bytes and ends at offset `0x28`. Its purpose, uniqueness requirements and generation rules have not been established. Do not infer account or machine binding from its appearance.

Offsets below describe that observed identifier length. A parser should recognize the terminator rather than assuming every possible file has a 32-character identifier.

### Instrument-container version 1

The first region record prefix begins immediately after the identifier, at observed offset `0x29` (decimal 41). Its node name begins at `0x2d` (decimal 45).

### Instrument-container version 2

Version 2 adds four little-endian 32-bit words after the identifier:

| Observed offset | Field | Observed values |
|---|---|---|
| `0x29` | Extension word 0 | 1 |
| `0x2d` | Extension word 1 | 1 |
| `0x31` | Extension word 2 | 10, 14 or 16 |
| `0x35` | Extension word 3 | 2 |

Their meanings are unknown. The third word must not be treated as a region count: the three examined files contain 15, 48 and 52 regions. Retain all four words as opaque header data.

The first record prefix follows at `0x39` (decimal 57), and its node name begins at `0x3d` (decimal 61).

### Top-level record sequence

After the appropriate header, the examined files contain a sequence of records continuing to end of file. Each record consists of a four-byte prefix followed by one serialized node.

Every observed prefix is the little-endian 32-bit value 4, bytes `04 00 00 00`. Its semantic role is unresolved. It is not the byte length of the following region: regions are much longer than four bytes. Do not label it a record length, audio version or region count.

Every observed top-level node is named `Region`. No separate outer region count, final checksum or trailing bytes were needed to parse these 21 files. That observation does not exclude other record kinds or trailers in unexamined files.

## Serialized node and property layout

A node contains, in order:

1. A null-terminated node name.
2. An encoded property count.
3. That number of properties, each consisting of a null-terminated property name, an encoded value-body length, and the value body.
4. An encoded child count.
5. Any child nodes, if present.

All 751 observed `Region` nodes have child count zero. Nonempty child trees have not been validated. Observed property counts are 5, 6, 7, 14 and 16.

### Observed count and length encoding

The examined records use two forms:

| Stored bytes | Decoded nonnegative value |
|---|---:|
| `00` | 0 |
| `01 vv` | The unsigned value of byte `vv` |

For example, `01 07` represents seven properties, and `01 05` represents a five-byte value body. The prefix and its following value byte are not included in the body length.

Every property count, child count and value-body length in this corpus fits these forms. Larger-width encodings, signed counts and unusual length prefixes are outside the confirmed contract. A bounded implementation can support the observed forms and report other forms as unsupported instead of guessing.

### Confirmed value types

The first byte of a value body is its type tag. The encoded body length includes this tag and, for strings, the terminator.

| Tag | Observed body length | Value interpretation |
|---:|---:|---|
| 1 | 5 | One tag byte followed by a signed little-endian 32-bit integer |
| 4 | 9 | One tag byte followed by an eight-byte little-endian IEEE 754 double |
| 5 | Variable, at least 2 | One tag byte followed by a null-terminated string |

An empty string is a two-byte body: tag 5 followed by zero. It is distinct from an absent property. The largest observed string body is 52 bytes, including its tag and terminator.

These types account for all observed properties: 4,379 integers, 100 doubles and 851 strings. No other type tag was required. Boolean, array, binary, 64-bit integer and other possible types are not specified here.

## Region properties

The following table separates confirmed storage from semantic interpretation. Conventional field names suggest several musical meanings; exact playback units and default rules have only been traced for loop resolution.

| Property | Stored type | Occurrences among 751 regions | Meaning and confidence |
|---|---|---:|---|
| `sample` | String | 751 | External sample filename; all examined values name adjacent `.roliaudio` files. |
| `lokey` | Integer | 751 | Lower key-map bound; observed values 0–118. MIDI-note interpretation is consistent with the content; exact selection rules remain untested. |
| `hikey` | Integer | 751 | Upper key-map bound; observed values 21–127. Endpoint inclusion remains untested. |
| `pitch_keycenter` | Integer | 751 | Pitch-reference key; observed values 21–119. Exact tuning calculation remains unverified. |
| `loop_mode` | Integer | 751 | Mode selection described below; values 0, 1 and 2 appear in content, and native analysis also identifies value 3. |
| `loop_start` | Integer | 285 | Explicit loop start in decoded audio frames. Missing is distinct from zero. |
| `loop_end` | Integer | 285 | Explicit loop end in decoded audio frames. The resolver caps the selected end at frame count minus one. |
| `offset` | Integer | 145 | Sample-start-related position; observed values 0–1,081. Exact renderer treatment remains unverified. |
| `end` | Integer | 160 | Sample-end-related position, separate from `loop_end`; observed values 4,096–4,283,040. Exact boundary rules remain unverified. |
| `transpose` | Integer | 100 | Pitch-transposition-related field; all observed values are zero, so units are not independently established. |
| `tune` | Integer | 100 | Fine-tuning-related field; all observed values are zero, so units are not independently established. |
| `pan` | Integer | 100 | Panning-related field; all observed values are zero, so scaling and pan law remain unverified. |
| `lovel` | Integer | 100 | Lower velocity-map bound; all observed values are zero. Selection semantics remain unverified. |
| `hivel` | Integer | 100 | Upper velocity-map bound; all observed values are 127. Selection semantics remain unverified. |
| `volume` | Double | 100 | Gain-related field. Units, defaults and gain conversion remain unverified. |
| `layer_name` | String | 100 | Layer label; empty strings also occur. Its effect on grouping or playback remains unverified. |

Preserve unknown properties and their encoded bodies when roundtrip fidelity is desired. Do not substitute zero for every missing numeric property: the inspected native mapping structures retain whether a value was explicitly supplied.

## Loop mode and bounds resolution

### Mode meanings

| Value | Confirmed role in the inspected native resolver |
|---:|---|
| 0 | Automatic: try embedded audio loop markers; promote to mode 2 when a usable pair is adopted. |
| 1 | Explicit no-loop: suppress embedded-loop fallback. |
| 2 | `loop_continuous`: use a valid explicit pair, otherwise try embedded markers, then the full audio range. |
| 3 | `loop_sustain`: the same bounds selection as mode 2; exact release and pedal behavior remain unverified. |

The inspected string converter writes `no_loop` for both 0 and 1. Preserve the numeric distinction: a roundtrip through that string alone can lose automatic mode. The inspected SFZ string parser maps `loop_continuous` to 2, `loop_sustain` to 3, and other strings to 1. These are conversion-path observations, not a complete SFZ specification.

### Resolution contract

For a nonempty referenced sample with N decoded frames, the ordinary inspected path resolves modes 0–3 as follows:

1. Modes 2 and 3 retain explicit bounds when the start is nonnegative and the end is greater than the start.
2. Otherwise, except for mode 1, the resolver tries the normalized embedded audio markers. A usable embedded pair has nonnegative start and end greater than start. Adopting it changes mode 0 to mode 2.
3. If no usable embedded pair exists, requested modes 2 and 3 fall back to start 0 and end N minus 1. Mode 3 remains mode 3.
4. The selected region end is capped at N minus 1. This is a cap, not a subtraction applied to every source endpoint.

Audio metadata normalization, including its own end cap, is described in the [audio specification's loop section](roliaudio.md#loop-metadata-and-region-resolution). Neither document establishes the exact emitted frame sequence at a wrap boundary.

An audio header containing 0/0 is unusable for automatic embedded-loop fallback. It does not disable a valid explicit instrument loop. In the examined content, 52 regions provide continuous loops over zero-header audio.

Keep raw instrument bounds and raw audio markers separately. Among 285 explicit regions, 69 mapping ends match the raw audio end and 216 differ. Some mapping ends equal N while the audio wrapper stores N minus 1; others match it or are smaller. Do not assume a universal exclusive-end convention.

### Fictional example

Suppose a region references a fictional two-second stereo sample at 48,000 Hz, giving N = 96,000 frames. The audio wrapper stores start 24,000 and end 95,999.

- Mode 0 adopts those markers and becomes mode 2.
- Mode 1 skips embedded fallback.
- Mode 2 with explicit start 12,000 and end 60,000 retains those explicit bounds.
- Mode 2 with explicit start 24,000 and end 96,000 retains the start and caps the end to 95,999.

If the audio wrapper instead stores 0/0, valid explicit bounds still work. Mode 3 with missing or invalid explicit bounds falls back to 0/95,999. These examples specify initialization only, not note-release timing or loop interpolation.

## Unverified features and boundaries

The following are not yet sufficient for an application-compatible writer or a faithful sampler:

- The identifier's purpose and generation rules, version-2 extension meanings, and record-prefix meaning.
- Larger count encodings, additional value types, nonempty child trees, alternative node kinds and duplicate-property behavior.
- A complete inventory of instrument fields, inheritance, defaults, layering, round-robin or articulation behavior.
- Exact key/velocity-bound inclusion, tuning and gain units, `offset`/`end` rendering boundaries and path-search rules.
- Loop endpoint emission, fractional playback positions, interpolation, note release, sustain-pedal handling, retrigger behavior and crossfade algorithms.
- A `loop_crossfade_mode` name exists in the native software, but its on-disk encoding and playback algorithm are not established by these 21 files.
- Acceptance of newly authored files by ROLI software, identifier collisions, malformed-file policy, content entitlement and activation behavior.

The observed instrument records can be read without applying the `.roliaudio` XOR transform. Their names and typed property values are directly serialized. This does not establish a universal absence of protection in every instrument variant or determine application authorization.

## Independent implementation acceptance checks

A reader targeting the examined corpus should verify the outer version, terminate the identifier safely, retain version-specific header words, recognize record prefixes, parse property bodies by their declared lengths, and consume the record sequence exactly. It should preserve signed integer values, double precision, empty strings, missing fields and raw loop markers.

Verification should compare decoded records and source offsets with independent observations, resolve sample references separately from payload decoding, and check the loop-resolution examples. Unsupported structures should produce an explicit limitation instead of silently discarding data. Writer interoperability needs additional native writer analysis or controlled acceptance tests; successful parsing alone is not evidence that a newly authored instrument will load.

## Revision history

- **1.0:** Initial bounded layout and property specification for instrument-container versions 1 and 2, complete structural parsing of 21 files/751 regions, loop-resolution contract and explicit unknowns. Companion audio document remains revision 1.4.
