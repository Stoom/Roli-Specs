# ROLI Airwave Player entitlement consumer

This specification describes the entitlement path recovered from the Windows x64 build of ROLI Airwave Player 1.4.1. Static analysis recovered acquisition, signature verification, and the account and expiry checks that run before the examined consumer adopts the entitlement data. The code findings are static observations. A separate startup observation reached the normal Play interface under the existing account; transport selection and rejection cases were not measured at runtime. The [Connect entitlement interface](roli-connect-entitlements.md) describes the other side of the local transport and the producer of the shared files.

## Acquisition

### Connect pipe and routes

Airwave Player gets `{windows_user}` from `GetUserNameW` and uses `CreateFileW` to open `\\.\pipe\roli_connect_ipc_{windows_user}` for reading and writing. The pipe-name helper removes characters from the set `"#@,;:<>*^|?\/` before adding the Windows pipe prefix. It also shortens names longer than 128 characters. The initial client open retries within a 200-millisecond budget. Matching Connect behavior for unusual and long usernames remains unverified.

Airwave Player takes the path from its internal `roli://connect` URI and sends the requests in the order shown below.

| Order | Purpose | Connect HTTP request target | Shared file name |
| --- | --- | --- | --- |
| 1 | Load the account | `GET /api/v1/user/` | `%2Fapi%2Fv1%2Fuser%2F.json` |
| 2 | Load entitlements | `GET /api/v1/user/entitlements/` | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |

### HTTP exchange

Airwave Player writes the serialized request with overlapped `WriteFile` and parses the response through its pipe-backed input stream. Each request is an HTTP/1.0 GET with `Host: connect` and no body. Header lines end with CRLF, followed by a blank line.

```http
GET /api/v1/user/entitlements/ HTTP/1.0
Host: connect

```

Connect supplies its session token when the request omits `X-Access-Token`. Both routes can return HTTP 511 when Connect has no usable token.

### Shared-file fallback

If Airwave Player cannot open or write to the pipe, or fails to accept the live entitlements, the examined refresh path can use the shared files. A separate cache-only path reads the same files. The traced path showed no switch to Connect’s loopback TCP listener.

The files in the table are under `%APPDATA%/ROLI/Shared`. Each name encodes the request path’s slashes as `%2F`, including the trailing slash.

- Airwave Player loads the account file’s `body` into its account state.
- For the entitlement file, Airwave Player converts the `headers` values to strings, serializes `body` back to JSON text with two-space indentation, and passes both to the same verifier as a synthetic HTTP 200 response.

The reconstructed text must verify against the stored signature. Whitespace, property order, escaping, and number formatting can affect verification.

## Signed entitlement response

The verifier first requires status 200. It reads the following headers as Base64 and obtains the response body as text. For signature verification it passes the body's UTF-8 bytes through the first NUL, excluding the terminator. It parses the verified body as JSON afterward. Preserve the exact live response text and all three headers when archiving a genuine response.

| Header | Decoded record |
| --- | --- |
| `x-message-signature` | 74-byte detached signature record for the entitlement body |
| `x-signer-certificate` | 52-byte signer certificate |
| `x-signer-certificate-signature` | 74-byte detached signature record for the signer certificate |

Offsets below are zero-based byte offsets in decoded records. Airwave Player uses Ed25519 for both signatures. The key and signature layouts are consistent with [OpenBSD Signify-style records](https://man.openbsd.org/signify).

| Record | Offset | Size | Value |
| --- | ---: | ---: | --- |
| Signer certificate | 0 | 2 | ASCII `C1` |
| Signer certificate | 2 | 8 | Expiry as a big-endian count of Unix seconds |
| Signer certificate | 10 | 42 | Signer public-key record |
| Public-key record | 0 | 2 | ASCII `Ed` |
| Public-key record | 2 | 8 | Key ID |
| Public-key record | 10 | 32 | Public key bytes |
| Detached signature record | 0 | 2 | Algorithm tag |
| Detached signature record | 2 | 8 | Signing key ID |
| Detached signature record | 10 | 64 | Signature bytes |

The build embeds this Base64 public trust anchor.

```text
RWTVpFS7WTTlDkLcLodJHUodFa8zi/Nboe+KK83CLQycsOUtVYgJyN9Q
```

### Embedded root key locations

In the Windows x64 Airwave Player 1.4.1 executable with SHA-256 `4ec751a7c1aa640626b8d9337b4b8a0e8d2d8dfd033c3dcf3d13c1c1db10d4a1`, the root key appears as a 56-byte ASCII Base64 string followed by a NUL byte. All eleven exact copies are in `.rdata`. These are hexadecimal offsets from the start of the executable file.

| File offset | RVA | Direct references |
| --- | --- | --- |
| `0xC67540` | `0xC68F40` | A direct reference from the root-record initializer was identified. |
| `0xC83360` | `0xC84D60` | No direct reference in the examined reference inventory. |
| `0xC94EC0` | `0xC968C0` | No direct reference in the examined reference inventory. |
| `0xC964F8` | `0xC97EF8` | No direct reference in the examined reference inventory. |
| `0xCC3640` | `0xCC5040` | No direct reference in the examined reference inventory. |
| `0xEAE8C0` | `0xEB02C0` | No direct reference in the examined reference inventory. |
| `0xF70788` | `0xF72188` | No direct reference in the examined reference inventory. |
| `0x127C320` | `0x127DD20` | No direct reference in the examined reference inventory. |
| `0x12853C0` | `0x1286DC0` | No direct reference in the examined reference inventory. |
| `0x132C238` | `0x132DC38` | No direct reference in the examined reference inventory. |
| `0x13AF358` | `0x13B0D58` | No direct reference in the examined reference inventory. |

**RVA** means relative virtual address. Add it to Airwave Player's actual module base to locate the bytes in memory. A **file offset** counts bytes from the start of the executable on disk.

The initializer at module base + `0xA2E0` constructs the Base64 value and decodes it into the root record consumed by the certificate verifier. An instruction in this initializer directly references the first literal copy. The decoded 42-byte record does not appear verbatim in the executable file. The remaining copies occur near repeated entitlement strings. Their original compilation units and the reason for retaining the duplicates remain unknown. Computed and indirect references remain possible.

### In-process DLL hooking

#### Root key hook point

For this x64 build, the certificate verifier passes the decoded root key record at **Airwave Player module base + `0x18AA3A0`** to its signature-check routine. The record is in the writable, zero-initialized portion of `.data`. The executable’s initializer fills it from the embedded Base64 string. Use the loaded module base when resolving the RVA in a running process.

| Offset from root record | Size | Runtime field |
| --- | ---: | --- |
| `0x00` | 2 bytes | ASCII `Ed` tag |
| `0x02` | 8 bytes | Root key ID used in the certificate signature’s key-ID comparison |
| `0x0A` | 32 bytes | Ed25519 public key |
| `0x2A` | 1 byte | Initialization flag. The decoder writes `1` after copying a 42-byte input. |

This is a candidate data hook for an x64 DLL loaded into the Airwave Player process. A replacement would need to take effect after the initializer writes the record and before the certificate verifier reads it. The key ID and public key must correspond to the root that signs the replacement certificate. The signer certificate and entitlement payload still pass through the normal signature, expiry, and account checks. The location and layout were verified statically. DLL loading and runtime replacement remain untested.

#### Loaded libraries

Airwave Player 1.4.1 imports Windows system libraries and Microsoft runtime libraries. Its installation directory contains no DLLs, and a startup module snapshot showed no Airwave Player-local DLLs.

| Kind | Libraries |
| --- | --- |
| Direct executable imports | `WS2_32.dll`, `ADVAPI32.dll`, `IPHLPAPI.DLL`, `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `SHELL32.dll`, `ole32.dll`, `OLEAUT32.dll`, `COMDLG32.dll`, `MSVCP140.dll`, `WININET.dll`, `SHLWAPI.dll`, `WINMM.dll`, `d2d1.dll`, `dxgi.dll`, `d3d11.dll`, `dcomp.dll`, `IMM32.dll`, `COMCTL32.dll`, `dwmapi.dll`, `VCRUNTIME140_1.dll`, `VCRUNTIME140.dll`, `api-ms-win-crt-heap-l1-1-0.dll`, `api-ms-win-crt-runtime-l1-1-0.dll`, `api-ms-win-crt-convert-l1-1-0.dll`, `api-ms-win-crt-string-l1-1-0.dll`, `api-ms-win-crt-math-l1-1-0.dll`, `api-ms-win-crt-stdio-l1-1-0.dll`, `api-ms-win-crt-environment-l1-1-0.dll`, `api-ms-win-crt-time-l1-1-0.dll`, `api-ms-win-crt-locale-l1-1-0.dll`, `api-ms-win-crt-filesystem-l1-1-0.dll`, `api-ms-win-crt-utility-l1-1-0.dll` |
| Additional Windows modules observed at startup | Includes `DWrite.dll`, `dsound.dll`, `uxtheme.dll`, and `shcore.dll` |
| Host-installed modules observed at startup | `RTSSHooks64.dll`, Apple Bonjour's `mdnsNSP.dll`, A-Volute or Nahimic modules `AudioDevProps2.dll`, `ASM.Plugin.AudioDevProps2.dll`, and `ProductInfo.dll`, and Microsoft Edge WebView's `EmbeddedBrowserWebView.dll` |

The executable imports `LoadLibraryA`, `LoadLibraryW`, and `GetProcAddress`. The import table and startup snapshot establish no app-local DLL replacement point. The entitlement verifier and its root record are in the main executable. The observed external modules describe this host's startup state; they do not establish an application plug-in or injection interface.

### Verification sequence

The verifier reconstructs the certificate from its parsed fields in wire order, then Base64-encodes that record. It verifies the resulting ASCII Base64 text against the embedded trust anchor using `x-signer-certificate-signature`, then rejects a certificate whose expiry is earlier than the current Unix time in whole seconds. It verifies the entitlement body with the certified public key using `x-message-signature`. Each signature check compares the signature's eight-byte key ID with the selected public key's ID before verifying the 64 signature bytes. The certificate parser recognizes the `C1` and `Ed` tags. The signature reader retains its tag, but a separate signature-tag check was not established.

The certificate signature covers the canonical Base64 text. The body signature covers the exact JSON bytes, including whitespace and line endings. Two-space indentation with no terminal newline is a valid representation when it reproduces those bytes. Connect’s shared file stores the parsed body and the three signature headers. Offline acceptance depends on reproducing the signed bytes and satisfying the account and expiry checks.

### Separate local licence validation

The Connect HTTP response and the shared-file fallback converge on the same verifier for the three entitlement signature headers. The certificate check passes the decoded root record at module base + `0x18AA3A0` to the signature routine. The body check passes the signer key from the verified certificate to the same routine.

The refresh code also has a separate local licence branch. Its path helper obtains the Windows local application-data directory and appends `\SpliceSettings\license\`. The local signature path supplies a separate key string object at module base + `0x1899410` and calls the same low-level Ed25519 verifier. This is separate from the Connect signer-certificate chain. The licence file format, product selection, and full acceptance rules remain unspecified.

## Entitlement body and account binding

After signature verification, Airwave Player parses the response body and compares the top-level `uid` with the current account identity. It rejects an identity mismatch. It also rejects a top-level `expiration` earlier than the current clock. The parser multiplies the numeric `expiration` by 1,000 before comparing it with the current Unix time in milliseconds. This payload expiry is independent of the signer certificate expiry.

| JSON member | Observed interpretation |
| --- | --- |
| `uid` | Converted to a string and compared with the current account identity |
| `expiration` | Unix seconds, converted to milliseconds for the response freshness check |
| `entitlements` | Object keyed by entitlement identifier. The parser iterates its properties and reads object-valued entries |
| `entitlements.<id>.enabled` | Converted to a Boolean and retained on the entry |
| `entitlements.<id>.trial_id` | Property presence is recorded. The examined parser uses its presence to decide whether to read `valid_until` |
| `entitlements.<id>.valid_until` | When both trial-related properties are present, the parser converts this value from seconds to milliseconds |
| `entitlements.<id>.licences` | Optional array. Each item is converted to a string and retained on the entry. The meaning of individual licence labels for Airwave Player features remains unverified |

The examined entry parser does not establish handling of a separate per-entry `expiration` member. That member must not be substituted for the top-level payload expiry or the trial field `valid_until`.

The verified and accepted response updates the consumer's entitlement state. On an account mismatch or stale top-level expiration, the examined adoption routine replaces that state with an empty entitlement collection and reports failure. The parser observations establish what fields enter that state. Individual Airwave feature gates and the full per-entry trial rules remain open. The GUI authenticator is constructed with `com.roli.airwaveplayer`. Its entitlement lookup returns the matching entry's `enabled` flag, or false when no entry exists. The constructor also checks a recorded trial end against the current Unix time in milliseconds before reusing an existing authorized state; an expired trial causes it to request a refresh. The full callback-to-feature behavior remains unverified.

A separate GUI initialization path queries `com.roli.airwaveplayer.sound-design`. The inspected function does not establish which controls depend on the returned value. In particular, this observation alone does not prove that the Edit tab is gated by that identifier.

## Preservation and verification

For already licensed accounts, preserve the account record, signed response body, and certificate and signature headers together. An unchanged Airwave Player build still applies both expiry checks during validation. A genuine archived response can therefore have a finite offline lifetime, even when the local transport and cache files remain available. Continued acceptance past the existing expiry dates requires fresh data from an issuer trusted by the build.

The acquisition, verifier, payload adoption, parser, and GUI authenticator decompilations are recorded in Evidence `ev_8aab5aa75beb12d32fccb15f9458ea20d99092cafd6a0b2f43c791d1a98b66b8`, `ev_e65dc6b79b817345dc2c565b9d455e609260fee20d9a71f04f7a143a07e23251`, `ev_96365db6cce3841854dd5137e2eda4572c58ffe38cace10de0c1744c51ee82a9`, `ev_f34f5922fb533838b1cb2b68892dfe9655a05b5bcfa3db2c14c5658fa0d95e8a`, `ev_4fbe04ea6a8e6b92cae1dcbd14a28b1f771853f755b46f5c155559f4cccd3176`, `ev_2c390b1ae3d7ee411ed8b6e0fd7bb4eae9400608720ac1d4d0bc471385c16844`. Static decompilation does not establish runtime acceptance.

A startup observation on 10 November 2026 reached the Play interface, loaded the preset “Blade Runner Brass”, and displayed “Airwave is not connected” without an activation prompt. Settings were inspected without changing their values. The application was closed afterward. This observation used the existing account and services; it did not isolate the transport, exercise audio, or test any signature or expiry rejection.

Use a genuine, authorized fixture to verify the following cases on this build. These checks are pending runtime validation.

1. Capture the account request followed by the entitlement request. Confirm their exact HTTP request targets, pipe framing, and the response body bytes used for signature verification.
2. Replay the same fixture through the pipe and separately through the shared files. Compare the live body with the JSON text Airwave Player reconstructs. Record which cache and transport paths the app uses under normal startup and upstream loss.
3. Isolate each rejection condition. Try a non-200 live status, a missing signature header, a modified body, a mismatched account, an expired certificate, and an expired entitlement body. Use already issued fixtures for the expiry cases.
4. With a successful fixture, verify the relevant Airwave Player features for the licensed device or product. Compare behavior with an account that lacks that entitlement.
