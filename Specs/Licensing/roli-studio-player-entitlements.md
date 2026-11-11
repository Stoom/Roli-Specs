# ROLI Studio Player entitlement consumer

This specification describes the entitlement path recovered from the Windows x64 build of ROLI Studio Player 1.4.1. It follows acquisition, signature verification, and the account and expiry checks that run before Studio Player adopts the entitlement data. The [Connect entitlement interface](roli-connect-entitlements.md) describes the other side of the local transport and the producer of the shared files.

## Acquisition

### Connect pipe and routes

Studio Player gets `{windows_user}` from `GetUserNameW` and uses `CreateFileW` to open `\\.\pipe\roli_connect_ipc_{windows_user}` for reading and writing. The traced client open uses a 200 ms retry budget. Before adding the Windows pipe prefix, the client removes the characters `" # @ , ; : < > * ^ | ? \ /` from the combined name, where spaces separate individual characters. Connect also filters its suffix, but takes that suffix from the environment rather than `GetUserNameW`. Matching behavior for unusual usernames remains untested at runtime.

Studio Player takes the path from its internal `roli://connect` URI and sends the requests in the order shown below.

| Order | Purpose | Connect HTTP request target | Shared file name |
| --- | --- | --- | --- |
| 1 | Load the account | `GET /api/v1/user/` | `%2Fapi%2Fv1%2Fuser%2F.json` |
| 2 | Load entitlements | `GET /api/v1/user/entitlements/` | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |

### HTTP exchange

Studio Player uses overlapped `WriteFile` and `ReadFile`. Each request is an HTTP/1.0 GET with `Host: connect` and no body. Header lines end with CRLF, followed by a blank line.

```http
GET /api/v1/user/entitlements/ HTTP/1.0
Host: connect

```

Connect supplies its session token when the request omits `X-Access-Token`. Both routes can return HTTP 511 when Connect has no usable token.

### Shared-file fallback

If Studio Player cannot open or write to the pipe, or fails to accept the live entitlements, the examined refresh path can use the shared files. A separate cache-only path reads the same files. The traced path showed no switch to Connect’s loopback TCP listener.

The files in the table are under `%APPDATA%/ROLI/Shared`. Each name encodes the request path’s slashes as `%2F`, including the trailing slash.

- Studio Player loads the account file’s `body` into its account state.
- For the entitlement file, Studio Player converts the `headers` values to strings, serializes `body` back to JSON text, and passes both to the same verifier as a synthetic HTTP 200 response.

The reconstructed text must verify against the stored signature. Whitespace, property order, escaping, and number formatting can affect verification.

## Signed entitlement response

The verifier first requires status 200. It reads the following headers as Base64 and obtains the response body as text. For signature verification it passes the body's UTF-8 bytes through the first NUL, excluding the terminator. It parses the verified body as JSON afterward. Preserve the exact live response text and all three headers when archiving a genuine response.

| Header | Decoded record |
| --- | --- |
| `x-message-signature` | 74-byte detached signature record for the entitlement body |
| `x-signer-certificate` | 52-byte signer certificate |
| `x-signer-certificate-signature` | 74-byte detached signature record for the signer certificate |

Offsets below are zero-based byte offsets in decoded records. Studio Player uses Ed25519 for both signatures. The key and signature layouts are consistent with [OpenBSD Signify-style records](https://man.openbsd.org/signify).

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

In the Windows x64 Studio Player 1.4.1 executable with SHA-256 `e777ee1565c54781d2ad234942171cb31a6be868e8205290aabf10336318f0c5`, the root key appears as a 56-byte ASCII Base64 string followed by a NUL byte. All 8 exact copies are in `.rdata`. These are hexadecimal offsets from the start of the executable file.

| File offset | RVA | Direct references |
| --- | --- | --- |
| `0x11F16D8` | `0x11F2CD8` | The initializer reads the string at byte offsets 0, 16, 32, and 48. |
| `0x1226D08` | `0x1228308` | No direct reference found in the examined reference inventory. |
| `0x123B2D0` | `0x123C8D0` | No direct reference found in the examined reference inventory. |
| `0x1240000` | `0x1241600` | No direct reference found in the examined reference inventory. |
| `0x1252FC0` | `0x12545C0` | No direct reference found in the examined reference inventory. |
| `0x12E9C98` | `0x12EB298` | No direct reference found in the examined reference inventory. |
| `0x131CDC0` | `0x131E3C0` | No direct reference found in the examined reference inventory. |
| `0x132F580` | `0x1330B80` | No direct reference found in the examined reference inventory. |

**RVA** means relative virtual address. Add it to Studio Player’s actual module base to locate the bytes in memory. A **file offset** counts bytes from the start of the executable on disk.

The initializer starts reading the first copy at file offset `0x890823`. Its machine code uses three 16-byte loads and one eight-byte load to assemble the Base64 text, then decodes it into the root record consumed by the certificate verifier. The decompiled pseudocode folds those loads into constants; the assembly establishes the references in the table. The decoded 42-byte record does not appear verbatim in the executable file.

The remaining copies occur in repeated groups of entitlement and account strings. Their original compilation units and the reason the linker retained the copies remain unknown. The reference check covers direct references; computed and indirect references remain possible.

### In-process DLL hooking

#### Root key hook point

For this x64 build, the certificate verifier passes the decoded root key record at **Studio Player module base + `0x2235450`** to its signature-check routine. The record is in the writable, zero-initialized portion of `.data`. The executable’s initializer fills it from the embedded Base64 string. Use the loaded module base when resolving the RVA in a running process.

| Offset from root record | Size | Runtime field |
| --- | ---: | --- |
| `0x00` | 2 bytes | ASCII `Ed` tag |
| `0x02` | 8 bytes | Root key ID used in the certificate signature’s key-ID comparison |
| `0x0A` | 32 bytes | Ed25519 public key |
| `0x2A` | 1 byte | Initialization flag. The decoder writes `1` after copying a 42-byte input. |

This is a candidate data hook for an x64 DLL loaded into the Studio Player process. A replacement would need to take effect after the initializer writes the record and before the certificate verifier reads it. The key ID and public key must correspond to the root that signs the replacement certificate. The signer certificate and entitlement payload still pass through the normal signature, expiry, and account checks. The location and layout were verified statically. DLL loading and runtime replacement remain untested.

#### Loaded libraries

Studio Player 1.4.1 imports Windows DLLs for system services, networking, graphics, audio, and debugging. The installed application directory contains no DLLs, and a startup module snapshot showed no application-local DLLs.

| Kind | Libraries |
| --- | --- |
| Direct executable imports | `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `COMDLG32.dll`, `ADVAPI32.dll`, `SHELL32.dll`, `ole32.dll`, `OLEAUT32.dll`, `WININET.dll`, `WS2_32.dll`, `VERSION.dll`, `SHLWAPI.dll`, `WINMM.dll`, `IMM32.dll`, `dxgi.dll`, `OPENGL32.dll`, `RPCRT4.dll`, `gdiplus.dll` |
| Additional Windows modules observed at startup | Includes `COMCTL32.dll`, `d2d1.dll`, `DWrite.dll`, `dsound.dll`, `iphlpapi.dll`, `shcore.dll`, and `uxtheme.dll` |
| Host-installed modules observed at startup | `RTSSHooks64.dll`, Apple Bonjour’s `mdnsNSP.dll`, and A-Volute or Nahimic modules `AudioDevProps2.dll`, `ASM.Plugin.AudioDevProps2.dll`, and `ProductInfo.dll` |

The executable imports `LoadLibraryA`, `LoadLibraryW`, `LoadLibraryExW`, and `GetProcAddress`. The observed host modules show that external DLLs can be present in the process. The import table and startup snapshot establish no entitlement-specific DLL loader or verified app-local DLL replacement point. The entitlement verifier and its root record are in the executable. This snapshot covers the standalone application; separately installed audio plug-ins were not examined.

### Verification sequence

The verifier reconstructs the certificate from its parsed fields in wire order, then Base64-encodes that record. It verifies the resulting ASCII Base64 text against the embedded trust anchor using `x-signer-certificate-signature`, then rejects a certificate whose expiry is earlier than the current Unix time in whole seconds. It verifies the entitlement body with the certified public key using `x-message-signature`. Each signature check compares the signature's eight-byte key ID with the selected public key's ID before verifying the 64 signature bytes. The certificate parser recognizes the `C1` and `Ed` tags. The signature reader retains its tag, but a separate signature-tag check was not established.

The certificate signature covers the canonical Base64 text. The body signature covers the exact JSON bytes, including whitespace and line endings. Two-space indentation with no terminal newline is a valid representation when it reproduces those bytes. Connect’s shared file stores the parsed body and the three signature headers. Offline acceptance depends on reproducing the signed bytes and satisfying the account and expiry checks.

### Separate local licence validation

The Connect HTTP response and the shared-file fallback converge on the same verifier for the three entitlement signature headers. The certificate check passes the decoded root record at module base + `0x2235450` to the signature routine. The body check passes the signer key from the verified certificate to the same routine.

The refresh code also has a separate local licence branch that reads from a path containing `\SpliceSettings\license\`. That branch shares the low-level Ed25519 verifier and supplies a different public key. Its initializer fills a separate 44-byte Base64 public-key string object at module base + `0x2169E28`. The local licence branch consumes that string. This is a raw 32-byte public key after decoding, rather than the 42-byte entitlement root record. Its full licence file format and acceptance rules remain unspecified.

## Entitlement body and account binding

After signature verification, Studio Player parses the response body and compares the top-level `uid` with the current account identity. It rejects an identity mismatch. It also rejects a top-level `expiration` earlier than the current clock. The parser multiplies the numeric `expiration` by 1,000 before comparing it with the current Unix time in milliseconds. This payload expiry is independent of the signer certificate expiry.

| JSON member | Observed interpretation |
| --- | --- |
| `uid` | Converted to a string and compared with the current account identity |
| `expiration` | Unix seconds, converted to milliseconds for the response freshness check |
| `entitlements` | Object keyed by entitlement identifier. The parser iterates its properties and reads object-valued entries |
| `entitlements.<id>.enabled` | Converted to a Boolean and retained on the entry |
| `entitlements.<id>.trial_id` | Property presence is recorded. The examined parser uses its presence to decide whether to read `valid_until` |
| `entitlements.<id>.valid_until` | When both trial-related properties are present, the parser converts this value from seconds to milliseconds |
| `entitlements.<id>.licences` | Optional array whose items are converted to strings and retained on the entry. Their effect on individual features remains unverified |

The traced entry parser does not read a per-entry `expiration` member. The top-level payload expiry and the trial field `valid_until` are separate checks. This does not establish how other application paths handle an added per-entry field.

The verified and accepted response updates Studio Player’s entitlement state. An account mismatch or stale top-level payload clears the stored entitlement collection in the examined acceptance routine. The GUI dependency manager passes `com.roli.studioplayer` to its `Authenticator`. The authenticator’s existing-state check looks up that exact entry, requires its retained `enabled` value, and checks a retained trial deadline when present before deciding whether to request a refresh. The mapping is recovered from code, rather than inferred from the product catalog. The precise effects on playback, editing, and individual content packs remain unverified.

## Preservation and verification

For already licensed accounts, preserve the account record, signed response body, and certificate and signature headers together. An unchanged Studio Player build still applies both expiry checks during validation. A genuine archived response can therefore have a finite offline lifetime, even when the local transport and cache files remain available. Continued acceptance past the existing expiry dates requires fresh data from an issuer trusted by the build.

Evidence anchors are `ev_b91285163ffc2ce4a53b7bc0f94e76cd169439b40a802add0828bc3a9fcd5ffc` for refresh and fallback, `ev_c6743baa5c179cffb1f588536fb80985d87682a93f48cfc4ebe5b76408361f0a` for signature verification, `ev_c1c7a6f03423f7bacee457f9065e465fea9831f454cd0d4a759f7d8bc6e0af76` for root initialization, `ev_86f39c644a9291512cd8c0f5b065b4c8b1e916924bb5bdf200d5b05508e2c6e5` for payload fields, `ev_06395c792f9b817c4dee8b17d4d8caa07ec7d7583a6d08bfa8341707ca1a8cc4` for account and expiry acceptance, and `ev_a02381f0732145f5729fc66b14017fb5e6212970cbe78196c20a4e84c8bb129b` for the product identifier. These are static observations; startup module enumeration does not validate entitlement acceptance.

Use a genuine, authorized fixture to verify the following cases on this build. Startup and loaded-library observations were performed. The entitlement cases below remain pending runtime validation.

1. Capture the account request followed by the entitlement request. Confirm their exact HTTP request targets, pipe framing, and the response body bytes used for signature verification.
2. Replay the same fixture through the pipe and separately through the shared files. Compare the live body with the JSON text Studio Player reconstructs. Record which cache and transport paths the app uses under normal startup and upstream loss.
3. Isolate each rejection condition. Try a non-200 live status, a missing signature header, a modified body, a mismatched account, an expired certificate, and an expired entitlement body. Use already issued fixtures for the expiry cases.
4. With a successful fixture, verify the relevant Studio Player features for the licensed device or product. Compare behavior with an account that lacks that entitlement.
