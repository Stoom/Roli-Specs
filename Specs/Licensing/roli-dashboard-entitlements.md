# ROLI Dashboard entitlement consumer

This specification describes the entitlement path recovered from the Windows x86 build of ROLI Dashboard 4.7.2. It follows acquisition, signature verification, and the account and expiry checks that run before Dashboard adopts the entitlement data. The [Connect entitlement interface](roli-connect-entitlements.md) describes the other side of the local transport and the producer of the shared files.

## Acquisition

Dashboard's Connect client builds account and entitlement requests using the trailing-slash fragments `/user/` and `/user/entitlements/`. It builds a logical request URI under `roli://connect/api/v` and supplies a Windows pipe name constructed from `roli_connect_ipc_` and the username returned by `GetUserNameW`. On the examined refresh path, Dashboard first loads the account response and requests entitlements once the account data is accepted. The corresponding Connect HTTP request targets are `/api/v1/user/` and `/api/v1/user/entitlements/`. This association follows from the Dashboard route construction and the matching Connect configuration. The raw pipe exchange and username edge cases have yet to be observed.

Dashboard also has a cache-only load path and can fall back to cached account and entitlement data after a failed live entitlement acceptance on the examined refresh path. Both cache readers request the Windows roaming application data directory and look under `ROLI/Shared`. The filename starts with the API prefix and route, with each slash replaced by `%2F`, and ends with `.json`.

| Purpose | File under `%APPDATA%/ROLI/Shared` |
| --- | --- |
| Account | `%2Fapi%2Fv1%2Fuser%2F.json` |
| Entitlements | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |

The account cache reader extracts the parsed `body` for the account state. The entitlement cache reader extracts the `headers` object, converts its property values to header strings, serializes the parsed `body` back to JSON text, and constructs a response with status 200. That response enters the same verifier as a live response. The signature therefore has to verify over the text Dashboard reconstructs. Property order, number formatting, escaping, and whitespace can matter. The exact serializer output has yet to be compared against a genuine signed fixture.

## Signed entitlement response

The verifier first requires status 200. It reads the following headers as Base64 and obtains the response body as text. For signature verification it passes the body's UTF-8 bytes through the first NUL, excluding the terminator. It parses the verified body as JSON afterward. Preserve the exact live response text and all three headers when archiving a genuine response.

| Header | Decoded record |
| --- | --- |
| `x-message-signature` | 74-byte detached signature record for the entitlement body |
| `x-signer-certificate` | 52-byte signer certificate |
| `x-signer-certificate-signature` | 74-byte detached signature record for the signer certificate |

Offsets below are zero-based byte offsets in decoded records. The key and signature layouts are consistent with Signify-style Ed25519 records. The `Ed` key tag, key and signature sizes, and the elliptic-curve and SHA-512 verification path identify the algorithm statically. An independent Ed25519 verifier also validated both signatures from a live response.

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

| File offset | Reference |
| --- | --- |
| `0x545470` | The initializer reads this copy, decodes it, and stores the root record consumed by the entitlement certificate verifier. |
| `0x550ED0` | Exact duplicate. Its use remains unverified. |
| `0x657964` | Exact duplicate. Its use remains unverified. |
| `0x65F830` | Exact duplicate. Its use remains unverified. |
| `0x6B7318` | Exact duplicate. Its use remains unverified. |

The initializer reads the referenced string at the instruction starting at file offset `0x53DB`. A whole-file search found no exact copy of the decoded 42-byte public-key record. Removing the referenced string would leave the existing certificate check without its expected trust anchor. Replacing the anchor would change which signer certificates the verifier can accept. The offsets and reference apply to the executable hash above.

### Verification sequence

The verifier reconstructs the certificate from its parsed fields in wire order, then Base64-encodes that record. It verifies the resulting ASCII Base64 text against the embedded trust anchor using `x-signer-certificate-signature`, then rejects a certificate whose expiry is earlier than the current Unix time in whole seconds. It verifies the entitlement body with the certified public key using `x-message-signature`. Each signature check compares the signature's eight-byte key ID with the selected public key's ID before verifying the 64 signature bytes. The certificate parser recognizes the `C1` and `Ed` tags. The signature reader retains its tag, but a separate signature-tag check was not established.

In a live response fetched through Connect on November 8, 2026, the certificate signature verified over both the original header text and the canonical Base64 re-encoding. It failed over the 52 decoded bytes. The body signature verified over the live response bytes and over the parsed JSON serialized with two-space indentation and no terminal newline. It failed over compact JSON. Connect's shared file preserved the parsed body and the three signature headers. The independent verifier tested those inputs in memory. Dashboard's own offline execution remains unverified.

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
