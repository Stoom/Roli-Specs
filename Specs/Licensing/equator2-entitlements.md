# Equator2 entitlement consumer

This specification describes the entitlement path recovered from the Windows x64 build of Equator2 2.5.2. It follows acquisition, signature verification, and the account and expiry checks that run before Equator2 adopts the entitlement data. The [Connect entitlement interface](roli-connect-entitlements.md) describes the other side of the local transport and the producer of the shared files. The findings apply to the examined standalone executable; separate plug-in builds and runtime acceptance were not verified.

## Acquisition

### Connect pipe and routes

Equator2 gets `{windows_user}` from `GetUserNameW`, combines it with `roli_connect_ipc_`, and opens the resulting Windows named pipe for reading and writing using `CreateFileW`. The pipe constructor supplies the `\\.\pipe\` prefix. The examined open call retries within a 200-millisecond budget. Matching behavior for usernames requiring pipe-name sanitization remains unverified.

Equator2 builds its base URI as `roli://connect/api/v1` and appends the paths below. The traced refresh requests the account first and requests entitlements after successfully parsing the account.

| Order | Purpose | Connect HTTP request target | Shared file name |
| --- | --- | --- | --- |
| 1 | Load the account | `GET /api/v1/user/` | `%2Fapi%2Fv1%2Fuser%2F.json` |
| 2 | Load entitlements | `GET /api/v1/user/entitlements/` | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |

### HTTP exchange

Equator2 uses overlapped `WriteFile` and `ReadFile`. The pipe request path selects HTTP/1.0 and the GET method. It derives the `Host` header from the URI host, `connect`, and sends no request body in the traced acquisition. Header lines end with CRLF, followed by a blank line.

```http
GET /api/v1/user/entitlements/ HTTP/1.0
Host: connect

```

Connect supplies its session token when the request omits `X-Access-Token`. Both routes can return HTTP 511 when Connect has no usable token; this is behavior of the [Connect proxy](roli-connect-entitlements.md).

### Shared-file fallback

If live entitlements are not accepted and the separate local licence branch has not succeeded, the traced refresh loads the cached account and then the cached entitlements. The examined path does not switch from its named pipe to Connect's loopback TCP listener.

The cache path constructor starts from `%APPDATA%`, appends `ROLI/Shared`, replaces each slash in `/api/v1` plus the route with `%2F`, and appends `.json`. This produces the filenames in the table, including the encoded trailing slash.

- Equator2 loads the account file's `body` into its account state.
- For the entitlement file, Equator2 converts the `headers` values to strings, serializes `body` back to JSON text, and passes both to the same verifier as a synthetic HTTP 200 response.

The reconstructed text must verify against the stored signature. Whitespace, property order, escaping, and number formatting can affect verification.

## Signed entitlement response

The verifier first requires status 200. It reads the following headers as Base64 and obtains the response body as text. For signature verification it copies the body's UTF-8 text through the first NUL, excluding the terminator. The acceptance wrapper parses the body as JSON after successful signature verification. Preserve the exact live response text and all three headers when archiving a genuine response.

| Header | Decoded record |
| --- | --- |
| `x-message-signature` | 74-byte detached signature record for the entitlement body |
| `x-signer-certificate` | 52-byte signer certificate |
| `x-signer-certificate-signature` | 74-byte detached signature record for the signer certificate |

Offsets below are zero-based byte offsets in decoded records. Equator2 uses Ed25519 for both signatures. The certificate parser checks the `C1` and `Ed` tags and decodes the expiry in big-endian order.

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

In the Windows x64 Equator2 2.5.2 executable with SHA-256 `0db0b00d39bd4dc9308fd882ea14a50500d002d95aa88fc7ddbdb38e74396f89`, the root key appears as a 56-byte ASCII Base64 string followed by a NUL byte. All eight exact copies are in `.rdata`. These are hexadecimal offsets from the start of the executable file.

| File offset | RVA | Direct references |
| --- | --- | --- |
| `0x8A3148` | `0x8A4548` | Initializer loads at string offsets 0, 16, 32, and 48. |
| `0x928578` | `0x929978` | No direct reference to the string's start found in the examined code. |
| `0x9348D0` | `0x935CD0` | No direct reference to the string's start found in the examined code. |
| `0x9F0BD8` | `0x9F1FD8` | No direct reference to the string's start found in the examined code. |
| `0xAB9B58` | `0xABAF58` | No direct reference to the string's start found in the examined code. |
| `0xACBB68` | `0xACCF68` | No direct reference to the string's start found in the examined code. |
| `0xADB888` | `0xADCC88` | No direct reference to the string's start found in the examined code. |
| `0xE95870` | `0xE96C70` | No direct reference to the string's start found in the examined code. |

**RVA** means relative virtual address. Add it to Equator2's actual module base to locate the bytes in memory. A **file offset** counts bytes from the start of the executable on disk. The preferred image base is `0x140000000`; a running process can use another base.

The initializer at RVA `0x1000` starts loading the first copy at file offset `0x413`. It decodes the assembled string into the root record consumed by the certificate verifier. The decoded 42-byte record does not appear verbatim in the executable file. Repeated entitlement field names occur near several other copies. Their original compilation-unit ownership and the reason they were retained remain unknown. Computed and indirect references remain possible.

### In-process DLL hooking

#### Root key hook point

For this x64 build, the certificate verifier passes the decoded root key record at **Equator2 module base + `0x1192A60`** to its signature-check routine. The record is in the writable, zero-initialized portion of `.data`. The executable's initializer fills it from the embedded Base64 string. Use the loaded module base when resolving the RVA in a running process.

| Offset from root record | Size | Runtime field |
| --- | ---: | --- |
| `0x00` | 2 bytes | ASCII `Ed` tag |
| `0x02` | 8 bytes | Root key ID used in the certificate signature's key-ID comparison |
| `0x0A` | 32 bytes | Ed25519 public key |
| `0x2A` | 1 byte | Initialization flag. The decoder sets it when the decoded input has 42 bytes. |

This identifies the build-specific data location corresponding to Dashboard's root-record hook point. Initialization and verifier use were verified statically. DLL loading, injection, and runtime replacement were not performed. The signer certificate, entitlement body, account identity, and expiry checks remain separate parts of the acceptance path.

#### Loaded libraries

Equator2 2.5.2 imports Windows DLLs for system services, networking, graphics, and audio. The installed Equator2 directory contains no DLLs.

| Kind | Libraries |
| --- | --- |
| Direct executable imports | `KERNEL32.dll`, `USER32.dll`, `GDI32.dll`, `COMDLG32.dll`, `ADVAPI32.dll`, `SHELL32.dll`, `ole32.dll`, `OLEAUT32.dll`, `WININET.dll`, `WS2_32.dll`, `SHLWAPI.dll`, `WINMM.dll`, `IMM32.dll`, `dxgi.dll`, `OPENGL32.dll` |
| Additional Windows modules observed at startup | Not captured for this build. |
| Host-installed modules observed at startup | Not captured for this build. |

The executable imports `LoadLibraryA`, `LoadLibraryW`, `LoadLibraryExW`, and `GetProcAddress`. These imports do not establish an app-local DLL replacement point. The examined entitlement verifier and root record are in the Equator2 executable.

### Verification sequence

The verifier reconstructs the certificate from its parsed fields in wire order and Base64-encodes that record. It verifies this ASCII Base64 text against the embedded trust anchor using `x-signer-certificate-signature`, then rejects a certificate whose expiry is earlier than the current Unix time in whole seconds. It verifies the entitlement body with the certified public key using `x-message-signature`.

Each signature check compares the signature's eight-byte key ID with the selected public key's ID before checking the 64 signature bytes. The signature-record parser retains its two-byte tag; a separate signature-tag check was not established in the traced comparison routine.

The certificate signature covers the canonical Base64 text. The body signature covers the exact JSON text, including whitespace and line endings. Connect's shared file stores the parsed body and the three signature headers. Offline acceptance depends on reproducing the signed text and satisfying the account and expiry checks.

### Separate local licence validation

The live Connect response and shared-file fallback converge on the same three-header verifier. The refresh also contains an optional, separate local licence branch that reads under `%LOCALAPPDATA%\SpliceSettings\license\`. It uses the same low-level Ed25519 routine with a different public key. Its initializer copies a 44-byte Base64 string from RVA `0xE8EC68` into a separate string object at RVA `0x110CF30`. The local licence verifier consumes this string rather than the Connect root record.

The local file parser checks a product field, an activation flag, and time bounds before the wrapper performs its signature check. The examined conditions reject a start time more than 86,400 seconds ahead, an expiry earlier than the current time, and an expiry more than 7,776,000 seconds ahead. These are separate local-licence rules. The complete file format, caller-selected product value, and runtime behavior remain unspecified.

## Entitlement body and account binding

After signature verification, Equator2 parses the response body and compares its top-level `uid` with the account identity. A mismatch rejects the response. It also rejects a top-level `expiration` earlier than the current clock. The parser multiplies the numeric value by 1,000 before comparing it with the current Unix time in milliseconds. This payload expiry is independent of the signer certificate expiry.

| JSON member | Observed interpretation |
| --- | --- |
| `uid` | Converted to a string and compared with the current account identity |
| `expiration` | Unix seconds, converted to milliseconds for the response freshness check |
| `entitlements` | Object keyed by entitlement identifier. The parser iterates its properties and reads object-valued entries |
| `entitlements.<id>.enabled` | Converted to a Boolean and retained on the entry |
| `entitlements.<id>.trial_id` | Property presence is recorded. Its presence controls whether the parser reads `valid_until` |
| `entitlements.<id>.valid_until` | When both trial-related properties are present, converted from seconds to milliseconds and retained as an optional time |
| `entitlements.<id>.licences` | Optional array. Each element is converted to a string and retained on the entry; individual label-to-feature mappings remain unverified |

The traced entry parser does not read a per-entry `expiration` member. Its expiry-related entry read is `valid_until` under the trial-property condition above. This does not establish how other Equator2 paths handle an added per-entry field.

The verified and accepted response updates the entitlement state. Failed account or payload-expiry checks replace the stored entitlement set with an empty set in the examined acceptance function. The parser establishes the retained fields; product-specific feature gates and the later evaluation of trial expiry remain unverified. The repository's sanitized `com.roli.equator2` entitlement entry is issuer-side reference data, not proof of a particular executable feature gate.

## Preservation and verification

For already licensed accounts, preserve the account record, signed response body, and certificate and signature headers together. An unchanged Equator2 build still applies both expiry checks during validation. An archived response can therefore have a finite offline lifetime even when the local transport and cache files remain available. Continued acceptance past those expiry dates requires fresh data from an issuer trusted by the build.

Evidence anchors are `ev_465960b336d750c03c4cd24abdb945ae56cc997fd70c0cd3bdec07160616af71` for refresh and fallback, `ev_2137587f8f900029e61996616061dd42d852b424b5c2d9ca63f63bb67b66becb` for signature verification, `ev_d9d5100e4e22e171ee5802b2a7397a9b7bc622682dd04852facce9b54ab9c047` for root initialization, `ev_f92f7ac4f14b48fe33ba0b8f42d94c86cf4a995f0dbc3f83f9718762b7339ccc` for payload fields, and `ev_1203f3870f0c1b66b98b4fbbc67e935b5a5312435921dd67f90b28abe8816629` for account and payload-expiry acceptance. These are static observations, not runtime results.

Use a genuine, authorized fixture to verify the following cases on this build. These checks are pending runtime validation.

1. Capture the account request followed by the entitlement request. Confirm their exact request targets, pipe framing, and signed body bytes.
2. Replay the fixture through the pipe and separately through the shared files. Compare the live body with the reconstructed JSON text and record fallback behavior under upstream loss.
3. Isolate each rejection condition: non-200 status, missing signature header, modified body, account mismatch, expired certificate, and expired payload. Use already issued fixtures for expiry cases.
4. With a successful fixture, verify the relevant Equator2 features. Compare authorized account states and distinguish Connect entitlement acceptance from the separate local licence branch.
