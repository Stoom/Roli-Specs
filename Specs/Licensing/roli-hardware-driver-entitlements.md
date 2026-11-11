# ROLI Hardware Driver entitlement consumer

This specification describes the entitlement investigation of the Windows x64 build of ROLI Hardware Driver 0.7.1. Static analysis recovered the application startup and hardware-server construction paths, but did not establish a Dashboard-style entitlement consumer in this executable. The [Connect entitlement interface](roli-connect-entitlements.md) describes the producer of the shared account and entitlement files. A product's appearance in Connect's entitlement catalog does not establish that its executable reads those files.

## Acquisition

### Connect pipe and routes

No Connect pipe name, account route, or entitlement route was recovered from the examined executable. Searches of the completed string inventory for `entitlement`, `roli_connect`, `/api/v1/user`, `license`, and `licence` returned no matches. A separate ASCII and UTF-16LE examination of the file also found no Dashboard entitlement signature-header or root-key literals.

The decompiled startup constructs an `RHDServerApplication`, supplies version `0.7.1` and build identifier `20251014124911-8de40468`, and constructs an `RHDServer`. That constructor initializes physical topology, hardware callbacks, two IPC listener objects, an Airwave firmware checker, and an `RHDWatchdog`. The listener objects receive numeric values `0x326F` and `0x326E`, respectively. Their complete transport protocol is outside this entitlement investigation. These hardware-server paths must not be identified as Connect's HTTP entitlement transport merely because they use IPC.

### HTTP exchange

No entitlement HTTP exchange was established. The executable imports WinINet and Windows socket APIs, but imports alone do not identify an entitlement request or prove that one occurs during startup. Dashboard's HTTP request targets, order, and framing have not been attributed to Hardware Driver.

### Shared-file fallback

No account or entitlement shared-file fallback was recovered. The executable contains generic `Shared` strings; their presence does not establish access to `%APPDATA%/ROLI/Shared` or either encoded Connect cache filename. Preserve this distinction when inspecting hardware state and configuration files.

## Signed entitlement response

No consumer of `x-message-signature`, `x-signer-certificate`, or `x-signer-certificate-signature` was recovered. The header literals were absent from the bounded file examination and the completed string search. Consequently, no entitlement signature-record layout or certificate expiry rule is attributed to Hardware Driver by this investigation.

### Embedded root key locations

The Windows x64 Hardware Driver 0.7.1 executable has SHA-256 `5e8b1ab05ba6ada7684a13ea84609e3b47884e7ebf02f71ac14017e031410b36`. No exact ASCII copy of Dashboard's 56-byte Base64 trust anchor was found. Its decoded 42-byte public-key record was also absent from the file examination.

This result is specific to that key and those representations. It does not prove that the executable contains no cryptography or that hardware or firmware messages have no integrity checks.

### In-process DLL hooking

#### Root key hook point

No entitlement root record or corresponding data hook was established. Dashboard's root-record RVA and layout cannot be transferred to this x64 executable. No DLL injection or runtime replacement was performed.

#### Loaded libraries

The executable's PE import table names the following libraries.

| Kind | Libraries |
| --- | --- |
| Direct executable imports | `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `COMDLG32.dll`, `ADVAPI32.dll`, `SHELL32.dll`, `ole32.dll`, `OLEAUT32.dll`, `WININET.dll`, `WS2_32.dll`, `SHLWAPI.dll`, `WINMM.dll`, `IMM32.dll`, `dxgi.dll` |
| DLLs present in the installed directory | `logger.dll`, `srvstart.dll` |

Directory presence does not establish that the driver executable loads those local DLLs. A running Hardware Driver process was present during the investigation, but its module paths could not be read with the available process access. No startup module inventory or app-local DLL replacement point was verified.

### Verification sequence

No Dashboard-style certificate, body-signature, and payload-expiry sequence was recovered. The absence of the searched literals and the inspected startup paths supports a bounded negative finding, rather than a claim that every possible execution path has been proved free of entitlement checks.

### Separate local licence validation

No `\SpliceSettings\license\` literal or corresponding local licence path was recovered. The hardware-server constructor contains firmware and topology checks, but their presence is not evidence of account licence validation.

## Entitlement body and account binding

No parser for a Connect entitlement body, comparison against account `uid`, or top-level entitlement `expiration` check was established. No `enabled`, `trial_id`, `valid_until`, or `licences` semantics are assigned to Hardware Driver here. The sanitized repository baseline's `com.roli.roliblocksserver` entry describes an issuer-side product identifier; it does not independently prove a feature gate in the executable.

## Preservation and verification

Preserve the identified executable and its matching hardware configuration when reproducing these observations. This investigation does not establish that archiving Connect's signed entitlement files is required for Hardware Driver startup, or that those files are sufficient for hardware operation.

The completed string search is recorded as Evidence `ev_6494b021745e593406be64e7547879f187dd09b19bf6c3a7c214d0eaeaf8fe80`. Startup decompilation is recorded as `ev_4182844df7b86e6d9d35077159b0a13c318631e4f63d6daaff6a21df3215e910`; the hardware-server constructor is recorded as `ev_7b447aa8c138e8529f5b3f1638ac965ff3548b69a4ae85536aa7db7bb564c476`. Static analysis did not observe execution of these paths.

The following checks remain pending runtime validation.

1. Observe the existing service's file and pipe activity without changing its service configuration. Determine whether it accesses Connect or the shared account and entitlement files.
2. Compare normal operation and upstream Connect loss with an authorized hardware setup. Separate hardware discovery, firmware compatibility, and topology failures from account authorization.
3. If an entitlement exchange is observed, trace its actual caller and parser before applying the response format documented for Dashboard.
4. Test the relevant device operations across authorized account states. The present investigation establishes no account-dependent hardware feature gate.
