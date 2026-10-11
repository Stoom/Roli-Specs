# ROLI instrument container: specification for independent implementation

Revision 1.0

## Purpose and provenance

This document specifies the `.roliinstrument` container, region records and their relationship to external `.roliaudio` samples. It is based on static analysis of shipped Equator2 reader/writer paths and independent byte examination. It contains no implementation code, decompiler output, executable addresses, personal information or local filesystem paths.

Format rules below are established by those native paths. Corpus statistics describe the examined files, rather than universal limits. No ROLI application was run for this investigation, and acceptance of newly authored files has not been tested. These findings do not assert a formally separated clean-room development process.

For audio payload decoding and embedded loop metadata, see the [ROLI audio specification](roliaudio.md).

## Findings

- The outer container supports versions 1 and 2. The native writer emits version 2.
- Regions continue to end of file, each beginning with its own encoding selector. The reader supports selectors 1–4; the writer emits selector 4.
- Selector 4 stores a JUCE ValueTree named `Region`, with typed properties. Selectors 1–3 use fixed legacy layouts.
- Samples are external references. Their audio-container versions are independent of instrument-container versions and region selectors.
- Instrument bytes do not use the `.roliaudio` XOR transform. Decoding the format does not establish application authorization.

## Conventions

- Byte offsets, variant tags, masks and byte sequences use hexadecimal with the 0x prefix. Selector values, byte sizes, counts, musical quantities and audio-frame positions use decimal. Offset formulas and the header-extension formula retain hexadecimal constants. Standalone hex values are plain text; formulas use Markdown inline code.
- Unprefixed numbers are decimal. Conventional type and standard names retain their usual spelling, such as int32, float32, UTF-8 and UUID version 4.
- Fixed-width integers are little-endian. Region integers and the version-2 array count are signed int32.
- N denotes the header array element count; F denotes the decoded audio-frame count. References to these symbols are plain text.
- Legacy floats are little-endian IEEE 754 float32; typed floating values use IEEE 754 doubles.
- Names and strings are UTF-8 and null terminated in the writer paths. Invalid character handling remains untested.
- Missing, explicitly zero and empty values are distinct. Preserve original property order, encoded bodies and floating precision for lossless reconstruction.
- Loop positions are decoded audio frames, not container byte offsets.

## Outer container layout

The file has a shared header, a version-2 extension when applicable, and a stream of region records. Header offsets below are absolute file offsets. Each structure table states its own offset origin; selector-specific tables start at the beginning of the selected body.

### Shared header

| Offset | Length (bytes) | Field |
|---|---:|---|
| 0x00 | 4 | ASCII `ROLI`, bytes 0x52 0x4f 0x4c 0x49 |
| 0x04 | 4 | Instrument-container version: 1 or 2 |
| 0x08 | Variable | Null terminated hexadecimal identifier |

The reader decodes the identifier into 16 bytes, taking the first 16 decoded bytes and zero-padding shorter values. The writer formats 16 bytes as hexadecimal text. Preserve original text if noncanonical inputs must roundtrip. The traced new-instrument creation path generates a pseudorandom 16-byte identifier with UUID version-4 and variant bits, serialized as 32 hexadecimal characters without separators. This path does not derive the identifier from file content. Collision handling and identity preservation across other workflows remain unresolved; 9 identifiers in the corpus occur with different complete-file digests.

Let E be the offset immediately after the identifier terminator. With the corpus's 32-character identifier plus its 0x00 terminator, E is 0x29. Always parse the terminator rather than hardcoding its length.

### Version 1

Regions immediately follow the identifier at E, which is 0x29 with that identifier length. Header scalars default to zero and the header array to empty.

### Version 2

The identifier is followed by:

| Offset from E | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | 4 | int32 | Header scalar A |
| 0x04 | 4 | int32 | Array element count N |
| `0x08 + 0x04 × i` | 4 | int32 | Header array element i; repeats N times |
| `0x08 + 0x04 × N` | 4 | int32 | Header scalar B |

Array element i starts at `E + 0x08 + 0x04 × i`, for `0x00 ≤ i < N`; each element occupies 4 bytes. For nonnegative N, the extension occupies `0x0C + 0x04 × N` bytes, and the first selector is at `E + 0x0C + 0x04 × N`. The reader loops over any positive count. With E equal to 0x29, the first selector is at offset 0x35 for `N = 0x00` and 0x39 for `N = 0x01`.

The traced new-instrument constructor initializes scalar A to 2 and scalar B to 1, with the array supplied by its caller; these are creation-path values, not universal file defaults. Both scalars and every array element must be retained. Their musical meanings remain unresolved. The count is neither a Boolean flag nor a region count. Negative or impossible counts should be rejected by a strict independent reader.

## Region encodings

Each region has the following structure. Offsets in this table are measured from the start of the complete region record.

| Offset | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | 4 | int32 | Encoding selector; supported values 1–4 |
| 0x04 | Variable | Selected encoding | Region body; layout defined below |

The selector chooses the body's layout. Every body begins at region offset 0x04 because the selector occupies 4 bytes; the body itself is variable length. The selector-specific tables below restart offsets at 0x00 for the beginning of that body, excluding the selector. There is no outer region count or per-region byte-length field. Parse the selected body completely to find the next region's start.

For example, a version-2 header with the usual identifier and `N = 0x01` puts the first region at file offset 0x39. Its selector occupies file offsets 0x39–0x3C and its body begins at 0x3D. Body offset 0x00 in a selector-specific table therefore corresponds to file offset 0x3D in this example.

### Selector 1: sample and shared tail

| Offset | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | Variable | Null terminated UTF-8 | `sample` |
| After `sample` terminator | 32 | Legacy-tail record | [Legacy tail record](#legacy-tail-record) |

### Selector 2: velocity bounds, sample and shared tail

| Offset | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | 4 | int32 | `lovel` |
| 0x04 | 4 | int32 | `hivel` |
| 0x08 | Variable | Null terminated UTF-8 | `sample` |
| After `sample` terminator | 32 | Legacy-tail record | [Legacy tail record](#legacy-tail-record) |

### Selector 3: tuning, velocity bounds, sample and shared tail

| Offset | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | 4 | int32 | `transpose` |
| 0x04 | 4 | int32 | `tune` |
| 0x08 | 4 | int32 | `lovel` |
| 0x0C | 4 | int32 | `hivel` |
| 0x10 | Variable | Null terminated UTF-8 | `sample` |
| After `sample` terminator | 32 | Legacy-tail record | [Legacy tail record](#legacy-tail-record) |

### Legacy tail record

| Offset | Length (bytes) | Storage | Field |
|---|---|---|---|
| 0x00 | 4 | int32 | `lokey` |
| 0x04 | 4 | int32 | `hikey` |
| 0x08 | 4 | int32 | `pitch_keycenter` |
| 0x0C | 4 | int32 | `loop_mode` |
| 0x10 | 4 | int32 | `loop_start` |
| 0x14 | 4 | int32 | `loop_end` |
| 0x18 | 4 | float32 | `lorand` |
| 0x1C | 4 | float32 | `hirand` |

The next region's selector follows immediately after this record, with no padding. Fields omitted by an earlier selector retain initializer state before load preprocessing.

### Selector 4: ValueTree property map

Offsets start at 0x00 for the tree body. Later fields follow sequentially; their offsets depend on the encoded lengths of preceding fields.

| Offset | Length (bytes) | Storage | Item |
|---|---|---|---|
| 0x00 | Variable | Null terminated UTF-8 | Node name |
| After node name | 1–5 | Compressed integer | Property count P |
| After property count | Variable | P serialized key/value entries | Property map |
| After property map | 1–5 | Compressed integer | Child count K |
| After child count | Variable | K recursively serialized trees | Child array |

Each property entry contains a null terminated UTF-8 key followed immediately by a serialized variant. The properties form a keyed map, not a fixed-offset structure. Their serialized order must still be retained for byte-exact reconstruction. Child trees form an ordered array.

The region writer uses the name `Region`. The reader extracts root properties without checking that name; child trees are consumed but do not become additional instrument regions. An empty name produces a null tree and missing-property conversions. Higher-level acceptance of these cases remains untested.

### Compressed integers

Compressed integers use a sign-and-magnitude encoding, not two's complement or a continuation-bit encoding. Offsets below are relative to the beginning of the compressed integer.

| Offset | Length (bytes) | Item |
|---|---|---|
| 0x00 | 1 | Header byte H: sign flag and magnitude width |
| 0x01 | W bytes | Little-endian magnitude M |

The header contains these independent bit fields:

| Mask | Meaning |
|---|---|
| 0x7F | Magnitude width W: `H & 0x7F` |
| 0x80 | Negative flag: set means negate M |

Valid widths are 0–4 bytes. The complete encoded size is `1 + W` bytes; the maximum valid size is 5 bytes. Width 0 has no magnitude bytes and yields 0, including when the sign flag is set. For a positive width, byte i contributes `byte[i] × 0x100^i` to M, starting with `i = 0` at offset 0x01. Apply the sign only after assembling the magnitude.

| Encoded bytes | Width W (bytes) | Magnitude M (hex) | Decoded value (decimal) |
|---|---|---|---|
| 0x00 | 0 | 0x00 | 0 |
| 0x80 | 0 | 0x00 | 0 |
| 0x01 0x05 | 1 | 0x05 | 5 |
| 0x02 0x00 0x01 | 2 | 0x0100 | 256 |
| 0x03 0x56 0x34 0x12 | 3 | 0x123456 | 1,193,046 |
| 0x04 0x78 0x56 0x34 0x12 | 4 | 0x12345678 | 305,419,896 |
| 0x81 0x05 | 1 | 0x05 | −5 |
| 0x82 0x00 0x01 | 2 | 0x0100 | −256 |

Magnitudes above are shown in hex to illustrate byte order. For example, 0x82 selects a 2-byte width through mask 0x7F and sets the negative flag through mask 0x80. The next bytes 0x00 0x01 form magnitude 0x0100, or 256; the result is −256. The flag describes the sign of the whole magnitude, not the most significant payload byte.

Widths above 4 and incomplete magnitude reads return zero in the native helper. That result does not distinguish malformed input from encoded zero. A strict reader should verify header availability, reject excessive widths, require all W bytes, and reject negative counts or lengths before allocating or iterating. Overflow and minimum-int corner cases remain untested; a 4-byte magnitude alone does not establish that every possible magnitude is valid for a signed int32 result.

### Serialized variants

Each variant starts with a compressed body length. A positive body contains a tag and payload; length includes the tag and excludes the compressed length itself. Native readers and writers establish these layouts:

| Tag | Kind | Body length (bytes) | Payload after tag |
|---:|---|---|---|
| None | Void/default | 0 | No tag or payload |
| 0x01 | int32 | 5 | 4 little-endian bytes |
| 0x02 | Boolean true | 1 | None |
| 0x03 | Boolean false | 1 | None |
| 0x04 | Double | 9 | 8 little-endian IEEE 754 bytes |
| 0x05 | String | UTF-8 byte count + 2 | UTF-8 bytes and final 0x00 |
| 0x06 | int64 | 9 | 8 little-endian bytes |
| 0x07 | Array | 1 + encoded count size + total encoded element sizes | Compressed count, then complete serialized variants |
| 0x08 | Binary | Raw byte count + 1 | Raw bytes without a terminator |

The tag is at body-relative offset 0x00, and payload begins at 0x01. An empty string has body length 2; an empty binary block has length 0x01; an empty array has length 0x02 because it retains its zero element count. Arrays may contain mixed types and nested arrays. Their body includes every element's own length encoding, tag and payload, with no padding.

The reader skips an unknown tag's remaining body and returns a default variant. Nonpositive body lengths return a default without reading a tag. Preserve raw bodies to retain unknown values. Known scalar and array reads are not comprehensively confined by their declared lengths; strict readers should validate scalar sizes and bound recursive reads independently.

## Region properties

For selector 4, these fields are entries in a keyed property map, not members of a fixed-offset structure. Keys identify fields; serialized positions vary. No particular in-memory hash-table implementation is implied. The following keys are recognized by the native mapping paths. Type is the typed-tree representation; initializer values are internal fallbacks, not universal missing-property rules. Floating-point initializers are decimal.

| Property | Type | Initializer | Role |
|---|---|---|---|
| `sample` | String | Absent/empty | External audio reference |
| `lokey` | int32 | 0 | Lower key-map bound |
| `hikey` | int32 | 127 | Upper key-map bound |
| `pitch_keycenter` | int32 | 64 | Pitch-reference key |
| `lovel` | int32 | 0 | Lower velocity-map bound |
| `hivel` | int32 | 127 | Upper velocity-map bound |
| `transpose` | int32 | 0 | Transposition |
| `tune` | int32 | 0 | Fine tuning |
| `pan` | int32 | 0 | Percent-scaled pan setting in native import |
| `volume` | Double | 0.0 | Decibel-scaled volume setting in native import |
| `offset` | int32 | 0 | Sample start boundary, separate from loop bounds |
| `end` | int32 | 0 | Sample end boundary, separate from loop bounds |
| `loop_mode` | int32 | 0x00 | Loop policy; see below |
| `loop_start` | int32 | 0 | Explicit loop start in frames |
| `loop_end` | int32 | 0 | Explicit loop end in frames |
| `loop_crossfade_length` | int32 | 1 | Stored crossfade length |
| `loop_crossfade_mode` | int32 | 0x00 | Stored crossfade mode |
| `lorand` | Double | 0.0 | Lower random-range setting; legacy storage uses float32 |
| `hirand` | Double | 1.0 | Upper random-range setting; legacy storage uses float32 |
| `seq_length` | int32 | 1 | Sequence length |
| `seq_position` | int32 | 1 | One-based stored sequence position |
| `layer_name` | String | Empty | Layer-associated name |
| `rr_group` | int32 | Not established here | Layer-associated round-robin group |
| `rr_position` | int32 | Not established here | Layer-associated round-robin position |
| `rr_length` | int32 | Not established here | Layer-associated round-robin length |

### Presence and load processing

The reader directly fetches `sample`, `lokey`, `hikey`, `pitch_keycenter` and `loop_mode`. Missing values follow variant conversion, which can override initializer fallbacks. Other fields generally use presence-aware helpers. Crossfade mode is also fetched directly and marked present even when absent; crossfade length remains presence-aware. Typed floating values are converted to float internally, so original doubles must be retained separately for byte fidelity.

The writer always emits the five core properties. Optional output generally follows presence flags; crossfade-length presence gates output of both crossfade fields. Raw properties and normalized native state can therefore differ.

Before appending a region, load processing:

1. Changes mode 0x00 to mode 0x01 when either loop point is explicitly present.
2. Clears presence flags for negative effective loop points.
3. Registers layer-associated metadata and processes sequence fields.

The mode change precedes negative-point clearing. Even a supplied negative point can trigger it.

### Native region import

The traced importer resolves sample metadata, builds region descriptors and applies them to the application model. It establishes these conversions, without establishing the renderer's DSP behavior:

| Stored field | Import conversion |
|---|---|
| `pan` | Multiply by decimal 0.01 and clamp to decimal −1.0…1.0 |
| `transpose` | Split the signed integer into quotient and remainder using division by 12; the complete pitch formula remains unresolved |
| `tune` | Copy unchanged; complete pitch conversion remains unresolved |
| `offset` | Copy unchanged |
| `end` | Replace zero with `F − 1` for F decoded frames; copy nonzero values without an additional cap in this step |
| `loop_crossfade_length` | Copy unchanged when present |
| `loop_crossfade_mode` | When crossfade length is present, map stored 0x02 to internal 0x01, stored 0x03 to internal 0x02, and other values to internal 0x00; otherwise retain internal 0x00 |

For effective volume V, import computes an intermediate ratio `10^((V − 6) / 20)`, substitutes zero when `V − 6 ≤ −150`, clamps to 0.0…1.0, then applies a nonlinear lookup interpolation. All constants in this decibel formula are explicitly base 10. This confirms a decibel scale in this path; the intermediate ratio is not the final model control or an established DSP gain. Pan law, crossfade units and renderer endpoint inclusion remain unresolved.

### Layers and sequences

Layer processing runs when explicit sequence length is nonzero or a layer name is present. Missing sequence length contributes zero; explicit position is reduced by one, while missing position contributes zero. After this branch runs, sequence presence flags are cleared.

Layer lookup takes the first match from these ordered searches: supplied name equality; a layer without sequence metadata when supplied length is zero; matching sequence length and converted position. A name match takes precedence. Otherwise, a new layer is created; absent names become `Layer ` plus the existing layer-table count plus one, formatted as decimal text. Explicitly empty names stay supplied. Creation can reuse an internal group identifier associated with sequence length.

These are loading and grouping rules. They do not establish note selection, sequence advancement or round-robin reset behavior; `rr_position` must not inherit the one-based rule of `seq_position`.

## Loop mode and bounds resolution

These rules apply after load preprocessing, so stored mode 0x00 with an explicit point has already become mode 0x01.

| Mode | Resolver behavior |
|---:|---|
| 0x00 | Automatic: try embedded markers; become mode 0x02 when a usable pair is adopted |
| 0x01 | No-loop: suppress embedded fallback |
| 0x02 | `loop_continuous`: explicit pair, embedded pair, then full audio range |
| 0x03 | `loop_sustain`: same bounds selection as mode 0x02; release behavior unresolved |

The string converter emits `no_loop` for both 0x00 and 0x01. Its SFZ parser maps `loop_continuous` to 0x02, `loop_sustain` to 0x03 and other strings to 0x01, so string-only roundtrips lose the automatic distinction.

For a nonempty sample with F decoded frames:

1. Modes 0x02 and 0x03 retain explicit bounds when start is nonnegative and end exceeds start.
2. Otherwise, except in mode 0x01, try normalized embedded markers with those same validity conditions. Adopting them changes mode 0x00 to mode 0x02.
3. If no embedded pair is usable, modes 0x02 and 0x03 use start 0 and end `F − 1`.
4. Cap the selected loop end at `F − 1`.

Audio marker normalization is described in the [audio loop section](roliaudio.md#loop-metadata-and-region-resolution). Embedded 0/0 is unusable for fallback but does not disable a valid explicit instrument loop. Preserve raw mapping and audio endpoints: both F and `F − 1` occur in content, and the cap does not establish renderer endpoint inclusion.

For example, with `F = 96,000` and embedded bounds 24,000/95,999, automatic mode adopts those markers. Continuous mode with explicit bounds 24,000/96,000 instead retains the start and caps the end to 95,999. These examples describe initialization, not wrap timing or note release.

## Validation evidence and confidence

### Completed checks

Counts, byte widths and frame lengths below are decimal; mode values are hexadecimal; selector values are decimal.

- Traced native reader/writer contracts, new-instrument identifier creation, load preprocessing, layer lookup, loop resolution and region-to-model conversions. These are static-path confirmations, not application execution tests.
- Parsed and reconstructed all 848 physical files to their original SHA-256 digests: 456 distinct file digests, 447 identifiers and 53,220 regions.
- Outer versions: 290 version-1 files and 558 version-2 files. Version-2 array counts are 0 in 15 files and 1 in 543.
- Region selectors: 53,091 selector-4 records, 114 selector-3 records and 15 selector-2 records. Selector 1 has static reader evidence only.
- All typed trees are `Region`, contain zero children and have unique keys. Property counts span 5–19 with gaps; property counts and body lengths use compressed width 1, while zero child counts use width 0.
- Typed corpus values comprise 362,783 integers, 3,879 doubles and 56,410 strings. Other variant types have native reader/writer evidence only.
- Both crossfade fields occur in 601 typed regions; lengths span 1–60,430 and modes are 0x01, 0x02 and 0x03. Round-robin fields occur together in 6 records with group 1, position 0 and length 1. These values are corpus coverage, not valid-value limits.
- All 53,220 sample references resolve relative to the instrument directory; 4 start with `./`. This establishes installed arrangement, not the full application search policy.

## Unverified features and boundaries

- Header scalar/array musical meanings; collision handling and identity preservation across workflows.
- Key/velocity endpoint inclusion, complete pitch formula, pan law and random selection.
- Renderer sample-end and loop-wrap inclusion, interpolation, release/pedal interactions and retriggering.
- Crossfade length units, enum names and blend curves; sequence/round-robin selection and reset.
- Complete path search, inheritance and articulation behavior.
- Application acceptance of newly authored or malformed files, uncommon tree/variant structures and content authorization.

## Independent implementation handoff

Validate the magic, version, terminated identifier and complete counted array. Dispatch each selector separately; parse legacy tails as six integers and two floats. Bound tree recursion, counts, lengths and allocations by available input, and require exact record-sequence consumption.

An unknown selector cannot safely be skipped: the native reader consumes only its word and returns default region state, which the outer loop preprocesses without a separate error check. Independent readers should report unsupported selectors rather than reproduce that recovery.

Preserve raw header data, property bodies, presence distinctions, doubles and loop markers separately from normalized playback state. Exact reconstruction verifies the surveyed byte layouts; it does not prove audible equivalence or application acceptance. Wider compressed values, selector 1, nonempty children and variant types absent from the corpus still need independent fixtures or controlled tests.
