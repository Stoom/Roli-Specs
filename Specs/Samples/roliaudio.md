# ROLI audio container: specification for independent implementation

Revision 1.4

## Purpose and provenance

This document describes the observed structure and decoding behavior of version 1 and version 2 `.roliaudio` files. It is intended as an implementation-neutral handoff for a developer writing an independent reader or converter.

The specification was derived from static analysis of a shipped Equator2 decoder and independent examination of audio files. It contains format facts, constants, arithmetic rules, and validation results. It contains no original source code, decompiled pseudocode, example implementation, executable addresses, personal information, or local filesystem paths.

Statements describe the examined formats and decoder. Compatibility with other application builds, future container versions, or unexamined content is not established.

For external sample mapping, instrument-container layout and region properties, see the companion [ROLI instrument specification, revision 1.0](roliinstrument.md). Instrument-container versions are separate from the audio-container versions described here. This cross-reference update retains audio document revision **1.4**.

## Findings

Two container versions were observed:

| Version | Untransformed header | Payload |
|---|---:|---|
| 1 | 36 bytes | XOR-transformed interleaved 16-bit PCM |
| 2 | 16 bytes | XOR-transformed FLAC stream |

Both use the same fixed table of eight 32-bit constants and the same fixed multiplier. The effective XOR mask varies deterministically with position. No per-file secret, random initialization value, account identifier, or machine identifier is an input to the observed audio transform.

The examined decoder describes version 2 as “ROLI encrypted FLAC file.” In this context, the payload is an ordinary FLAC stream concealed by a reversible XOR transform. “Fixed obfuscation” describes the observed mechanism more precisely than encryption using a private secret.

Audio decoding and application authorization are separate matters. These findings do not establish that an application will activate or play content on another system.

## Conventions

- Offsets are measured in bytes from the beginning of the original `.roliaudio` file, unless explicitly described as payload-relative.
- Header integers and stored PCM words are little-endian.
- A frame is one sample from each channel at the same time position. A stereo frame contains two 16-bit words.
- XOR means bitwise exclusive OR.
- All mask multiplication uses unsigned 32-bit arithmetic: discard any bits above bit 31.
- Hexadecimal values use the `0x` prefix. Byte sequences list bytes in storage order.
- Loop fields are metadata and do not participate in mask generation.

## Fixed constants and mask derivation

The multiplier is **`0x727ac02d`**.

The fixed table is indexed from zero:

| Index | 32-bit constant | Little-endian bytes | Selected for position index modulo 8 |
|---:|---|---|---:|
| 0 | `0x4b6146d4` | `d4 46 61 4b` | 0 |
| 1 | `0x9261f82e` | `2e f8 61 92` | 5 |
| 2 | `0x36d44e00` | `00 4e d4 36` | 2 |
| 3 | `0xb08618ea` | `ea 18 86 b0` | 7 |
| 4 | `0x95e7150c` | `0c 15 e7 95` | 4 |
| 5 | `0x6ba02406` | `06 24 a0 6b` | 1 |
| 6 | `0x6d817ef8` | `f8 7e 81 6d` | 6 |
| 7 | `0x51868082` | `82 80 86 51` | 3 |

To obtain a 32-bit mask for a position index:

1. Multiply the position index by the multiplier, retaining only the lowest 32 bits. Call this value the product.
2. Use the lowest three bits of the product as the table index, giving an index from zero through seven.
3. XOR the product with the selected table constant. The result is the 32-bit mask.

The position index has a different meaning in each version: an absolute four-byte word index in version 2, or an audio frame index in version 1. The worked examples in the corresponding version sections show how each format selects and applies the resulting mask.

The table-selection sequence is `0, 5, 2, 7, 4, 1, 6, 3`, repeating every eight position indices. The complete masks do **not** repeat every eight positions, because the product continues to change.

No key needs to be extracted from an individual audio file. The constants above and the relevant position determine the mask completely.

## Version 2 layout and decoding

### Header

| Offset | Length | Meaning |
|---|---:|---|
| `0x00` | 4 | ASCII `ROLI`; bytes `52 4f 4c 49` |
| `0x04` | 4 | Unsigned version value, equal to 2 |
| `0x08` | 4 | Loop start value |
| `0x0c` | 4 | Loop end value |
| `0x10` | Remaining | Transformed FLAC stream |

The wrapper is untransformed. The examined reader passes the loop values into metadata named `Loop0Start` and `Loop0End`. See the loop-metadata section for the confirmed normalization and region-resolution rules, and the remaining rendering uncertainties.

### Payload decoding

For each payload byte:

1. Take its absolute position in the original file. The first payload byte is at position 16.
2. Divide that position by four, rounding down. This is the position index for mask generation.
3. Generate the 32-bit mask using the fixed constants and procedure above.
4. Select one byte from the mask according to the original position modulo four: remainder zero selects the least significant byte, remainder one selects bits 8–15, remainder two selects bits 16–23, and remainder three selects bits 24–31.
5. XOR the selected mask byte with the stored byte. This yields the decoded FLAC byte.

The decoded payload begins with the standard `fLaC` marker. A standalone FLAC consists of the decoded payload without the 16-byte ROLI wrapper. Preserve the wrapper's loop metadata separately if it is needed; copying it into the FLAC byte stream would produce an invalid stream.

The transform is symmetric: applying the same mask again restores the stored bytes.

### Fictional worked example: recovering a FLAC header

Suppose a hypothetical version 2 file has the standard 16-byte ROLI wrapper, followed by the stored bytes `de 59 6d 1f`. We want to recover the first four bytes of its FLAC payload. This is an illustrative scenario, not a report about a particular recording. The constants and expected FLAC marker are the observed format facts, so these first encoded bytes are determined by the transform rather than chosen arbitrarily.

1. **Determine the absolute file position.** The first payload byte is at offset 16 (`0x10`), immediately after the untransformed ROLI wrapper. Use its original file position, not payload-relative position zero.
2. **Determine the word index.** Divide 16 by four, rounding down. The position index is 4. All four bytes at offsets 16 through 19 belong to this same word and share one 32-bit mask.
3. **Multiply by the fixed multiplier.** Four multiplied by `0x727ac02d` gives the full integer product `0x1c9eb00b4`.
4. **Apply unsigned 32-bit wraparound.** Retaining the lowest eight hexadecimal digits gives `0xc9eb00b4`. The leading hexadecimal digit 1 is discarded.
5. **Select the table entry.** The lowest three bits of the retained product are binary `100`, so the table index is 4. Table entry 4 is `0x95e7150c`.
6. **Derive the full mask.** XOR `0xc9eb00b4` with `0x95e7150c`. The resulting 32-bit mask is `0x5c0c15b8`.
7. **Select mask bytes in little-endian order.** For offsets 16, 17, 18, and 19, use the mask bytes `b8`, `15`, `0c`, and `5c`, respectively. The position modulo four selects the byte, as shown below.
8. **Decode the stored bytes.** XOR each stored byte with its selected mask byte. The recovered bytes are `66 4c 61 43`, the ASCII marker `fLaC`.

| Absolute file offset | Position modulo 4 | Stored byte | Selected mask byte | Recovered byte | ASCII |
|---:|---:|---|---|---|---|
| 16 (`0x10`) | 0 | `de` | `b8` | `66` | f |
| 17 (`0x11`) | 1 | `59` | `15` | `4c` | L |
| 18 (`0x12`) | 2 | `6d` | `0c` | `61` | a |
| 19 (`0x13`) | 3 | `1f` | `5c` | `43` | C |

Continue with absolute offset 20 (`0x14`). This begins word index 5, so derive a new mask rather than repeating the previous four mask bytes. Its product is `0x3c65c0e1`, table index is 1, and mask is `0xae0438cf`, giving little-endian mask bytes `cf 38 04 ae`.

For a fictional continuation containing the first FLAC metadata-block header, suppose the stored bytes at offsets 20 through 23 are `cf 38 04 8c`. Applying those four mask bytes recovers `00 00 00 22`. In FLAC, this identifies a non-final STREAMINFO block with a 34-byte body. Together, the recovered opening eight bytes are `66 4c 61 43 00 00 00 22`.

These bytes establish only the marker and first metadata-block header; they do not demonstrate a complete valid FLAC stream. A complete file still needs valid metadata bodies and audio frames. When writing recovered FLAC, omit the ROLI wrapper and retain its loop values separately. The filename, sample rate, and loop values do not determine the XOR mask.

### Streaming and seeking

Maintain the original absolute byte position across reads. Seeking to a new payload position requires calculating the mask from that position; it does not require decoding earlier payload bytes.

Do not reset the position to zero at the beginning of the payload or at each read buffer. Partial four-byte words and unaligned read boundaries use the corresponding bytes of the same position-derived mask. No padding is required for a final partial word.

The observed decoder supplies a 32-bit position to the transform. This specification's verified compatibility scope is files smaller than 4 GiB. Behavior for larger files, especially reads spanning that boundary, remains unvalidated.

## Version 1 layout and decoding

### Header

| Offset | Length | Meaning |
|---|---:|---|
| `0x00` | 4 | ASCII `ROLI`; bytes `52 4f 4c 49` |
| `0x04` | 4 | Unsigned version value, equal to 1 |
| `0x08` | 4 | Channel count: 1 or 2 in the examined reader |
| `0x0c` | 4 | Bit depth: 16 in the examined reader |
| `0x10` | 4 | Sample rate in Hz |
| `0x14` | **8** | Frame count, read as a little-endian 64-bit integer |
| `0x1c` | 4 | Loop start value |
| `0x20` | 4 | Loop end value |
| `0x24` | Remaining | Transformed interleaved PCM |

The bytes at `0x18` belong to the upper half of the frame count; they are not a separate loop field.

For the observed 16-bit layout, the exact payload length is the frame count multiplied by the channel count and then by two bytes. Total file length is that payload length plus 36 bytes.

Observed sample rates were 44,100, 48,000, and 96,000 Hz. The examined reader's supported-rate list also includes 8,000, 11,025, 12,000, 16,000, 22,050, 32,000, 88,200, 176,400, 192,000, 352,800, and 384,000 Hz. Content at those additional rates was not validated.

### Payload decoding

Frames are numbered from zero. For each frame:

1. Generate the 32-bit mask using the frame number as the position index.
2. Retain the upper 16 bits of that mask. This is the frame's 16-bit XOR mask.
3. Read each channel's stored word as a little-endian 16-bit value and XOR it with the frame mask.
4. Preserve the recovered 16-bit bit pattern and interpret it as a signed PCM sample.

Every channel in the same frame uses the same mask. In stereo, the stored order is channel 0 followed by channel 1 for each frame. Advance the position index once per frame, not once per channel or once per stored word.

Recovered PCM can be placed in a suitable audio container using the header's sample rate and channel count. The PCM itself does not include a WAV header.

### Fictional worked example: a stereo PCM frame

Suppose a hypothetical version 1 file contains stereo, 16-bit audio. We want to decode frame number **5**, counting from zero, whose stored channel words are `0xab04` and `0x51fc`. These sample values are invented; the multiplier and table constants are the observed format constants.

1. **Determine the frame index.** The index is 5 for both channels. With a 36-byte header and four bytes per stereo frame, the frame begins at absolute byte offset 56 (`0x38`). Version 1 uses the frame number, not that byte offset, to generate its mask.
2. **Multiply by the fixed multiplier.** Five multiplied by `0x727ac02d` gives the full integer product `0x23c65c0e1`.
3. **Apply unsigned 32-bit wraparound.** Retain the lowest eight hexadecimal digits, giving `0x3c65c0e1`.
4. **Select the table entry.** The lowest three bits of that product are binary `001`, so select table index 1, whose constant is `0x9261f82e`.
5. **Derive the full mask.** XOR `0x3c65c0e1` with `0x9261f82e`, giving `0xae0438cf`.
6. **Select the PCM mask.** Retain the upper 16 bits, giving `0xae04`. The lower 16 bits are not used for these PCM words.
7. **Decode both channel words.** XOR each stored word with the same `0xae04` mask. Do not advance the index between channels.
8. **Interpret the recovered samples.** Preserve the recovered bit patterns as little-endian signed 16-bit PCM. Advance to frame index 6 only when processing the next frame, then derive its new mask.

| Channel | Invented stored word | Frame mask | Recovered PCM word | Signed sample value | Recovered little-endian bytes |
|---:|---|---|---|---:|---|
| 0 | `0xab04` | `0xae04` | `0x0500` | 1,280 | `00 05` |
| 1 | `0x51fc` | `0xae04` | `0xfff8` | -8 | `f8 ff` |

The recovered interleaved bytes for this fictional frame are `00 05 f8 ff`. The filename, sample rate, and loop values do not affect the mask. This example illustrates sample recovery, not a complete PCM file or WAV container.

### Streaming and seeking

The frame number determines the mask independently of previous frames. Seeking can therefore begin directly at the desired frame. The original byte position of a channel word is 36 bytes plus twice the sum of the frame number multiplied by the channel count and the channel index.

When processing partial reads, retain both the original frame number and channel position. Splitting a stereo frame across buffers must not change the mask used for its second channel.

## Loop metadata and region resolution

The companion [instrument specification](roliinstrument.md#loop-mode-and-bounds-resolution) documents the instrument-side mode and bounds contract; its [region property table](roliinstrument.md#region-properties) covers other mapping settings. The rules below are retained here to explain how audio-wrapper markers are consumed.

### Audio markers and instrument settings are separate

Both audio versions store one pair of raw loop values. The examined readers expose these as `Loop0Start` and `Loop0End`. The values refer to decoded audio frames: one frame contains one sample per channel. They are not byte offsets into compressed FLAC or into interleaved PCM. At 48,000 Hz, frame 48,000 is one second into either mono or stereo audio.

The audio wrapper does not contain a loop-mode field. Instrument regions can separately specify `loop_mode`, `loop_start`, and `loop_end`, as documented in the [instrument specification](roliinstrument.md#loop-mode-and-bounds-resolution). Preserve these alongside the raw wrapper markers; recovering an ordinary FLAC stream alone does not retain the instrument's playback policy.

### Mode values

The native region-resolution path distinguishes the following values. String conversion alone is insufficient to distinguish automatic mode from explicit no-loop mode.

| Numeric value | Meaning established by the inspected paths | Bounds behavior during region resolution |
|---:|---|---|
| 0 | Automatic selection from embedded metadata | A valid embedded pair is adopted and mode becomes 2; it does not force looping when that pair is invalid. |
| 1 | Explicit no-loop mode | Embedded-loop fallback is skipped. |
| 2 | `loop_continuous` | Valid explicit bounds are retained; otherwise embedded bounds are tried, then the full audio range. |
| 3 | `loop_sustain` | The same bounds-resolution rules as mode 2. |

The inspected numeric-to-string converter renders both 0 and 1 as `no_loop`, while 2 and 3 render as the names above. The inspected SFZ string parser maps `loop_continuous` to 2 and `loop_sustain` to 3; its other input strings fall back to 1. Consequently, converting mode 0 to the literal string `no_loop` can lose its automatic-selection meaning. This is a property of those conversion paths, not a guarantee for every serializer.

The [instrument specification’s unverified features](roliinstrument.md#unverified-features-and-boundaries) distinguish region settings from software playback behavior. The names establish the intended continuous-versus-sustain distinction. The actual note-off transition, sustain-pedal interaction, loop wrap comparison, interpolation and crossfade behavior have not been traced through the rendering path or tested during playback. Do not infer their exact implementation from the names alone.

### Embedded metadata normalization

For the inspected WAV/ROLI metadata path and a nonempty audio stream containing N frames, a supplied embedded end is capped at N minus 1. A start below zero is normalized by this helper toward zero; reversed or equal bounds are collapsed rather than turned into a positive-length loop. The helper returns a nondecreasing pair. For the ordinary ROLI pair 0/0 it returns 0/0.

The region resolver regards an embedded pair as usable only when its start is nonnegative and its end is strictly greater than its start. Thus 0/0 fails embedded-loop fallback. It is not a global command to disable looping: an instrument can supply its own positive-length loop over audio with a 0/0 wrapper.

This metadata helper and the subsequent region resolver are distinct from the audio renderer. These observations describe initialization, not the precise frame sequence emitted when a loop wraps. Empty streams, oversized integer values and malformed bounds are outside the validated case.

### Region bounds selection

For the ordinary modes 0 through 3, the inspected resolver makes these decisions in this order:

1. Keep explicit bounds when the mode is 2 or 3, the start is nonnegative, and the end is greater than the start.
2. Otherwise, unless the mode is 1, try the normalized embedded pair. If usable, copy it into the region. If the original mode was 0, change it to 2.
3. If the embedded pair is unusable and the requested mode is 2 or 3, use start 0 and end N minus 1 as fallback bounds. This does not change a requested mode 3 into mode 2.
4. Cap the selected region end at N minus 1. This is a cap, not a general subtraction of one from every mapping end.

The native path also records the resolved pair in its sample state and contains diagnostics for invalid bounds. It has not been established that every malformed input is rejected or repaired consistently. A new implementation should validate its own arithmetic and retain the original values for inspection.

### Endpoint differences in real content

A bounded comparison covered 21 instrument mappings and 751 distinct referenced audio files: 651 version 2 and 100 version 1. Of the 751 pairs, 496 audio headers stored 0/0. Fifty-two of those had mode 2 with explicit nonzero mapping ends, confirming that wrapper markers alone cannot determine an instrument's loop.

Among 285 regions with explicit bounds, 69 mapping ends matched the raw audio-header end and 216 differed. In 152 version 2 cases the mapping end equaled N while the wrapper end equaled N minus 1. Twelve version 1 mappings had ends one lower than their wrapper ends. The remaining 52 mismatches supplied loops over zero-header audio. Other mappings also retained N minus 1 directly.

These differences do not establish a universal exclusive-end convention for mapping files. The native end cap explains how N and N minus 1 can reach the same initialized endpoint. It does not explain every authoring difference, nor prove whether the renderer emits its stored endpoint before wrapping. Preserve raw wrapper and mapping ends separately, then apply the confirmed cap only when reproducing this resolver.

### Fictional resolution examples

Consider a fictional stereo file with N = 96,000 frames at 48,000 Hz. Its duration is two seconds.

| Raw wrapper pair | Region mode and explicit pair | Result in the inspected resolver |
|---|---|---|
| 24,000 / 95,999 | Mode 0; no explicit pair | Adopt 24,000 / 95,999 and change to mode 2. |
| 24,000 / 95,999 | Mode 1; no explicit pair | Skip embedded fallback; keep no-loop mode. |
| 0 / 0 | Mode 2; 12,000 / 60,000 | Retain 12,000 / 60,000; the zero wrapper does not disable this loop. |
| 24,000 / 95,999 | Mode 2; 24,000 / 96,000 | Retain the explicit start and cap the end to 95,999. |
| 0 / 0 | Mode 3; missing/invalid explicit pair | Fall back to 0 / 95,999 and keep mode 3. |
| 0 / 0 | Mode 0; no explicit pair | Do not select an embedded loop or promote mode to 2. |

These examples describe bounds selection only. A converter targeting a format with a documented exclusive end should perform that target-specific conversion explicitly; it should not apply an assumed end-plus-one rule to every source marker.

## Arithmetic check values

The following values allow an independent implementation to verify constant ordering, overflow arithmetic, and mask selection without receiving implementation code.

| Position index | Table index | Product, truncated to 32 bits | 32-bit mask | Upper 16-bit mask |
|---:|---:|---|---|---|
| 0 | 0 | `0x00000000` | `0x4b6146d4` | `0x4b61` |
| 1 | 5 | `0x727ac02d` | `0x19dae42b` | `0x19da` |
| 2 | 2 | `0xe4f5805a` | `0xd221ce5a` | `0xd221` |
| 3 | 7 | `0x57704087` | `0x06f6c005` | `0x06f6` |
| 4 | 4 | `0xc9eb00b4` | `0x5c0c15b8` | `0x5c0c` |
| 5 | 1 | `0x3c65c0e1` | `0xae0438cf` | `0xae04` |
| 6 | 6 | `0xaee0810e` | `0xc361fff6` | `0xc361` |
| 7 | 3 | `0x215b413b` | `0x91dd59d1` | `0x91dd` |
| 8 | 0 | `0x93d60168` | `0xd8b747bc` | `0xd8b7` |

For version 2, the first payload word uses position index 4. Its mask bytes are `b8 15 0c 5c`, in little-endian order. Stored bytes `de 59 6d 1f` decode to `66 4c 61 43`, the ASCII marker `fLaC`.

For version 1, a stored word `0x4b61` in frame zero decodes to a zero-valued PCM sample. This is an arithmetic check value, not a claim about the beginning of every source file.

## Validation evidence and confidence

### Completed checks

- A header census covered 54,127 files: 52,789 version 2 and 1,338 version 1. All had the expected magic and one of those two version values.
- All 1,338 version 1 files satisfied the 36-byte header and expected payload-length relation. They were mono or stereo and 16-bit.
- Twenty-four files were selected for full-byte examination, using the smallest and largest file in each of twelve library groups. This is an extreme-size sample, not a random sample.
- All 24 installed samples matched their downloaded package counterparts by SHA-256. Multiple shared copies produced 97 matching comparisons. This supports absence of installation-time personalization for those samples, not a universal claim about all downloads or accounts.
- Applying the version 2 transform to bounded prefixes of all 21 version 2 samples recovered a FLAC marker and correctly shaped STREAMINFO metadata.
- One complete small version 2 file recovered a 2,515-byte FLAC stream. Its two metadata blocks were parsed, all three frame headers passed CRC-8 checks, and all three compressed frames passed CRC-16 checks. STREAMINFO reported stereo, 16-bit, 44,100 Hz, and 3,022 frames.
- Bounded prefixes of three version 1 files were transformed using the frame-index rule. Their resulting sample statistics were consistent with PCM and substantially smoother than the encoded values, corroborating the observed reader behavior.

The transform, constants, and version mapping are supported by static reader analysis and independent byte probes. Version 2 also has compressed-frame checksum corroboration. Version 1 has no independent reference recording or payload checksum comparison in this investigation.

### Remaining gaps

- Decoded FLAC PCM and the STREAMINFO PCM MD5 were not checked with an independent audio decoder.
- No listening test or full-library conversion was performed.
- Bounds normalization, mode selection and fallback are now described above. Exact rendering at loop boundaries, note release, pedal behavior, crossfades and roundtrip conversion into other containers remain unverified.
- Malformed headers, truncated inputs, unsupported versions, very large files, and all read-boundary combinations were not exhaustively tested.
- Application activation, content entitlements, and playback on another system were not tested.
- No claim is made about other ROLI container versions or other decoder builds.

## Independent implementation handoff

A reader can be developed from this specification using newly written parsing and transform logic, together with an independently chosen standard FLAC decoder or PCM output writer. Reconstructing instrument mappings additionally requires the [companion instrument specification](roliinstrument.md); decoding audio alone does not recreate region selection or playback policy. Original executable code, decompiler output, and investigation scripts are not part of this handoff.

Suggested acceptance checks are correct header parsing, the arithmetic check values above, consistent results across aligned and unaligned reads, stereo frame handling, safe payload-length checks, and validation of recovered FLAC with a standard decoder. Check the loop-resolution examples above, retain both wrapper and instrument markers, and preserve unverified rendering behavior as an explicit compatibility limit.

## Revision history

- **1.4, companion-document update:** Added references to instrument specification revision 1.0 without changing the audio layouts, XOR transform or loop-resolution contract. The original 1.4 text remains archived.
- **1.4:** Added frame-based loop metadata, automatic/no-loop/continuous/sustain mode distinctions, native bounds selection and end capping, a 751-file mapping comparison, fictional resolution examples and explicit rendering limits. The audio layouts and XOR constants are unchanged.
- **1.3:** Retained as the exact pre-loop-analysis specification. It includes separate fictional decoding examples for versions 1 and 2.

Document revision numbers are separate from the audio-container version values 1 and 2. Earlier document revisions 1.0 through 1.2 were not separately retained in the available files and have not been reconstructed.
