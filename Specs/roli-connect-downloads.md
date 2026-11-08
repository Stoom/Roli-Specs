# ROLI Connect product downloads

This inventory covers build paths, catalog checksums, and artifact delivery. The [Connect API specification](roli-connect-entitlements.md#get-build-download) documents the build lookup request and response.

## Live product download paths

The signed-in Connect proxy returned these builds on November 8, 2026 from `GET /api/v1/products/software`, `GET /api/v1/user/products`, and `GET /api/v1/products/trials`. The inventory includes builds under `included_additional_content` and merges duplicate rows across lists. It contains 25 API lookup paths and 24 distinct storage keys. The two Dashboard Windows entries share one storage key.

Each lookup path uses the product `public_id`, build `version_number`, and nested `build.platform_code`. Storage keys preserve the exact `build.s3_path`, including spaces and capitalization. The Segment column shows the sampled string in `segments`. An empty string corresponds to `[""]`.

| API download lookup path | Storage key | Checksum | Segment |
| --- | --- | --- | --- |
| [`/api/v1/product/com.fxpansion.cypher2.stubloader/version/2.6.1/build/osx/download`](https://api.roli.com/api/v1/product/com.fxpansion.cypher2.stubloader/version/2.6.1/build/osx/download) | `software/Cypher2/2.6.1.7/Cypher2_v2.6.1.7.dmg` | Empty | `""` |
| [`/api/v1/product/com.fxpansion.cypher2.stubloader/version/2.6.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.fxpansion.cypher2.stubloader/version/2.6.1/build/windows64/download) | `software/Cypher2/2.6.1.7/Cypher2_v2.6.1.7.exe` | Empty | `""` |
| [`/api/v1/product/com.fxpansion.strobe2.stubloader/version/2.6.1/build/osx/download`](https://api.roli.com/api/v1/product/com.fxpansion.strobe2.stubloader/version/2.6.1/build/osx/download) | `software/Strobe2/2.6.1.7/Strobe2_v2.6.1.7.dmg` | Empty | `""` |
| [`/api/v1/product/com.fxpansion.strobe2.stubloader/version/2.6.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.fxpansion.strobe2.stubloader/version/2.6.1/build/windows64/download) | `software/Strobe2/2.6.1.7/Strobe2_v2.6.1.7.exe` | Empty | `""` |
| [`/api/v1/product/com.roli.airwavecontrol/version/1.4.1/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.airwavecontrol/version/1.4.1/build/osx/download) | `software/ROLI Airwave Control/1.4.1/osx/airwavecontrol-1.4.1.rpkg` | `sha256:4186f9974df89d6055c8545b2feb53178b6b8dd9a37cbb6c8f35ae7c25a4b698` | `"rac141"` |
| [`/api/v1/product/com.roli.airwavecontrol/version/1.4.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.airwavecontrol/version/1.4.1/build/windows64/download) | `software/ROLI Airwave Control/1.4.1/windows64/airwavecontrol-1.4.1.rpkg` | `sha256:3e0a9cac4c6f95a95e65be061c2263a0c1850caf150118e8410308d43ff1bcab` | `"rac141"` |
| [`/api/v1/product/com.roli.airwaveplayer/version/1.4.1/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.airwaveplayer/version/1.4.1/build/osx/download) | `software/ROLI Airwave Player/1.4.1/osx/airwaveplayer-1.4.1.rpkg` | `sha256:1690bd347b3bf4d643b9198a8dac349cc8570a70cece4869fa3cf6f1f770e9d1` | `""` |
| [`/api/v1/product/com.roli.airwaveplayer/version/1.4.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.airwaveplayer/version/1.4.1/build/windows64/download) | `software/ROLI Airwave Player/1.4.1/windows64/airwaveplayer-1.4.1.rpkg` | `sha256:d4fce03cb1d02036faf76f5128146cd1a7ea67e979ed18b0d6a634e02eb1d32b` | `""` |
| [`/api/v1/product/com.roli.airwaveplayer.airwaveplayercontent/version/1.1.0/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.airwaveplayer.airwaveplayercontent/version/1.1.0/build/osx/download) | `software/ROLI Airwave Player Content/1.1.0/osx/airwaveplayercontent-1.1.0.rpkg` | `sha256:7ca9e3a3faf53118634c4c583fb2f540a5faaf5132d1043ba3c5c9aeb91a7ae0` | `"rapcontent110"` |
| [`/api/v1/product/com.roli.airwaveplayer.airwaveplayercontent/version/1.1.0/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.airwaveplayer.airwaveplayercontent/version/1.1.0/build/windows64/download) | `software/ROLI Airwave Player Content/1.1.0/windows64/airwaveplayercontent-1.1.0.rpkg` | `sha256:ed3167834bca221a17aeaea313ccd9249f490ea48d7584a63adff15ee9561e08` | `"rapcontent110"` |
| [`/api/v1/product/com.roli.equator2/version/2.5.2/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.equator2/version/2.5.2/build/osx/download) | `software/Equator2/2.5.2/osx/equator2-2.5.2.rpkg` | `sha256:57f3eb8a38c6211e6ed49eb62e3231a5b2df58fd6d4f6ce6918712c5c474331d` | `"equator252"` |
| [`/api/v1/product/com.roli.equator2/version/2.5.2/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.equator2/version/2.5.2/build/windows64/download) | `software/Equator2/2.5.2/windows64/equator2-2.5.2.rpkg` | `sha256:9af698de46de92f88c2d21eefae5e9a3a71732359043e53cc95379a339ec7b8a` | `"equator252"` |
| [`/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/osx/download) | `software/Equator Legacy Content/1.1.0/osx/Equator Legacy Content-1.1.0.rpkg` | `sha256:48001cc3f77b8023cb79e3e953ad171c9ea17693d7348affeb8b463b6a1486ca` | `""` |
| [`/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/windows64/download) | `software/Equator Legacy Content/1.1.0/windows64/Equator Legacy Content-1.1.0.rpkg` | `sha256:884ca5b858ec2666b055589b5899779b3ad37159d256a0df1ab67b745a72a700` | `""` |
| [`/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/osx/download) | `software/Equator2 Factory Content/1.0.0/osx/Equator2 Factory Content-1.0.0.rpkg` | `sha256:4f9fb67601fd87279d874796ded560589c4f85e0d90721bb9c35a68aaae376c7` | `""` |
| [`/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/windows64/download) | `software/Equator2 Factory Content/1.0.0/windows64/Equator2 Factory Content-1.0.0.rpkg` | `sha256:a7871719e15fc0cd45d770c4b316d57ebe7cb43e77e85aaf7556f1d0c8b4ac58` | `""` |
| [`/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/osx/download) | `software/ROLI Hardware Driver/0.7.1/osx/roliblocksserver-0.7.1.rpkg` | `sha256:7d8fd393c216d97543d26d5f28906f5ee031cf313e02a6caaf95092ed937257d` | `""` |
| [`/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/windows64/download) | `software/ROLI Hardware Driver/0.7.1/windows64/roliblocksserver-0.7.1.rpkg` | `sha256:a103798a1d11dd0cfbe1e64a196d36e38b2e7975f07da752ce18d6269e1ad59b` | `""` |
| [`/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/osx/download) | `software/ROLI Dashboard/4.7.2/osx/DashboardInstallerOSX.mpkg.zip` | Empty | `""` |
| [`/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/windows32/download`](https://api.roli.com/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/windows32/download) | `software/ROLI Dashboard/4.7.2/win64/DashboardInstallerWIN.exe.zip` | Empty | `""` |
| [`/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.rolidashboard/version/4.7.2/build/windows64/download) | `software/ROLI Dashboard/4.7.2/win64/DashboardInstallerWIN.exe.zip` | Empty | `""` |
| [`/api/v1/product/com.roli.studiodrums/version/1.4.1/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.studiodrums/version/1.4.1/build/osx/download) | `software/ROLI Studio Drums/1.4.1/osx/studiodrums-1.4.1.rpkg` | `sha256:9590ddb1fb66e426d9c370bea0025e5596acf74d96b5fa085a29848f4c5d59c2` | `""` |
| [`/api/v1/product/com.roli.studiodrums/version/1.4.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.studiodrums/version/1.4.1/build/windows64/download) | `software/ROLI Studio Drums/1.4.1/windows64/studiodrums-1.4.1.rpkg` | `sha256:42daefc9a0cd3ac5e514fa36112f9be8955ba2844eb7f0344f94fc243063fe24` | `""` |
| [`/api/v1/product/com.roli.studioplayer/version/1.4.1/build/osx/download`](https://api.roli.com/api/v1/product/com.roli.studioplayer/version/1.4.1/build/osx/download) | `software/ROLI Studio Player/1.4.1/osx/studioplayer-1.4.1.rpkg` | `sha256:70108a12be328a9c80fb370ce45c3828568930984a0ea1d44bc799b9870915ce` | `""` |
| [`/api/v1/product/com.roli.studioplayer/version/1.4.1/build/windows64/download`](https://api.roli.com/api/v1/product/com.roli.studioplayer/version/1.4.1/build/windows64/download) | `software/ROLI Studio Player/1.4.1/windows64/studioplayer-1.4.1.rpkg` | `sha256:1ec249dad69e3f638b44a60bedc5e07cb1f906a255921b66936ca42ae001ebde` | `""` |

The live `build.checksum` field supplied a SHA-256 value for 18 lookup rows and an empty string for the other 7. The table records the supplied values. Verifying them against downloaded files is outside this capture. The lookup links point to the API, which may require an authenticated request.

### Artifact access

The build lookup returned signed HTTPS URLs on `builds.roli.com` for the Windows x64 builds of Studio Player, Dashboard, and Equator2 Factory Content. DNS resolves that host through CloudFront. Each signed URL returned HTTP 206 to a one-byte range request. The same host and object path returned HTTP 403 when the query string was removed.

The catalog’s `build.s3_path` identifies the storage key. The build lookup supplies the signed delivery URL. The tested URLs establish access through the signed CloudFront path. The underlying S3 bucket name and its access policy remain unverified.

### Deduplicated software catalog downloads

This list uses only `GET /api/v1/products/software` and its nested `included_additional_content` entries. Deduplication uses the literal storage key. The response contained 10 distinct artifact keys across 5 product IDs.

| Product ID | Version | Platform | Location in response | Artifact lookup |
| --- | --- | --- | --- | --- |
| `com.roli.equator2.eq1legacycontent` | `1.1.0` | `osx` | Additional content | [`Equator Legacy Content-1.1.0.rpkg`](https://api.roli.com/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/osx/download) |
| `com.roli.equator2.eq1legacycontent` | `1.1.0` | `windows64` | Additional content | [`Equator Legacy Content-1.1.0.rpkg`](https://api.roli.com/api/v1/product/com.roli.equator2.eq1legacycontent/version/1.1.0/build/windows64/download) |
| `com.roli.equator2.eq2factorycontent` | `1.0.0` | `osx` | Additional content | [`Equator2 Factory Content-1.0.0.rpkg`](https://api.roli.com/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/osx/download) |
| `com.roli.equator2.eq2factorycontent` | `1.0.0` | `windows64` | Additional content | [`Equator2 Factory Content-1.0.0.rpkg`](https://api.roli.com/api/v1/product/com.roli.equator2.eq2factorycontent/version/1.0.0/build/windows64/download) |
| `com.roli.roliblocksserver` | `0.7.1` | `osx` | Top level | [`roliblocksserver-0.7.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/osx/download) |
| `com.roli.roliblocksserver` | `0.7.1` | `windows64` | Top level | [`roliblocksserver-0.7.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.roliblocksserver/version/0.7.1/build/windows64/download) |
| `com.roli.studiodrums` | `1.4.1` | `osx` | Top level | [`studiodrums-1.4.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.studiodrums/version/1.4.1/build/osx/download) |
| `com.roli.studiodrums` | `1.4.1` | `windows64` | Top level | [`studiodrums-1.4.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.studiodrums/version/1.4.1/build/windows64/download) |
| `com.roli.studioplayer` | `1.4.1` | `osx` | Top level | [`studioplayer-1.4.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.studioplayer/version/1.4.1/build/osx/download) |
| `com.roli.studioplayer` | `1.4.1` | `windows64` | Top level | [`studioplayer-1.4.1.rpkg`](https://api.roli.com/api/v1/product/com.roli.studioplayer/version/1.4.1/build/windows64/download) |

### Links listed alongside builds

| Product ID | Link type | Destination |
| --- | --- | --- |
| `com.roli.abletonlive11lite` | software | [Ableton Live Lite product page](https://www.ableton.com/en/products/live-lite/) |
| `com.roli.equator2` | manual | [Equator2 online manual](https://support.roli.com/support/solutions/articles/36000379550-equator2-online-manual) |

The `links_and_downloads` entries point to a product page and a manual. They are separate from the build URL lookup.
