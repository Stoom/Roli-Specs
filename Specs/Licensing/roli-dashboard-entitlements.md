# ROLI Dashboard entitlement consumer

This specification describes the entitlement path recovered from the Windows x86 build of ROLI Dashboard 4.7.2. It follows acquisition, signature verification, and the account and expiry checks that run before Dashboard adopts the entitlement data. The [Connect entitlement interface](roli-connect-entitlements.md) describes the other side of the local transport and the producer of the shared files.

## Acquisition

### Connect pipe and routes

Dashboard gets `{windows_user}` from `GetUserNameW` and uses `CreateFileW` to open `\\.\pipe\roli_connect_ipc_{windows_user}` for reading and writing. It retries the open within its time budget. Connect strips certain characters when creating its pipe name. Matching behavior for usernames containing those characters remains unverified.

Dashboard takes the path from its internal `roli://connect` URI and sends the requests in the order shown below.

| Order | Purpose | Connect HTTP request target | Shared file name |
| --- | --- | --- | --- |
| 1 | Load the account | `GET /api/v1/user/` | `%2Fapi%2Fv1%2Fuser%2F.json` |
| 2 | Load entitlements | `GET /api/v1/user/entitlements/` | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |

### HTTP exchange

Dashboard uses overlapped `WriteFile` and `ReadFile`. Each request is an HTTP/1.0 GET with `Host: connect` and no body. Header lines end with CRLF, followed by a blank line.

```http
GET /api/v1/user/entitlements/ HTTP/1.0
Host: connect

```

Connect supplies its session token when the request omits `X-Access-Token`. Both routes can return HTTP 511 when Connect has no usable token.

### Shared-file fallback

If Dashboard cannot open or write to the pipe, or fails to accept the live entitlements, the examined refresh path can use the shared files. A separate cache-only path reads the same files. The traced path showed no switch to Connect’s loopback TCP listener.

The files in the table are under `%APPDATA%/ROLI/Shared`. Each name encodes the request path’s slashes as `%2F`, including the trailing slash.

- Dashboard loads the account file’s `body` into its account state.
- For the entitlement file, Dashboard converts the `headers` values to strings, serializes `body` back to JSON text, and passes both to the same verifier as a synthetic HTTP 200 response.

The reconstructed text must verify against the stored signature. Whitespace, property order, escaping, and number formatting can affect verification.

## Signed entitlement response

The verifier first requires status 200. It reads the following headers as Base64 and obtains the response body as text. For signature verification it passes the body's UTF-8 bytes through the first NUL, excluding the terminator. It parses the verified body as JSON afterward. Preserve the exact live response text and all three headers when archiving a genuine response.

| Header | Decoded record |
| --- | --- |
| `x-message-signature` | 74-byte detached signature record for the entitlement body |
| `x-signer-certificate` | 52-byte signer certificate |
| `x-signer-certificate-signature` | 74-byte detached signature record for the signer certificate |

Offsets below are zero-based byte offsets in decoded records. Dashboard uses Ed25519 for both signatures. The key and signature layouts are consistent with [OpenBSD Signify-style records](https://man.openbsd.org/signify).

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

In the Windows x86 Dashboard 4.7.2 executable with SHA-256 `3dd3f31bf2f5e64d9f92d722d5efbdb7ab443a8474ab71f8d9dcdc0ee619545a`, the root key appears as a 56-byte ASCII Base64 string followed by a NUL byte. All five exact copies are in `.rdata`. These are hexadecimal offsets from the start of the executable file.

| File offset | RVA | Direct references |
| --- | --- | --- |
| `0x545470` | `0x546070` | Four relocated operands in the initializer read the string at byte offsets 0, 16, 32, and 48. |
| `0x550ED0` | `0x551AD0` | No direct absolute address reference found. |
| `0x657964` | `0x658564` | No direct absolute address reference found. |
| `0x65F830` | `0x660430` | No direct absolute address reference found. |
| `0x6B7318` | `0x6B7F18` | No direct absolute address reference found. |

**RVA** means relative virtual address. Add it to Dashboard’s actual module base to locate the bytes in memory. A **file offset** counts bytes from the start of the executable on disk.

The initializer starts reading the first copy at file offset `0x53DB`. It decodes the assembled string into the root record consumed by the certificate verifier. The decoded 42-byte record does not appear verbatim in the executable file.

Three of the other copies sit near repeated strings from the same feature area. The regions at `0x550ED0` and `0x657964` repeat entitlement field names, and the region at `0x6B7318` repeats Dashboard preset and account field names. That pattern is consistent with separate groups of string literals being retained in the linked executable. The original compilation units and the exact reason the duplicates were retained remain unknown. The reference check covers direct absolute addresses into the string bytes. Computed and indirect references remain possible.

### In-process DLL hooking

#### Root key hook point

For this x86 build, the certificate verifier passes the decoded root key record at **Dashboard module base + `0xC6F130`** to its signature-check routine. The record is in the writable, zero-initialized portion of `.data`. The executable’s initializer fills it from the embedded Base64 string. Use the loaded module base when resolving the RVA in a running process.

| Offset from root record | Size | Runtime field |
| --- | ---: | --- |
| `0x00` | 2 bytes | ASCII `Ed` tag |
| `0x02` | 8 bytes | Root key ID used in the certificate signature’s key-ID comparison |
| `0x0A` | 32 bytes | Ed25519 public key |
| `0x2A` | 1 byte | Initialization flag. The decoder writes `1` after copying a 42-byte input. |

This is a candidate data hook for an x86 DLL loaded into the Dashboard process. A replacement would need to take effect after the initializer writes the record and before the certificate verifier reads it. The key ID and public key must correspond to the root that signs the replacement certificate. The signer certificate and entitlement payload still pass through the normal signature, expiry, and account checks. The location and layout were verified statically. DLL loading and runtime replacement remain untested.

#### Loaded libraries

Dashboard 4.7.2 imports Windows DLLs for system services, networking, graphics, audio, and debugging. The installed Dashboard directory contains no DLLs, and a startup module snapshot showed no Dashboard-local DLLs.

| Kind | Libraries |
| --- | --- |
| Direct executable imports | `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `COMDLG32.dll`, `ADVAPI32.dll`, `SHELL32.dll`, `ole32.dll`, `OLEAUT32.dll`, `WININET.dll`, `WS2_32.dll`, `SHLWAPI.dll`, `WINMM.dll`, `dbghelp.dll`, `IMM32.dll`, `dxgi.dll`, `OPENGL32.dll` |
| Additional Windows modules observed at startup | Includes `COMCTL32.dll`, `d2d1.dll`, `DWrite.dll`, `dsound.dll`, `iphlpapi.dll`, `shcore.dll`, and `uxtheme.dll` |
| Host-installed modules observed at startup | `RTSSHooks.dll`, Apple Bonjour’s `mdnsNSP.dll`, and A-Volute or Nahimic modules `AudioDevProps2.dll`, `ASM.Plugin.AudioDevProps2.dll`, and `ProductInfo.dll` |

The executable imports `LoadLibraryA`, `LoadLibraryW`, `LoadLibraryExW`, and `GetProcAddress`. The observed host modules show that external DLLs can be present in the process. The import table and startup snapshot establish no Dashboard plug-in loader or verified app-local DLL replacement point. The entitlement verifier and its root record are in the Dashboard executable.

### Verification sequence

The verifier reconstructs the certificate from its parsed fields in wire order, then Base64-encodes that record. It verifies the resulting ASCII Base64 text against the embedded trust anchor using `x-signer-certificate-signature`, then rejects a certificate whose expiry is earlier than the current Unix time in whole seconds. It verifies the entitlement body with the certified public key using `x-message-signature`. Each signature check compares the signature's eight-byte key ID with the selected public key's ID before verifying the 64 signature bytes. The certificate parser recognizes the `C1` and `Ed` tags. The signature reader retains its tag, but a separate signature-tag check was not established.

The certificate signature covers the canonical Base64 text. The body signature covers the exact JSON bytes, including whitespace and line endings. Two-space indentation with no terminal newline is a valid representation when it reproduces those bytes. Connect’s shared file stores the parsed body and the three signature headers. Offline acceptance depends on reproducing the signed bytes and satisfying the account and expiry checks.

### Separate local licence validation

The Connect HTTP response and the shared-file fallback converge on the same verifier for the three entitlement signature headers. The certificate check passes the decoded root record at module base + `0xC6F130` to the signature routine. The body check passes the signer key from the verified certificate to the same routine.

The refresh code also has a separate local licence branch that reads from a path containing `\SpliceSettings\license\`. That branch shares the low-level Ed25519 verifier and supplies a different public key. Its initializer copies a 44-byte Base64 string from module base + `0xB5B44C` into a separate string object at module base + `0xC333A0`. The local licence branch consumes that string. Its licence file format and full acceptance rules remain unspecified.

## Entitlement body and account binding

After signature verification, Dashboard parses the response body and compares the top-level `uid` with the current account identity. It rejects an identity mismatch. It also rejects a top-level `expiration` earlier than the current clock. The parser multiplies the numeric `expiration` by 1,000 before comparing it with the current Unix time in milliseconds. This payload expiry is independent of the signer certificate expiry.

| JSON member | Observed interpretation |
| --- | --- |
| `uid` | Converted to a string and compared with the current account identity |
| `expiration` | Unix seconds, converted to milliseconds for the response freshness check |
| `entitlements` | Object keyed by entitlement identifier. The parser iterates its properties and reads object-valued entries |
| `entitlements.<id>.enabled` | Converted to a Boolean and retained on the entry |
| `entitlements.<id>.trial_id` | Property presence is recorded. The examined parser uses its presence to decide whether to read `valid_until` |
| `entitlements.<id>.valid_until` | When both trial-related properties are present, the parser converts this value from seconds to milliseconds |
| `entitlements.<id>.licences` | Optional array consumed as part of the entry. The item schema and its effect on individual Dashboard features remain unverified |

A user-supplied Airwave Player entitlement entry also had a nullable `expiration` member under `entitlements.<id>`. This member is distinct from the top-level payload expiry and the trial field `valid_until`. The traced Dashboard path establishes the top-level check. Handling of the per-entry field remains unverified.

The verified and accepted response updates Dashboard's entitlement state. The parser observations establish what fields enter that state. They leave product ID mappings, individual feature gates, and the full per-entry trial and licence rules open.

## Preservation and verification

For already licensed accounts, preserve the account record, signed response body, and certificate and signature headers together. An unchanged Dashboard build still applies both expiry checks during validation. A genuine archived response can therefore have a finite offline lifetime, even when the local transport and cache files remain available. Continued acceptance past the existing expiry dates requires fresh data from an issuer trusted by the build.

Use a genuine, authorized fixture to verify the following cases on this build. These checks are pending runtime validation.

1. Capture the account request followed by the entitlement request. Confirm their exact HTTP request targets, pipe framing, and the response body bytes used for signature verification.
2. Replay the same fixture through the pipe and separately through the shared files. Compare the live body with the JSON text Dashboard reconstructs. Record which cache and transport paths the app uses under normal startup and upstream loss.
3. Isolate each rejection condition. Try a non-200 live status, a missing signature header, a modified body, a mismatched account, an expired certificate, and an expired entitlement body. Use already issued fixtures for the expiry cases.
4. With a successful fixture, verify the relevant Dashboard features for the licensed device or product. Compare behavior with an account that lacks that entitlement.
