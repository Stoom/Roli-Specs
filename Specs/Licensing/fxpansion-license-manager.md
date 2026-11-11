# FXpansion LicenseManager and instrument licence consumers

This specification describes the authorization path recovered from Windows x64 LicenseManager 2.1.0.14 and the Cypher2 and Strobe2 instrument DLLs reporting version 2.6.1.7. It follows product discovery, online and offline acquisition, signature verification, and the serial, machine, and expiry checks applied before a licence is accepted. These instrument builds also contain a separate ROLI account path, described below. The [Connect entitlement interface](roli-connect-entitlements.md) and [Dashboard consumer](roli-dashboard-entitlements.md) document the other ROLI licensing interface.

## Acquisition

### Installed components

The standalone executable for each instrument loads its adjacent DLL and calls its exported `StandAloneMain`. The substantial licensing code is in that DLL. Both examined DLLs also export `VSTPluginMain`; authorization in a running plug-in host was not tested.

| Component | Version | Architecture | SHA-256 |
| --- | --- | --- | --- |
| `LicenseManager.exe` | 2.1.0.14 | x64 | `8c6e6349901873563168d7b2dff8f80fcbde72d76e78ddc8774df11e09822c74` |
| `Cypher2.dll` | 2.6.1.7 | x64 | `5119ba8136fdbac7c7e9730dec3212186ea0266104b4eb644cc1eb8c02e354db` |
| `Strobe2.dll` | 2.6.1.7 | x64 | `9b3d417f019a57aeea6ebdb11f9ea7ef05379f718ccea1e73641a9a49fa3c535` |

LicenseManager is installed under `Program Files (x86)` but is an x64 executable. The examined `Program Files (x86)` Cypher2 and Strobe2 directories contain resources and uninstallers, without corresponding x86 instrument executables or DLLs. This specification therefore makes no claim about x86 instrument behavior.

### Product discovery and manager launch

Each instrument can register itself with the shared manager and launch the executable named by `HKCU\Software\fxpansion\licensemanager`, value `app_path`. A launch requested by the local licence failure path supplies `-product:"<module>"`. The explicit Unlock control also reaches the manager launch routine. This is process launch through the registered path; the traced exchange does not require a running manager service.

LicenseManager enumerates string values under `HKCU\Software\fxpansion\licensemanager\installedproducts`. Each value names a product module and supplies the product's registry path. The instrument registers the mapping `<module>` → `<company>/<module>`, with the associated metadata below. Slash-separated logical paths are translated to Windows registry keys beneath `Software`, with the final component used as the value name.

| Product metadata value | Observed use |
| --- | --- |
| `publickey` | External public verification key for the product's authorization file |
| `serialprefix` | Product serial prefix; the manager also recognizes `serialPrefix` |
| `serialnumber` | Stored product serial, read by both manager and instrument |
| `systempathbase` | Product system directory metadata |
| `userpathbase` | Product user directory; the manager constructs authorization paths here |
| `systemregistry` | Additional registry metadata read by the manager; its full downstream contract remains unresolved |

The launch routine writes the public key, serial prefix, and system and user directory metadata before starting the manager. The product name comes from the loaded module's filename without its extension. The instrument's local authorization path is `<user-base>/<company>/<module>/<module>.auth`; the normal Windows user base is the roaming Application Data folder. LicenseManager uses `<userpathbase>/<module>.auth` and `<userpathbase>/<module>.authrequest`. Preserve the registry mapping and actual directory values together rather than deriving them from a display name.

### HTTP exchange

The manager initializes its service base as `http://www.fxpansion.com/`. The following are compiled request paths, not confirmation that the service remains available or accepts these requests today. No live authorization or account request was submitted during this examination.

| Purpose | Method in the traced path | Request target or body |
| --- | --- | --- |
| Login | POST with an empty body | `curl/login.php?username=<encoded-username>&password=<password-md5>` |
| Retrieve serials | GET | `curl/getserials_xml.php?fxsid=<session>` |
| Authorize a product | POST | `curl/authorize.php`, body `fxsid=<session>&challenge=<encoded-request-file>` |

The username and complete challenge file are percent-encoded. The encoder leaves ASCII letters, digits, `_`, `.`, and `-` unchanged, and encodes other bytes as uppercase `%HH`; a space becomes `%20`. The login password is reduced to MD5 and rendered as 32 lowercase hexadecimal characters before being appended to the URL. The digest is therefore carried in the query even though this login call uses POST.

The login path treats a nonempty response that does not match its `ERROR0` failure case as the session value, subsequently named `fxsid`. The serial response reader scans quoted `productID` and `serial` attributes, matches products by serial prefix, validates candidate serials, and stores accepted serials. A complete XML schema was not established from that scanner.

For authorization, the manager first writes a product `.authrequest`, reads its text, and sends the encoded file as `challenge`. A successful transfer alone is insufficient. A nonempty response must begin with `BEGIN_FXSIGHEADER`; it is written to the product authorization path and then passed through the product's signature, serial, expiry, and hardware verification. The manager updates its accepted product state only after verification succeeds. An invalid response can therefore have reached disk without becoming an accepted licence.

The transfer helper follows redirects. Its examined configuration disables peer-certificate verification. The compiled base above is HTTP; a redirect or present-day deployment must be observed separately before making claims about the actual transport. This helper's successful transfer result does not itself establish HTTP status 200.

The manager also initializes `curl/userinfo.php?fxsid=` and `curl/deauthorize.php` routes. Their complete request and state-transition contracts were not established and are not specified here.

### Service error responses

The authorization error reader recognizes these response labels. Their presence in the client establishes its error interpretation, not current server behavior.

| Label | Client interpretation |
| --- | --- |
| `ERROR0` | Invalid session |
| `ERROR1` | Expired session |
| `ERROR2` | Invalid username or password |
| `ERROR3` | Invalid serial |
| `ERROR4` | Serial registration failed or serial already registered |
| `ERROR5` | Invalid product signature |
| `ERROR6` | Authorization limit reached |
| `ERROR9` | Required product not registered |
| `ERROR10` | Concurrent request limit reached |

### Offline request and import

The same request writer supports the offline workflow. Packaged manager instructions direct the user to export a request, transfer it to `http://www.fxpansion.com/authorize`, and import the returned authorization file. Website operation was not tested.

The request is a text record with the following framing. Angle-bracketed values below are descriptive placeholders, not literal file bytes. The writer uses a UTC `asctime`-shaped creation date, such as `Wed Nov 11 12:00:00 2026`, without its terminal newline.

```text
BEGIN_FXAUTH:[[CREATEDATE:(<creation-date>):VENDOR(<vendor>):MODULE(<module>):VERSION(<version>):SERIAL(<serial>)]]
<machine report beginning with Detecting>
END_FXAUTH
BEGIN_FXPUBKEY
<request public-key text>
END_FXPUBKEY
BEGIN_PAD
<padding text>
END_PAD
```

The manager supplies vendor `FXpansion`, the selected module and serial, and an empty version argument in the traced request call. The padding writer produces 32 rows, each containing four uppercase eight-digit hexadecimal values, followed by a newline. The request public-key block and the externally supplied product verification key are separate inputs. The authorization verifier uses the external product key; it does not adopt the request's public-key text as its trust anchor.

The manager's multi-product importer splits returned text at subsequent `BEGIN_FXSIGHEADER` markers. It reads `MODULE(...)` from each part, finds the corresponding installed product, and verifies the part using that product's key, stored serial, and hardware check. It skips products already considered authorized and reports products absent from its installed list. Accepted parts become the corresponding product `.auth` files. A bundle is therefore a sequence of signed product records, rather than a new shared entitlement JSON object.

## Signed authorization response

The authorization text places a signature header before the request-shaped content and a verification block after `END_PAD`.

```text
BEGIN_FXSIGHEADER:RECIPIENT(<recipient>):CREATEDATE(<creation-date>):USEBY(<use-by>):EXPIRES(<expiry>):END_FXSIGHEADER
<request-shaped content through END_PAD>
BEGIN_FXVERIFY
<hexadecimal RSA signature>
END_FXVERIFY
```

This illustrates the recovered writer's structure. It does not establish that every service response populates every header field, or that all displayed fields are enforced by every consumer.

| Field or block | Observed interpretation |
| --- | --- |
| `RECIPIENT(...)` | Required by the local verifier and retained as recipient text |
| `SERIAL(...)` | Required; compared case-insensitively with the supplied or stored product serial |
| `EXPIRES(...)` | Optional date checked against the current UTC calendar date |
| `CREATEDATE(...)` | Read by an optional instrument freshness check; the manager verifier examined here does not apply that check |
| `USEBY(...)` | Written in the header; enforcement was not established |
| `MODULE(...)` | Used by the multi-product importer to select an installed product |
| `Detecting` through `END_FXAUTH` | Machine report extracted for hardware comparison |
| `BEGIN_FXVERIFY` through `END_FXVERIFY` | Hexadecimal signature payload, with surrounding whitespace removed |

### Verification sequence

Verification takes the authorization text, the external product public key, the expected product serial, and a flag controlling machine comparison. The instrument verifier also accepts a creation-date freshness flag. The normal local-file paths enable machine comparison. Successful transfer, recognizable markers, and a matching serial are preliminary conditions; acceptance also requires a valid signature.

The manager path performs the following stages. These are checks on the recovered text format, rather than a strict schema that validates every displayed header field.

1. **Locate the machine report.** Find `Detecting` and the following `END_FXAUTH`. The bounded text between them supplies the stored machine report. Missing required boundaries cause rejection.
2. **Apply expiry when present.** Find `EXPIRES(...)` and read its calendar date. Reject a date earlier than the current UTC date. A missing field skips this check; an invalid month or missing delimiter can fail parsing. The instrument's optional creation-date freshness check is separate and is described under [Date checks](#date-checks).
3. **Bind the serial and read the recipient.** Require `SERIAL(...)` and compare its value case-insensitively with the expected serial. Require and retain `RECIPIENT(...)`. The examined local verifier does not compare that recipient with a currently logged-in account.
4. **Compare the machine report when enabled.** Generate the current report, strip whitespace from both reports, and count differing colon-separated segments using the comparison rules below. Reject more than five counted mismatches in the manager, or more than six in these instrument DLLs. This decision precedes the final signature check.
5. **Extract the signature and signed message.** Find the `BEGIN_FXVERIFY` and `END_FXVERIFY` boundaries and extract the hexadecimal signature text. Separately take the original authorization text from its start through the first `END_PAD`, including that marker. The parser's temporary field extraction does not replace those original message bytes with reserialized fields.
6. **Normalize, decode, and verify.** Remove whitespace from the signed message and signature text, hex-decode the external public key and signature, and verify the normalized message using RSA PKCS#1 v1.5 with SHA-1. The signature byte count must match the size expected for the selected RSA modulus. A matching signature completes this verifier's acceptance checks; a failed signature does not authorize the product.

The exact serialized public-key container should be confirmed with a genuine fixture before implementing a compatible decoder. There is no fixed entitlement-certificate record size in this format. The verifier obtains trust from the external product key passed by the caller. The request's `BEGIN_FXPUBKEY` block is part of the signed message, but does not select the key used to verify that signature.

#### Signed-message boundaries

The following table separates the message bytes from the signature representation. It assumes the ordinary record ordering illustrated above.

| Region | Included in the normalized signed message? |
| --- | --- |
| Signature header, including recipient and date fields | Yes |
| `BEGIN_FXAUTH`, request fields, and machine report | Yes |
| `END_FXAUTH` and the request public-key block | Yes |
| `BEGIN_PAD`, padding contents, and the first `END_PAD` marker | Yes |
| Newline immediately after that `END_PAD` | No; the message boundary is immediately after the marker |
| `BEGIN_FXVERIFY`, signature text, and `END_FXVERIFY` | No; these supply the separate signature input |

Whitespace normalization removes space, tab, carriage return, newline, vertical tab, and form feed everywhere inside the bounded message. It does not lowercase text, sort fields, remove punctuation, or rebuild the record from parsed values. Non-whitespace bytes retain their order and case. Preserve the complete original record and external key even though this verifier ignores those whitespace differences.

#### Normalization examples

These examples are illustrative text fragments, not complete authorization records or valid licence fixtures. In the first fragment, the line break and the space inside the recipient both disappear before cryptographic verification.

```text
RECIPIENT(Example User):
SERIAL(DEMO-0001)
```

The normalized bytes for that fragment are the ASCII text below, with no terminal newline:

```text
RECIPIENT(ExampleUser):SERIAL(DEMO-0001)
```

Replacing LF with CRLF or indenting the fragment with tabs produces the same normalized bytes. Changing `Example` to `example`, changing `0001` to `0002`, or moving the serial field before the recipient produces different bytes. A matching signature for the original message would therefore no longer verify after those non-whitespace edits. Whitespace-equivalent text still has to satisfy the earlier marker and field parsing checks; signature normalization alone does not establish acceptance.

The signature has a separate text-to-byte conversion. For example, the illustrative hexadecimal text `AA bb 01`, with any line breaks between its byte pairs, decodes to the three bytes `0xAA 0xBB 0x01` after whitespace removal. Hexadecimal letter case does not change those decoded bytes. Those three bytes are only a decoding example and do not constitute a valid RSA signature. Message text such as `MODULE(Cypher2)` is not hex-decoded; its non-whitespace characters are the message supplied to the signature verifier.

#### Acceptance examples

Each row isolates one condition and assumes the other required fields and checks succeed. These outcomes follow from the recovered checks and have not been exercised with issued licence fixtures.

| Example | Expected result at the relevant check |
| --- | --- |
| Expected serial `DEMO-0001`; signed record contains `demo-0001` | The serial comparison passes because it ignores case. The signature must still match the record's actual letter case. |
| A genuine record's serial is edited from `DEMO-0001` to `demo-0001`, keeping its signature | The serial comparison can pass, but the changed message bytes fail signature verification. |
| `EXPIRES(Wed Nov 11 00:00:00 2026)`; current UTC time is later on 11 November 2026 | The calendar-date expiry check passes, despite the displayed midnight time. |
| The same expiry field; current UTC date is 12 November 2026 | The expiry check rejects the record before final signature verification. |
| Six hardware-report mismatches, with a valid signature and matching serial | The manager rejects the hardware comparison; these instrument DLLs pass that particular check. |
| All parsed fields match, but the signature was made with a different key | RSA verification fails against the external product key. |

The first two cases distinguish field comparison from message authentication: a comparison can ignore case while the signature still authenticates the original case-sensitive bytes. The same separation applies to machine comparison and dates. Passing one of these checks never substitutes for passing the others.

### Embedded verification locations

The following are build-specific relative virtual addresses in the artifacts identified above. Add an RVA to the corresponding loaded module base to locate it in memory. These anchors identify the examined routines; they do not establish a runtime replacement interface.

| Artifact | Routine | RVA |
| --- | --- | --- |
| LicenseManager | Authorization parser and acceptance checks | `0xF45A0` |
| LicenseManager | RSA signature verifier | `0xF8560` |
| LicenseManager | Request writer | `0xF5300` |
| Cypher2 DLL | Local authorization load and status | `0xB831D0` |
| Cypher2 DLL | Authorization parser and acceptance checks | `0xB55B00` |
| Cypher2 DLL | Manager registration and launch | `0xB836D0` |
| Strobe2 DLL | Local authorization load and status | `0xB83170` |
| Strobe2 DLL | Authorization parser and acceptance checks | `0xB55AA0` |
| Strobe2 DLL | Manager registration and launch | `0xB83670` |

## Serial, machine, and expiry binding

The normal local licence path first reads the product's stored `serialnumber` and passes it to the product serial validator. It constructs the `.auth` path and invokes the authorization verifier with hardware checking enabled and the product's external public key. The verifier compares the record's serial case-insensitively with the expected serial. This is a separate check from RSA verification.

`RECIPIENT(...)` is parsed and retained. A comparison against the currently logged-in FXpansion or ROLI account was not found in this local authorization acceptance routine. The observed local binding is the product-selected key, serial, machine report, and applicable dates. This does not establish the service's account ownership rules during issuance.

### Serial number structure

The product initialization table selects a five-character family code and a five-character product code. The registered `serialprefix` combines those codes with a hyphen. The following illustrate the usual six-group, 35-character representation: six groups of five characters separated by five hyphens.

| Product | Family code | Product code | Non-working structural example |
| --- | --- | --- | --- |
| Cypher2 | `FXDCS` | `CYPR2` | `FXDCS-CYPR2-XXXXX-XXXXX-XXXXX-XXXXX` |
| Strobe2 | `FXDCS` | `STRB2` | `FXDCS-STRB2-XXXXX-XXXXX-XXXXX-XXXXX` |

Every `X` above is an illustrative placeholder. These are deliberately invalid serials: `X` is outside the accepted suffix alphabet. They are not issued values or activation credentials. The product codes are recovered constants, rather than abbreviations inferred from the displayed product names.

The normal stored values are `serialnumber` under `HKCU\Software\FXpansion\Cypher2` and `HKCU\Software\FXpansion\Strobe2`, respectively. The instrument reads that value before loading the matching `.auth` file. The authorization record's `SERIAL(...)` must agree with the stored serial even after the serial's own structural checks pass.

The instrument validator checks the family prefix and product code before calling a shared serial validator. It uppercases copies for the prefix comparison, checks for the product-code text, and then validates the serial's suffix and check characters. The shared validator expects 35 characters and processes the suffix beginning at zero-based character offset 18. In that suffix it recognizes uppercase `A`–`J`, uppercase `N`–`S`, and hyphens, translating the letters into hexadecimal characters for its checksum comparisons. A string can therefore have the illustrated length and product prefix and still fail validation. The examples show the normal grouping; they do not imply that the parser independently enforces every hyphen position as a schema.

| Instrument DLL | Product selection RVA | Product serial validator RVA | Shared serial validator RVA |
| --- | --- | --- | --- |
| Cypher2 | `0xAA38D0` | `0xB83CF0` | `0xB55350` |
| Strobe2 | `0xAA3870` | `0xB83C90` | `0xB552F0` |

These are separate from the signed authorization parsers identified above. Serial validity, agreement between the stored serial and `SERIAL(...)`, and RSA verification are three distinct requirements. A valid-looking serial alone supplies no authorization file or signature.

### Machine report comparison

The report begins with `Detecting host architecture:` and contains the following fields in order. These are the report components supplied to the comparison, including user and OS values as well as hardware. The source column records the Windows collection path recovered in the Cypher2 report generator where established. It does not imply that every manager helper uses an identical collection implementation.

| Order | Report label | Value or source |
| --- | --- | --- |
| 1 | `HostName` | Computer name from `GetComputerNameW` |
| 2 | `UserName` | Windows user name from `GetUserNameW` |
| 3 | `UserHome` | Empty string in the examined authorization report paths |
| 4 | `Byte order` | `Little-endian` or `Big-endian`, selected from the library's byte-order flag |
| 5 | `Physical Memory` | Total physical memory from `GlobalMemoryStatusEx`, formatted with B, kB, MB, GB, or TB units |
| 6 | `CPU speed` | MHz text; the instrument helper reads `HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0`, value `~MHz`, and returns zero if the key cannot be opened |
| 7 | `Number of CPUs` | `GetSystemInfo.dwNumberOfProcessors` |
| 8 | `Processor name` | CPU brand text from extended CPUID leaves `0x80000002` through `0x80000004`, with leading spaces trimmed |
| 9 | `Processor level` | `GetSystemInfo.wProcessorLevel`, formatted in hexadecimal |
| 10 | `Processor revision` | `GetSystemInfo.wProcessorRevision`, formatted in hexadecimal |
| 11 | `FPU` | Library CPU-feature flag rendered as text |
| 12 | `MMX` | Library CPU-feature flag rendered as text |
| 13 | `SSE` | Library CPU-feature flag rendered as text |
| 14 | `SSE2` | Library CPU-feature flag rendered as text |
| 15 | `SSE3` | Library CPU-feature flag rendered as text |
| 16 | `SSE3_Supp` | Separate library support flag rendered as text; this is the report's literal label |
| 17 | `Hyperthreading` | Library CPU-feature flag rendered as text |
| 18 | `Operating system` | Manager authorization mode supplies `Win32`. The instrument generator instead obtains Windows product-name text through its OS-name helper, including a registry lookup of `Microsoft/Windows NT/CurrentVersion/ProductName` and fallback names |
| 19 | `OS major version` | Major version reported by `GetVersionExA` in the instrument generator |
| 20 | `minor version` | Minor version reported by `GetVersionExA` |
| 21 | `build` | Build number reported by `GetVersionExA` |

The manager report writer has the same ordered labels. Its examined mode leaves `UserHome` empty and forces the `Win32` OS label; the instrument's OS-name helper is a material difference between the generated reports. The Windows APIs' returned values, including any compatibility-dependent OS version, become the report text. The examined report writers do not add a disk serial, volume ID, MAC address, motherboard serial, or TPM identifier. Preserve the report as text; the comparison is not a fixed binary hardware identifier.

For comparison, the client strips whitespace, walks colon-separated report segments, and compares corresponding segments case-insensitively up to the shorter segment's length. A differing segment increments a mismatch counter. If one report ends before the other, that termination difference adds a mismatch. This is a tolerant textual comparison, and does not require every segment to have identical length.

| Consumer | Report generation RVA | Comparison and rejection location | Tolerance |
| --- | --- | --- | --- |
| LicenseManager 2.1.0.14 | `0xC7B20` | Inline comparison within authorization parser `0xF45A0` | Zero through five counted mismatches pass this check; six or more fail |
| Cypher2 DLL 2.6.1.7 | `0xB4FAF0` | Segment comparator `0xB55230`; threshold applied in authorization parser `0xB55B00` | Zero through six counted mismatches pass this check; seven or more fail |
| Strobe2 DLL 2.6.1.7 | `0xB4FA90` | Segment comparator `0xB551D0`; threshold applied in authorization parser `0xB55AA0` | Zero through six counted mismatches pass this check; seven or more fail |

The mismatch budget is shared across the report. There are no recovered per-component weights or separate allowances such as a percentage of RAM or a number of MHz. A changed formatted value normally consumes one segment mismatch. A single physical CPU replacement can alter several report fields and consume several mismatches. A computer rename and a Windows user rename can also contribute independently. Differences caused by the manager and instrument's report formatting use the same comparison budget.

For example, otherwise equal report values `HostName: STUDIO-A` and `HostName: studio-a` compare equally after case-insensitive normalization. A changed name `STUDIO-B` contributes a mismatch. Spaces and line breaks do not contribute because they are removed first. The shorter-segment comparison also means matching prefixes with unequal lengths are not automatically rejected. These are segment rules, rather than guarantees that a particular hardware upgrade will pass. Serial, expiry, and signature checks still apply after a report falls within the mismatch budget.

The manager and instruments therefore do not have identical acceptance thresholds or identical report generation. An implementation should keep these build-specific rules separate. The normal local-file consumers enable the machine check; a low-level verifier call with that flag disabled skips this comparison, without bypassing its other checks.

### Date checks

When `EXPIRES(...)` exists, the verifier extracts month, day, and year from its `asctime`-shaped value and compares them with the current UTC date. A record remains within this check throughout its stated expiry date; the time-of-day portion does not determine the cutoff. A missing expiry field bypasses this particular date check. Malformed date delimiters or an unrecognized month can cause rejection.

The instrument verifier also has an optional creation-date freshness mode. When enabled, it requires `CREATEDATE(...)`, converts the date and current time through the recovered time-conversion path, and rejects a negative age or an age exceeding 90 days. The ordinary initialization calls traced in both instruments pass this mode as disabled. Other callers can forward a flag, so a universal 90-day lifetime for all `.auth` files is not established. Time-zone and daylight-saving boundary behavior needs runtime validation because this conversion combines UTC calendar fields with local-time conversion functions.

### Instrument states and manager absence

An accepted local file produces status 1000 and can be retained in memory. A subsequent check allowed to reuse accepted state can return that status without reopening the file. Neither this accepted-state path nor the normal local file verifier requires LicenseManager to remain running or contacts the FXpansion authorization service.

| Status | Observed meaning |
| --- | --- |
| 1000 | Local authorization accepted |
| 1001 | No authorization file |
| 1002 | Existing authorization file failed acceptance; displayed as corrupt |
| 1003 | Missing serial in the traced load path |
| 1004 | Invalid serial message recognized by the status formatter; a distinct assignment in this load routine was not established |
| 1005 | Build-expired message recognized by the status formatter; its trigger remains unresolved |
| 1006 | Requested manager launch failed |
| 1007 | Evaluation period ended |
| 1011 | Active evaluation state |
| 1012 | ROLI Player licence state |
| 1013 | ROLI full licence state |

On local authorization failure, a caller can request manager launch or present the authorization panel. If the registered manager cannot be launched, the failure can become status 1006. The evaluated code also has an in-process evaluation timer; the acceptance routine compares it with a constant of 1,830 seconds. Packaged UI calls the evaluation 30 minutes. Saving is explicitly blocked by an examined GUI path while the evaluation state is active. Exact audible restrictions and timing in a running host remain unverified.

## Separate ROLI account acquisition

Both instrument DLLs contain their own ROLI account login and licence lookup. This route is separate from the manager's FXpansion session and signed `.auth` file. The traced callbacks make direct API requests and write a product-local login cache; they do not use the Connect named-pipe exchange described for Dashboard.

| Purpose | Compiled endpoint or parameter |
| --- | --- |
| Authenticate | `https://api.roli.com/api/v1/authenticate`, with JSON `email` and `password` members |
| Licence lookup | `https://api.roli.com/api/v1/user/licences?search_internal_id=com.roli.%s&product_version=%d` |
| Session credential | `X-Access-Token`, populated from the authentication response's `token` |

The lookup derives the lowercase product name and numeric final version digit for the query. Its response scanner recognizes `strobe-player`, `cypher-player`, `strobe-full`, and `cypher-full` values associated with `licence_type`. A full result takes precedence over a Player result. The callback sets state 1012 for Player and 1013 for full; a successful login without a recognized licence reports that no product licence was found. These are recovered client rules, without confirmation of current API availability or account responses.

### Local login cache

The callback writes `com.roli.logincookie.txt` beneath the product's `Settings` directory in the current user's Windows Documents folder. This is separate from the roaming Application Data directory used for the normal `.auth` file.

| Product | Cache path |
| --- | --- |
| Cypher2 | `<Windows Documents>\FXpansion\Cypher2\Settings\com.roli.logincookie.txt` |
| Strobe2 | `<Windows Documents>\FXpansion\Strobe2\Settings\com.roli.logincookie.txt` |

`<Windows Documents>` is the folder returned by `SHGetFolderPathW` with `CSIDL_PERSONAL` (`5`). It can be redirected, so a literal `%USERPROFILE%\Documents` path is only a common default. The path accessor appends the company, product, and `Settings` components. If the Windows folder lookup fails, its helper attempts a `My Documents` fallback before reporting failure. The product-directory accessors are at DLL RVA `0xA59480` for Cypher2 and `0xA59470` for Strobe2; the underlying Documents lookup is at `0xB50410` and `0xB503B0`, respectively.

The file contains the following text in order:

| Part | Representation |
| --- | --- |
| Timestamp | Decimal Unix seconds, obtained by dividing the client's millisecond clock by 1,000 |
| Separator | Two LF bytes (`\n\n`), producing a blank line after the timestamp |
| Licence marker | `!PLAYER\n` or `!FULL\n` |
| Checksum | 32 lowercase hexadecimal characters appended directly after the marker's LF |

The writer does not append another newline after the checksum. It computes that checksum over the entire preceding prefix: the timestamp digits, both LF bytes, the marker, and the marker's terminal LF. The checksum routine uses four 32-bit accumulators and formats their results as hexadecimal text. It is separate from the RSA authorization signature and from the signed entitlement response used by Dashboard. This file's writer supplies no email address, account ID, access token, serial number, or hardware report in the recovered layout.

The following are deliberately non-working examples of the file's appearance. Timestamp `1` is in January 1970 and is outside the cache's acceptance window; the zero checksum is a placeholder and was not calculated. These examples are not account data or licence fixtures. Each example ends at the last checksum digit, without a terminal newline.

```text
1

!PLAYER
00000000000000000000000000000000
```

```text
1

!FULL
00000000000000000000000000000000
```

The examined startup cache readers require the unsigned age calculation to be less than `0x127500` seconds: 1,209,600 seconds, or 14 days. This also rejects future timestamps through the unsigned comparison. The full-cache branch recomputes and compares the text checksum before adopting full state. The examined initial Player fallback does not perform that same full-cache checksum comparison. These observations describe the shipped reader; they do not establish a server-issued cryptographic licence in this file.

For a cache timestamp `t`, the age check uses the integer current Unix seconds minus `t`. An age of 1,209,599 seconds is within this particular check; 1,209,600 seconds is outside it. The full-cache branch then splits after `!FULL\n`, recomputes the checksum of the retained prefix, and compares it with the remaining text. Passing the age check alone is insufficient for full-state adoption. The observed file format has no independent signed certificate or machine-binding field.

The in-memory Player or full state is returned before the ordinary `.auth` checks. A usable local account cache can therefore supply an alternative when the manager is absent, subject to the cache reader and age checks. The examined logout action removes this cache and changes the authorization state. No login, logout, cache change, or licence issuance was performed during this investigation.

## Preservation and verification

For an existing authorized installation, preserve each product's `.auth` record, stored serial, product registration and directory metadata, and external verification key together. Preserve genuine `.authrequest` and returned multi-product records when available. The machine comparison and optional dates still apply when those files are read elsewhere. A copied authorization file alone does not establish acceptance on another machine. The ROLI login cache has its own short lifetime and is a separate preservation item.

Evidence anchors are `ev_d8dff77467463f9a681e3031c88052b09f6cd0a0806fc623c18486020440b392` for online authorization, `ev_ca07226fee5edfa86f5296df72d41ea795e1b60b7a2b021fe770edc56dee843c` for request framing, `ev_a177741a47f1aea2885e2b3c1cdfa9a7ff5ceea28d9cf1b4421c9035138f6378` for manager acceptance, and `ev_215a8d2b52968ce4253ae4d45bd1d61e283facfa29a5a41d877f6222bba452f8` for its signature verifier. The instrument locations above anchor the corresponding local load, verification, and launch behavior in the separately identified DLL builds.

This examination used static program and installed-resource evidence. It did not validate current remote services, genuine issued authorization records, successful runtime acceptance, a running plug-in host, or every manager command. The exact public-key serialization, complete serial-number arithmetic, remembered-login storage, deauthorization workflow, and detailed feature restrictions remain unresolved.

Use a genuine, authorized fixture to verify the following cases on these builds. All remain pending runtime validation.

1. Confirm the actual product registry values and directories, then load an existing valid authorization with LicenseManager closed and network access unavailable. Compare standalone and plug-in behavior.
2. Capture the normal request export and authorized response without changing account ownership. Confirm framing, key serialization, hexadecimal decoding, and the precise whitespace-normalized signed message.
3. Compare a single-product import with a genuine multi-product response. Check installed-product selection, already-authorized products, invalid response persistence, and per-product success reporting.
4. Isolate serial mismatch, signature failure, issued expiry, and naturally occurring hardware-report differences. Confirm the manager and instrument threshold difference using authorized records in a controlled environment.
5. Compare the direct ROLI login path with startup from its existing cache and with a naturally expired cache. Record the directory used, cache age boundary, Player/full feature behavior, and whether a fresh login is requested.
