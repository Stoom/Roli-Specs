# Roli Specifications

This repository documents the observed structure and behavior of Roli file formats and related software, written as implementation-neutral handoffs. The goal is to describe format facts, constants, arithmetic rules, and validation results so that an independent reader, writer, or converter can be built without access to the original source code.

The specifications are derived from static analysis of shipped decoders and independent byte-level examination of sample files. They intentionally contain no original source code, decompiled pseudocode, executable addresses, personal information, or local filesystem paths.

## Table of Contents

### Samples

| Format | Description |
|---|---|
| [`.roliaudio`](Specs/Samples/roliaudio.md) | Specification for the `.roliaudio` audio container (revisions 1 and 2). Covers the header layout, the fixed XOR mask constants and derivation, and the decoding of the interleaved 16-bit PCM (v1) and FLAC (v2) payloads. |
| [`.roliinstrument`](Specs/Samples/roliinstrument.md) | Specification for the `.roliinstrument` container (versions 1 and 2). Covers the outer container, region records, key/velocity mapping, loop properties, and how instrument regions reference external `.roliaudio` files. |

## Notes

- Specifications describe the examined formats and decoders. Compatibility with other application builds, future container versions, or unexamined content is not established.
- Audio decoding and application authorization are separate matters; these documents do not establish that an application will activate or play content on another system.
- Instrument-container versions, audio-container versions, and document revision numbers are independent of one another.
