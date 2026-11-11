# Roli Specifications

This repository documents the observed structure and behavior of Roli file formats and related software, written as implementation-neutral handoffs. The goal is to describe format facts, constants, arithmetic rules, and validation results so that an independent reader, writer, or converter can be built without access to the original source code.

The specifications are derived from static analysis of shipped software and independent byte-level examination of sample files. They intentionally contain no original source code, decompiled pseudocode, personal information, or local filesystem paths. Licensing specifications include build-specific executable locations where needed to identify the examined verification paths and data.

## Table of Contents

### Samples

| Format | Description |
|---|---|
| [`.roliaudio`](Specs/Samples/roliaudio.md) | Specification for the `.roliaudio` audio container (revisions 1 and 2). Covers the header layout, the fixed XOR mask constants and derivation, and the decoding of the interleaved 16-bit PCM (v1) and FLAC (v2) payloads. |
| [`.roliinstrument`](Specs/Samples/roliinstrument.md) | Specification for the `.roliinstrument` container (versions 1 and 2). Covers the outer container, region records, key/velocity mapping, loop properties, and how instrument regions reference external `.roliaudio` files. |

### Licensing

| Component | Description |
|---|---|
| [ROLI Connect](Specs/Licensing/roli-connect-entitlements.md) | Windows Connect 1.6.4 local proxy, shared account and entitlement caches, and the evidence needed to verify offline compatibility. |
| [ROLI Dashboard](Specs/Licensing/roli-dashboard-entitlements.md) | Windows Dashboard 4.7.2 acquisition paths, signed entitlement response, account binding, and expiry checks. |
| [ROLI Airwave Player](Specs/Licensing/roli-airwave-player-entitlements.md) | Windows x64 Airwave Player 1.4.1 entitlement-consumer analysis, including acquisition, verification, and remaining validation limits. |
| [ROLI Airwave Control](Specs/Licensing/roli-airwave-control-entitlements.md) | Windows x64 Airwave Control 1.4.1 entitlement-consumer analysis and the examined boundary with its installed helpers. |
| [ROLI Hardware Driver](Specs/Licensing/roli-hardware-driver-entitlements.md) | Windows x64 Hardware Driver 0.7.1 investigation of entitlement consumption and the limits of the examined executable. |
| [ROLI Studio Player](Specs/Licensing/roli-studio-player-entitlements.md) | Windows x64 Studio Player 1.4.1 entitlement-consumer analysis, including acquisition, verification, and remaining validation limits. |
| [ROLI Studio Drums](Specs/Licensing/roli-studio-drums-entitlements.md) | Windows x64 Studio Drums 1.4.1 entitlement-consumer analysis, including acquisition, verification, and remaining validation limits. |
| [Equator2](Specs/Licensing/equator2-entitlements.md) | Windows x64 Equator2 2.5.2 entitlement-consumer analysis, including acquisition, verification, and remaining validation limits. |
| [FXpansion LicenseManager](Specs/Licensing/fxpansion-license-manager.md) | Windows x64 LicenseManager 2.1.0.14 acquisition and signed authorization format, with Cypher2 and Strobe2 2.6.1.7 local checks and separate ROLI account caches. |

### Others

| Name | Description |
|---|---|
|[ROLI Connect product downloads](Specs/Licensing/roli-connect-downloads.md) | Build lookup paths, storage keys, catalog checksums, and signed artifact delivery. |

## Contribute entitlement samples

### Run from a downloaded ZIP on Windows

1. On the GitHub repository page, select **Code** → **Download ZIP**. Extract the ZIP using **Extract All**.
2. Open PowerShell 7 or later and change to the extracted folder that contains `tools`. If you need PowerShell 7, see the [Microsoft installation instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows).
3. Keep the [entitlement report script](tools/Submit-RoliEntitlementReport.ps1) and [known entitlement baseline](tools/known-entitlements.yaml) together in `tools`, then run the script from the extracted repository folder.

```powershell
pwsh -File ./tools/Submit-RoliEntitlementReport.ps1
```

If Windows blocks the downloaded script under the `RemoteSigned` execution policy, review the script, unblock that file, and rerun the command above. See [Microsoft's Unblock-File documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/unblock-file).

```powershell
Unblock-File -LiteralPath ./tools/Submit-RoliEntitlementReport.ps1
```

### Preview and submit a report

The script prompts for your ROLI login with masked password entry. It compares each entitlement against the known variants and includes it in the preview when a tracked field is added, removed, or changed. Product record IDs and names are included when the catalog or a known product record confirms them. Account fields, serials, timestamps, tokens, raw responses, response headers, and type placeholders are excluded. Partial observations appear in a separate section with comments naming the changed fields. Review the preview before opening the prefilled GitHub issue form.

Use `-DryRun` to fetch your entitlements and print the issue title and body without opening GitHub.

```powershell
pwsh -File ./tools/Submit-RoliEntitlementReport.ps1 -DryRun
```

New licence labels can appear in the report when they fit the lowercase label format. The script screens for key-like values, but a label-shaped value may still contain personal information. Check the preview before sharing it.

To record a reviewed variant, copy its YAML list item from **Entitlement variants** into the baseline under `entitlements:`. Keep the indentation from the generated report.

GitHub applies the **Entitlements Report** label through the issue template once the template is on the repository's default branch and the label exists.

## Notes

- Specifications describe the examined formats and decoders. Compatibility with other application builds, future container versions, or unexamined content is not established.
- Audio decoding and application authorization are separate matters; these documents do not establish that an application will activate or play content on another system.
- Instrument-container versions, audio-container versions, and document revision numbers are independent of one another.
