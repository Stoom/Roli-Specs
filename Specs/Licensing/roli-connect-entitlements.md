# ROLI Connect entitlement interface

This specification describes the Windows ROLI Connect 1.6.4 interface relevant to preserving access to already licensed software. It covers the local HTTP proxy, the shared response files, the renderer's direct API requests, and where validation occurs. The [Dashboard entitlement consumer](roli-dashboard-entitlements.md) specifies the signed entitlement format and acceptance checks for that app.

The Roli Connect ASAR file is located at `C:\Program Files (x86)\Roli Connect\RoLI Connect.asar` is identifiable with the SHA-256 hash value `24ccdf8fe553d65bb1c87a6a3dde18ecbfa8c2404684bb7a373182ce835cd62a`.

## Local HTTP interface

Connect starts the proxy from its Electron main process. On Windows it exposes HTTP over a named pipe and over loopback TCP. Both listeners use the same proxy and cache configuration.

| Transport | Address |
| --- | --- |
| Windows named pipe | `\\.\pipe\roli_connect_ipc_<suffix>` |
| TCP | `http://127.0.0.1:25438` |

For the pipe suffix, Connect takes the nonempty `USERNAME` environment value or falls back to the process working directory. It removes the characters `" # @ , ; : < > * ^ | ? /` from that string, where the spaces in this list separate individual characters. It otherwise keeps the suffix as supplied. The observed configuration also contains Unix socket branches. This document specifies the examined Windows deployment.

The entitlement-related proxy paths are the following four exact request targets. A trailing slash identifies a separate cache entry. A query string changes the request target and prevents an exact match for shared-file publication.

| Method | Request target | Role |
| --- | --- | --- |
| GET | `/api/v1/user/` | Current user |
| GET | `/api/v1/user` | Current user |
| GET | `/api/v1/user/entitlements/` | Current user's entitlements |
| GET | `/api/v1/user/entitlements` | Current user's entitlements |

The listener is a general proxy to `https://api.roli.com`. A client sends an HTTP request with the full `/api/v1/…` target over the named pipe or loopback TCP. The proxy forwards the method, path, query, and request body to the upstream host. The table describes the shared-file publication allowlist. Standalone app binaries also contain product route literals whose licensing relevance is unresolved.

### Authenticated requests

Send a GET with an empty body for any of the four account or entitlement targets. The proxy uses a nonempty caller-supplied `X-Access-Token` first and falls back to Connect’s current session token. With Connect signed in, a caller can omit both `X-Access-Token` and `Cookie`. Both slash variants return HTTP 200 over either transport for a successful authenticated request.

| Request targets | HTTP 200 response body |
| --- | --- |
| `/api/v1/user`, `/api/v1/user/` | JSON account object. See the [account response model](#get-user). |
| `/api/v1/user/entitlements`, `/api/v1/user/entitlements/` | Signed JSON with an account `uid`, top-level `expiration`, and entitlement entries. See the [entitlement response model](#get-user-entitlements). |

| Response header | Account response | Entitlement response |
| --- | --- | --- |
| `Content-Type` | `application/json; charset=utf-8` | `application/json; charset=utf-8` |
| `Cache-Control` | `private, max-age=0, max-stale=2419200` | `private, max-age=0, max-stale=2419200` |
| `X-API-Proxy-Cache-Hit` | `false` | `false` |
| `X-Auth-Token` | Present | Present |
| `Set-Cookie` | Present | Present |
| `X-Message-Signature` | Absent | 74 bytes decoded |
| `X-Signer-Certificate` | Absent | 52 bytes decoded |
| `X-Signer-Certificate-Signature` | Absent | 74 bytes decoded |

Signed-in loopback GETs for account products and soundpacks also returned HTTP 200.

Connect forwards upstream status and end-to-end headers, supplies `ROLI_CONNECT/1.6.4` when the request lacks a user agent, sets the upstream host, and removes `If-None-Match`. It follows redirects and configures request and upstream timeouts of 10 seconds. For HTTPS targets, this proxy sets `rejectUnauthorized: false`. For gzip responses, it decompresses the body and adjusts the outgoing encoding and length.

### Unauthenticated requests

If neither the request nor Connect supplies a token, the proxy returns HTTP 511 before forwarding. The response omits `Content-Type` and `X-API-Proxy-Cache-Hit` and carries this JSON body.

```json
{
  "error": {
    "name": "<error name>",
    "message": "Unauthorized - refused by API proxy"
  }
}
```

### Private proxy cache

The private cache lives under `%APPDATA%/ROLI/ROLI Connect/API Proxy Cache`. It uses the exact request target and the decoded account ID. The write rule selects GET responses with HTTP 200 and without `no-cache` or `no-store` in the response's `Cache-Control`. Sign-out, an update with an undecodable token, or a change in decoded account ID clears the private and shared caches.

The proxy attempts a cache read after an upstream error with code `ENOENT`, `ENOTFOUND`, or `ECONNREFUSED`. Its fallback marks the request `only-if-cached`. The reader computes age from the cached response's `Date`. It regards an entry as stale after `max-age` seconds and as expired after `max-stale` seconds, both measured from that same date. Each directive defaults to zero when absent. The reader rejects an entry that is both stale and expired. A stale entry that has yet to expire is eligible only with `only-if-cached`. For account and entitlement responses with `max-stale=2419200`, the cutoff is 28 days from the stored response date. Dashboard still applies its own signature and expiry checks. Proxy fallback and prolonged offline operation remain unverified.

A private-cache hit carries `X-API-Proxy-Cache-Hit: true`. The proxy error writer uses the error’s status when supplied and otherwise uses 502, with the same JSON shape as the 511 response. The client-visible result of a fallback cache miss remains unverified.

## Shared response files

Connect publishes the following files under `%APPDATA%/ROLI/Shared`. The name consists of the request target encoded with JavaScript `encodeURIComponent`, followed by `.json`.

| Request target | File name |
| --- | --- |
| `/api/v1/user/` | `%2Fapi%2Fv1%2Fuser%2F.json` |
| `/api/v1/user` | `%2Fapi%2Fv1%2Fuser.json` |
| `/api/v1/user/entitlements/` | `%2Fapi%2Fv1%2Fuser%2Fentitlements%2F.json` |
| `/api/v1/user/entitlements` | `%2Fapi%2Fv1%2Fuser%2Fentitlements.json` |

Each file is a UTF-8 JSON object with two members. `headers` is the upstream response header object. `body` is the JSON value obtained by parsing the upstream body. Connect attempts this write only for cacheable responses on the allowlist. If body parsing fails, publication fails. The shared-file writer reads from the upstream stream, separately from the gzip decoding used for the HTTP response. Shared files use route-based filenames, so Connect relies on clearing them at account transitions. These files have a different representation from the private proxy cache.

The trailing-slash account and entitlement files held the same parsed JSON as their HTTP responses. The entitlement file preserved all three signature headers. See [Entitlement responses](#entitlement-responses) for the signed byte representation.

## Direct renderer API

Connect's renderer calls `https://api.roli.com/api/v1` directly. The paths below are relative to that base. The shared client requests `Accept: application/json` and `Content-Type: application/json`, supplies Connect's user agent in its request options, and uses Fetch with credentials included and CORS mode. It adds `x-access-token` when the auth store returns a token. The renderer’s Fetch path is separate from the local proxy.

### Shared headers and response handling

These are the renderer’s shared request settings. Endpoint models include status, response shape, and authentication requirements where established.

| Header | Request or response | Observed behavior |
| --- | --- | --- |
| `Accept: application/json` | Request | Set by the shared client, including on routes whose bodies the renderer reads as text. |
| `Content-Type: application/json` | Request | Set by the shared client. POST and PUT bodies are JSON serialized. GET requests have no body. |
| `User-Agent: ROLI_CONNECT/1.6.4` | Request | Supplied in Fetch options. Its wire value has yet to be captured. |
| `x-access-token: <session token>` | Request | Added when the auth store returns a token. The client can make requests without it. See each endpoint for observed requirements. |
| `x-auth-token: <replacement token>` | Response | Optional session rotation header, subject to the conditions below. |

No route-specific response header is required by the traced renderer methods. The client selects JSON or text parsing per method. Dashboard’s signature headers are part of the [native entitlement response](#native-entitlement-response).

### Upstream errors and CORS

Unauthenticated requests to protected account, entitlement, product, and soundpack routes return HTTP 401 with JSON `error.code` (number), `error.name` (string), and `error.message` (string). The public software and trial catalogs accept unauthenticated requests. The trial response can differ with a token.

An OPTIONS request with `Origin: null`, requested method GET, and requested headers `content-type,x-access-token` returned HTTP 204 for `/user`, `/user/entitlements`, and `/products/software`. The API allowed the requested headers, returned `Access-Control-Allow-Credentials: true`, and exposed `X-Auth-Token,X-ROLI-OTP`. It omitted `Access-Control-Allow-Origin`, so browser acceptance for that origin remains unverified.

### Endpoint models

Paths are relative to `/api/v1`. Body models use TypeScript-style field and type notation. GET requests have no body. Path and query parameters appear in tables. Interpretation tables describe constraints and observed behavior. Response models list all captured fields where a complete sample is available. In these models, `?` marks a field absent from at least one sampled object of the same shape, `Record<string, T>` represents a map with variable keys, and `Array<unknown>` represents an array whose samples were empty. `// no body` marks an absent body. `{}` represents an empty JSON object. Server-wide field guarantees remain unverified.

<details>
<summary><code>POST /authenticate/{identifier}</code> — Sign in and obtain a session token, with an optional identifier path parameter.</summary>

The final path segment is optional: `/authenticate` and `/authenticate/{identifier}` are supported forms. Square brackets above denote the optional slash and segment; they are not literal URL characters. Connect uses `/authenticate/roli-hub`, while the examined instrument clients use `/authenticate`. The final segment appears to identify the requesting application or integration. Its exact server-side meaning, accepted values, and effect on authentication remain unverified; `roli-hub` is an observed value rather than a fixed part of the route.

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
```

The sampled `/authenticate/roli-hub` sign-in request succeeded without a session token or a `Cookie` header. The headers above describe that Connect request, rather than requirements established for every identifier or the bare route.

**Path parameters**

| Parameter | Type | Interpretation |
| --- | --- | --- |
| `identifier` | Optional `string` | Appears to identify the requesting application or integration. Connect supplies `roli-hub`. Omit the slash and segment to use `/authenticate` |

**Example request targets**

```http
POST /api/v1/authenticate
POST /api/v1/authenticate/roli-hub
```

**Body and parameters**

Reported successful requests accept `email` with `password`, `identity` with `password`, or all three keys together. The model below requires a password and at least one account identifier, while permitting both identifiers:

```typescript
type RequestBody = {
  password: string;
} & (
  | { email: string; identity?: string }
  | { identity: string; email?: string }
);
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| `email` | Account email address. Accepted alongside `password`, with or without `identity`, in the reported requests. |
| `identity` | Email address or username supplied to the sign-in form. The successful request used an email address. |
| `password` | The account’s current password. |
| Both identifiers | A body containing `email`, `identity`, and `password` is also reported to succeed. Precedence and behavior when the identifiers disagree remain unverified. |

The following examples illustrate the three accepted key combinations. Values are placeholders:

```json
{"email": "account@example.com", "password": "<password>"}
```

```json
{"identity": "account@example.com", "password": "<password>"}
```

```json
{"email": "account@example.com", "identity": "account@example.com", "password": "<password>"}
```

The sampled Connect request to `/authenticate/roli-hub` uses `identity` and `password`. The examined Cypher2 and Strobe2 clients construct `email` and `password` for the bare `/authenticate` route.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <session cookie>
```

**Body**

```typescript
type ResponseBody = {
  token: string;
  user: {
    about_me: string;
    avatar_id: null;
    avatar_url: string;
    coppa_status: boolean;
    created_at: string;
    email: string;
    email_preferences: {
      ADD_TO_PLAYLIST: boolean;
      ALSO_REMIXED_PROJECT: boolean;
      COMMENT_ON_PROJECT: boolean;
      CREATE_TOKEN: boolean;
      FOLLOW_USER: boolean;
      FORK_PROJECT: boolean;
      GUARDIAN_NOTIFIED: boolean;
      LIKE_PROJECT: boolean;
      LUMI_GUARDIAN_NOTIFIED: boolean;
      LUMI_STRIPE_EVENT: boolean;
      MENTION_USER: boolean;
      OPT_OUT_OF_ALL: boolean;
      OPT_OUT_OF_NOISE_FM_DIGEST: boolean;
      REMIX_PROJECT: boolean;
    };
    first_name: string;
    followers_count: number;
    following_count: number;
    gradient: Array<string>;
    id: string;
    klaviyo: {
      account: string;
    };
    last_name: string;
    likes_count: number;
    location: string;
    noise_fm_url_path: string;
    outstanding_surveys: Array<unknown>;
    partner: null;
    pending: boolean;
    products: Array<{
      id: string;
      metadata: {
        authoring_users: Array<unknown>;
        authors: null;
        images: Array<unknown>;
        internal_id: null;
        redeem_methods: Array<unknown>;
      };
      name: string;
      type: string;
    }>;
    published_projects: Array<unknown>;
    push_notification_preferences: {
      ADD_TO_PLAYLIST: boolean;
      ALSO_REMIXED_PROJECT: boolean;
      COMMENT_ON_PROJECT: boolean;
      CREATE_TOKEN: boolean;
      FOLLOW_USER: boolean;
      FORK_PROJECT: boolean;
      GUARDIAN_NOTIFIED: boolean;
      LIKE_PROJECT: boolean;
      LUMI_GUARDIAN_NOTIFIED: boolean;
      LUMI_STRIPE_EVENT: boolean;
      MENTION_USER: boolean;
      OPT_OUT_OF_ALL: boolean;
      REMIX_PROJECT: boolean;
    };
    revoked: boolean;
    social: {
      facebook: null;
      soundcloud: null;
      twitter: null;
    };
    subscriptions: Array<unknown>;
    tracking_id: string;
    trial_accesses: Array<unknown>;
    username: string;
  };
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `token` | Matches `X-Auth-Token` in the sampled response. Connect reads this field to establish its session. |
| `user` | The account object returned alongside the session token. |

The status, headers, and full response model above describe the sampled `/authenticate/roli-hub` exchange. The bare-route instrument clients also read a `token` field, but an identical full account response and identical headers have not been established for that route or other identifier values.

</td>
</tr>
</table>

</details>

<a id="get-build-download"></a>

<details>
<summary><code>GET /product/{public_id}/version/{version_number}/build/{platform_code}/download</code> — Get the download URL for a specific product build.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

A request with this token header can omit the `Cookie` header. Behavior without a token is unspecified.

**Path parameters**

| Parameter | Type | Interpretation |
| --- | --- | --- |
| `public_id` | `string` | The product public ID. |
| `version_number` | `string` | The selected build’s version. |
| `platform_code` | `string` | Use the nested `build.platform_code`. The storage path can use a different platform label. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = {
  size: number;
  url: string;
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `url` | Connect uses this URL to start the download. |
| `size` | The API returns a number. Its units remain unverified. |

See the [product download inventory](roli-connect-downloads.md) for lookup paths, storage keys, checksums, and artifact access.

</td>
</tr>
</table>

</details>

<details>
<summary><code>GET /products/software</code> — List software products for the Apps catalog.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
```

The live route returned HTTP 200 without a token or cookie. Add `X-Access-Token: <session token>` for the authenticated catalog view.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = Array<{
  builds: Record<string, {
    _id: string;
    build: {
      checksum: string;
      dependencies: Array<string>;
      enabled: boolean;
      platform_code: string;
      release_notes: string;
      s3_path: string;
      variant: string;
    };
    created_at: string;
    published: boolean;
    release_notes: string;
    segments: Array<string>;
    sequential: boolean;
    updated_at: string;
    version_number: string;
  }>;
  created_at: string;
  description: string;
  hide_rpkg_in_my_roli: boolean;
  id: string;
  included_additional_content: Array<{
    builds: Record<string, {
      _id: string;
      build: {
        checksum: string;
        dependencies: Array<unknown>;
        enabled: boolean;
        platform_code: string;
        release_notes?: string;
        s3_path: string;
        variant: string;
      };
      created_at: string;
      published: boolean;
      release_notes?: string;
      segments: Array<string>;
      sequential: boolean;
      updated_at: string;
      version_number: string;
    }>;
    created_at: string;
    description: string;
    hide_rpkg_in_my_roli: boolean;
    id: string;
    included_additional_content: Array<unknown>;
    is_auto_updatable: boolean;
    is_updatable: boolean;
    is_user_unregisterable: boolean;
    links_and_downloads: Array<unknown>;
    metadata: {
      images: Array<unknown>;
      internal_id: string;
    };
    name: string;
    public_description: string;
    public_id: string;
    rpkg_available: boolean;
    slug: string;
    store_url_path: string;
    type: string;
    user_downloadable: boolean;
    user_owns_product: boolean;
  }>;
  is_auto_updatable: boolean;
  is_updatable: boolean;
  is_user_unregisterable: boolean;
  links_and_downloads: Array<unknown>;
  metadata: {
    images: Array<unknown>;
    internal_id: null | string;
  };
  name: string;
  public_description: string;
  public_id: string;
  rpkg_available: boolean;
  slug: string;
  store_url_path: null | string;
  type: string;
  user_downloadable: boolean;
  user_owns_product: boolean;
}>;
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `builds` | The authenticated response used an object keyed by platform. The unauthenticated sample used an empty array. |
| `included_additional_content` | Nested records can carry builds and download paths of their own. |
| `builds[platform].build` | Build metadata includes the platform code, storage key, variant, and checksum. A checksum can be empty. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>GET /products/trials</code> — List products offered as trials.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
```

The live route returned HTTP 200 without a token or cookie. Add `X-Access-Token: <session token>` for the authenticated catalog view.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = Array<{
  builds: Record<string, {
    _id: string;
    build: {
      checksum: string;
      dependencies: Array<unknown>;
      enabled: boolean;
      platform_code: string;
      release_notes: string;
      s3_path: string;
      variant: string;
    };
    created_at: string;
    published: boolean;
    release_notes: string;
    segments: Array<string>;
    sequential: boolean;
    updated_at: string;
    version_number: string;
  }>;
  created_at: string;
  description: string;
  hide_rpkg_in_my_roli: boolean;
  id: string;
  included_additional_content: Array<unknown>;
  is_auto_updatable: boolean;
  is_updatable: boolean;
  is_user_unregisterable: boolean;
  links_and_downloads: Array<unknown>;
  metadata: {
    images: Array<unknown>;
    internal_id: string;
  };
  name: string;
  public_description: string;
  public_id: string;
  rpkg_available: boolean;
  slug: string;
  store_url_path: null;
  type: string;
  user_downloadable: boolean;
}>;
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| Authentication | The authenticated response contained records. The unauthenticated sample was an empty array. |
| `isTrial` | Connect adds this flag after reading the response. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>PUT /serial/{serial}/unregister</code> — Unregister a device by serial number.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

Connect sends the token header when a usable session is available. Upstream token and cookie requirements for this operation remain unverified.

**Path parameters**

| Parameter | Type | Interpretation |
| --- | --- | --- |
| `serial` | `string` | The device’s `serial` from the hardware product record. |

**Body**

```typescript
type RequestBody = {};
```

</td>
<td width="50%" valign="top">

**Response**

**Headers**

Live response status and headers remain unverified.

**Body**

```typescript
// Success response body shape has not been verified.
```

This response model comes from static inspection.

JSON value passed to the product store. No narrower success schema was identified.

</td>
</tr>
</table>

</details>

<details>
<summary><code>POST /tokens</code> — Request a password reset.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
```

The reset request succeeded without `X-Access-Token` or a `Cookie` header.

**Body and parameters**

```typescript
type RequestBody = {
  email: string;
  consumer: {
    name: "roli-hub";
  };
};
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| `email` | The email address for the reset request. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
```

The response omitted `Content-Type`, `X-Auth-Token`, and `Set-Cookie`.

**Body**

```typescript
// no body
```

**Response interpretation**

| Area | Interpretation |
| --- | --- |
| Success | Connect uses HTTP 200 to advance the reset flow. The response body contains zero bytes. |
| Email delivery | The API response confirms receipt of the reset request. Delivery remains unverified. |

</td>
</tr>
</table>

</details>

<a id="get-user"></a>

<details>
<summary><code>GET /user</code> — Fetch the current account profile.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

A request with this token header can omit the `Cookie` header. An unauthenticated request returns HTTP 401.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
Cache-Control: private, max-age=0, max-stale=2419200
```

**Body**

```typescript
type ResponseBody = {
  about_me: string;
  avatar_id: null;
  avatar_url: string;
  coppa_status: boolean;
  created_at: string;
  email: string;
  email_preferences: {
    ADD_TO_PLAYLIST: boolean;
    ALSO_REMIXED_PROJECT: boolean;
    COMMENT_ON_PROJECT: boolean;
    CREATE_TOKEN: boolean;
    FOLLOW_USER: boolean;
    FORK_PROJECT: boolean;
    GUARDIAN_NOTIFIED: boolean;
    LIKE_PROJECT: boolean;
    LUMI_GUARDIAN_NOTIFIED: boolean;
    LUMI_STRIPE_EVENT: boolean;
    MENTION_USER: boolean;
    OPT_OUT_OF_ALL: boolean;
    OPT_OUT_OF_NOISE_FM_DIGEST: boolean;
    REMIX_PROJECT: boolean;
  };
  first_name: string;
  followers_count: number;
  following_count: number;
  gradient: Array<string>;
  id: string;
  klaviyo: {
    account: string;
  };
  last_name: string;
  likes_count: number;
  location: string;
  noise_fm_url_path: string;
  outstanding_surveys: Array<unknown>;
  partner: null;
  pending: boolean;
  products: Array<{
    id: string;
    metadata: {
      authoring_users?: Array<unknown>;
      authors?: null;
      images: Array<unknown>;
      internal_id: null;
      redeem_methods?: Array<unknown>;
    };
    name: string;
    type: string;
  }>;
  published_projects: Array<unknown>;
  push_notification_preferences: {
    ADD_TO_PLAYLIST: boolean;
    ALSO_REMIXED_PROJECT: boolean;
    COMMENT_ON_PROJECT: boolean;
    CREATE_TOKEN: boolean;
    FOLLOW_USER: boolean;
    FORK_PROJECT: boolean;
    GUARDIAN_NOTIFIED: boolean;
    LIKE_PROJECT: boolean;
    LUMI_GUARDIAN_NOTIFIED: boolean;
    LUMI_STRIPE_EVENT: boolean;
    MENTION_USER: boolean;
    OPT_OUT_OF_ALL: boolean;
    REMIX_PROJECT: boolean;
  };
  revoked: boolean;
  social: {
    facebook: null;
    soundcloud: null;
    twitter: null;
  };
  subscriptions: Array<unknown>;
  tracking_id: string;
  trial_accesses: Array<unknown>;
  username: string;
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `id` | Matched `uid` in the signed entitlement response. |
| `coppa_status` | The response field is Boolean. Registration sends a string enum. |
| `products` | The account object contains product summaries. `/user/products` returns the separate product record model. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>POST /user</code> — Register a new user.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
```

Registration can omit both `X-Access-Token` and `Cookie`. Connect's shared client adds the token header when it already has a usable token. Server behavior with a supplied token remains unspecified.

**Body and parameters**

```typescript
type RequestBody = {
  email: string;
  guardian_email?: string;
  password: string;
  username: string;
  opt_in_newsletter: boolean;
  coppa_status: "minor" | "non-minor" | "undetermined";
  consumer: {
    name: "roli-hub";
  };
};
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| `guardian_email` | The minor registration flow can include this field. Adult registration can omit it. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = {
  token: string;
  user: {
    id: string;
    username: string;
    email: string;
    coppa_status: boolean;
  };
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `token` | The registration store reads this field as the session token. |
| `user` | The nested shape is partially specified. |
| `user.coppa_status` | The response field is Boolean. The request sends a string enum. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>PUT /user</code> — Update the current account profile or change its password.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

Both request forms can omit the `Cookie` header when they supply `X-Access-Token`. Behavior without a token is unspecified.

**Body and parameters**

```typescript
type ProfileEditBody = {
  first_name: string;
  last_name: string;
  email: string;
  password: string;
  username: string;
};

type PasswordChangeBody = {
  password: string;
  new_password: string;
};
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| Profile edit | Sends the profile fields and current `password`. |
| Password change | Sends the current `password` and `new_password` in a separate request. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = {
  token: string;
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `token` | Both profile edit and password change returned this field. |
| Verification | `GET /user` confirmed the new profile fields, and sign-in succeeded with the new password. |

</td>
</tr>
</table>

</details>

<a id="get-user-licences"></a>

<details>
<summary><code>GET /user/licences</code> — Fetch account licences, including ROLI software and sound collections.</summary>

The endpoint must use the British spelling **`/user/licences`**. The American spelling `/user/licenses` is not interchangeable: a reported request to that path returned `Cannot GET /api/v1/user/licenses`. Use `/api/v1/user/licences` in the full request target, including when adding query parameters.

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: */*
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
Cookie: token=<cookie session token>
```

**Body and parameters**

```typescript
// no body
```

| Query parameter | Wire representation | Observed use |
| --- | --- | --- |
| `search_internal_id` | String | Product lookup identifier assembled as `com.roli.` followed by the lowercase product name with its final version digit removed. The examined requests produce `com.roli.cypher` and `com.roli.strobe`. |
| `product_version` | Decimal integer in the query string | Product version derived from the product name's final digit. Both `Cypher2` and `Strobe2` produce `2`. This is separate from the DLL build version `2.6.1.7`. |

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| Parameter presence | Both parameters are included by the recovered instrument callers. The captured request succeeds with both omitted and returns the supplied three-record array. Omission of only one parameter has not been tested. |
| Product-name conversion | The caller reads the final character as a decimal number. If that gives a nonzero value, it removes that character from the name; otherwise it retains the name and uses version `1`. It then lowercases the name. This does not establish a general parser for multi-digit product versions. |
| Identifier meaning | These values identify the product lookup used by the instrument. Their equivalence to keys in `/user/entitlements`, catalog IDs, or other product identifiers has not been established. |
| Filtering | The parameter names and caller construction establish the requested product and version. Exact server matching, case sensitivity, wildcard support, accepted version range, and unknown-product behavior remain unverified. |

**Example request targets**

```http
GET /api/v1/user/licences
GET /api/v1/user/licences?search_internal_id=com.roli.cypher&product_version=2
GET /api/v1/user/licences?search_internal_id=com.roli.strobe&product_version=2
```

The first target was captured live without query parameters. The other two illustrate targets constructed by the examined instrument clients; filtered live requests were not captured. The unfiltered sample does not establish pagination or that every account licence is always returned.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/2 200
Date: Wed, 11 Nov 2026 11:40:07 GMT
Content-Type: application/json; charset=utf-8
Content-Length: 672
Access-Control-Allow-Credentials: true
Access-Control-Expose-Headers: X-Auth-Token,X-ROLI-OTP
X-Auth-Token: <replacement session token>
Set-Cookie: token=<replacement session token>; Domain=.roli.com; Path=/; Expires=Fri, 11 Dec 2026 11:40:07 GMT; HttpOnly; Secure
ETag: W/"<response validator>"
```

**Body**

```typescript
type ResponseBody = Array<{
  authorized_machine_keys: Array<unknown>;
  status: string;
  product_id: string;
  product_name: string;
  licence_id: string;
  public_id?: string;
}>;
```

This model lists all fields in the supplied three-record JSON array. All three records have `status: "active"` and empty `authorized_machine_keys` arrays. The sample establishes neither the element type of a nonempty machine-key array nor the complete set of status values. Account-specific licence IDs are omitted from this document.

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| Top-level array | Contains licence records. The sample includes Equator2, Equator Collection 1 - Evolving Classics, and Equator Collection 2 - Motion Dance. |
| `authorized_machine_keys` | Array present on every sampled record, empty in each case. Its element schema, machine-limit rules, and role in application authorization remain unverified. |
| `status` | String with the observed value `active`. Other values and their effect on clients remain unverified. |
| `product_id` | Product identifier represented as a string. Do not substitute it for `licence_id` or a query's `search_internal_id`. Cross-endpoint identifier equivalence remains unverified. |
| `product_name` | Human-readable software or collection name. |
| `licence_id` | Identifier of the licence record, separate from its product identifier. Its presence does not establish an authorization token or signed entitlement. |
| `public_id` | Optional product identifier: `com.roli.equator2` on the Equator2 record, absent from both collection records. Its relationship to `search_internal_id` has not been established. |
| `licence_type` | Absent from all three supplied records. The instrument clients separately recognize this field in response text, as described below. Its presence on every licence or product is not established. |

**Instrument-specific response handling**

The recovered Cypher2 and Strobe2 clients scan response text for `licence_type` and read its quoted string value. This is an additional client observation, rather than a field present in the supplied Equator response model.

| Recognized `licence_type` value | Instrument interpretation |
| --- | --- |
| `cypher-player`, `strobe-player` | Player licence result |
| `cypher-full`, `strobe-full` | Full licence result |

Both clients recognize all four labels in this shared lookup code. A full result takes precedence over a Player result. A successful login without a recognized licence leads to the client's no-product-licence message; it does not establish that the response is empty or that the server rejected authentication. These instrument-specific labels do not describe every ROLI product record returned by the endpoint. Additional response fields, licence labels, and their server-wide guarantees remain unverified.

</td>
</tr>
</table>

</details>

<a id="get-user-entitlements"></a>

<details>
<summary><code>GET /user/entitlements</code> — Fetch the current account’s entitlement response.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

A request with this token header can omit the `Cookie` header. An unauthenticated request returns HTTP 401.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
Cache-Control: private, max-age=0, max-stale=2419200
X-Message-Signature: <body signature>
X-Signer-Certificate: <signer certificate>
X-Signer-Certificate-Signature: <certificate signature>
```

**Body**

```typescript
type ResponseBody = {
  entitlements: Record<string, {
    enabled: boolean;
    expiration?: null;
    id: string;
    licences?: Array<string>;
    name: string;
  }>;
  expiration: number;
  uid: string;
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `uid` | Matched `id` in the account response. |
| Top-level `expiration` | Unix seconds. Dashboard checks this during validation. |
| Per-entry `expiration` | The sample includes `null`. Non-null values and their effect remain unverified. |
| `licences` | Known strings are `cypher-player`, `equator-player`, and `strobe-player`. The field may contain other values. |
| Trial fields | Dashboard reads `valid_until` when the trial fields are present. See [Native entitlement response](#native-entitlement-response). |
| Signed body | The renderer exposes the JSON body as text. Signature verification uses the original signed text. |

</td>
</tr>
</table>

**Response signatures**

All three header values are Base64. The two detached signatures use Ed25519. The certificate signature authenticates the signer’s public key and expiry, and the body signature authenticates the entitlement payload.

| Header | Decoded record | Signed input |
| --- | --- | --- |
| `X-Signer-Certificate` | 52-byte certificate containing the signer key and its expiry | This header supplies the certificate. |
| `X-Signer-Certificate-Signature` | 74-byte detached signature | ASCII text of the canonically Base64-encoded certificate. Dashboard uses its embedded root public key. |
| `X-Message-Signature` | 74-byte detached signature | UTF-8 entitlement response text up to the first NUL, excluding that terminator. Dashboard uses the certified signer key. |

**Decoded record layout**

Offsets start at zero within each record. Public-key offsets are relative to the start of that record inside the certificate.

| Record | Byte offset | Size | Field |
| --- | ---: | ---: | --- |
| Certificate | 0 | 2 | ASCII `C1` tag |
| Certificate | 2 | 8 | Certificate expiry in big-endian Unix seconds |
| Certificate | 10 | 42 | Signer public-key record |
| Public key | 0 | 2 | ASCII `Ed` tag |
| Public key | 2 | 8 | Key ID |
| Public key | 10 | 32 | Ed25519 public key |
| Detached signature | 0 | 2 | Algorithm tag |
| Detached signature | 2 | 8 | Signing key ID |
| Detached signature | 10 | 64 | Ed25519 signature |

**Dashboard verification**

1. Require HTTP 200 and decode the three headers. Compare the certificate signature’s key ID with the embedded root key ID, then verify the signature over the canonical Base64 certificate text.
2. Check the certificate expiry. Compare the body signature’s key ID with the certificate’s signer key ID, then verify the signature over the response body text.
3. Parse the verified JSON, match `uid` to the current account, and check the top-level payload `expiration`.

The certificate signature covers the canonical Base64 certificate text. The body signature covers the exact JSON bytes, including whitespace. Preserve the original response text for verification. The [Dashboard signature specification](roli-dashboard-entitlements.md#signed-entitlement-response) gives the embedded root public key and remaining verifier details.

</details>

<details>
<summary><code>GET /user/products</code> — List products associated with the current account.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

A request with this token header can omit the `Cookie` header. An unauthenticated request returns HTTP 401.

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = Array<{
  builds: Array<unknown> | Record<string, {
    _id: string;
    build: {
      checksum: string;
      dependencies: Array<unknown>;
      enabled: boolean;
      platform_code: string;
      release_notes: string;
      s3_path: string;
      variant: string;
    };
    created_at: string;
    published: boolean;
    release_notes: string;
    segments: Array<string>;
    sequential: boolean;
    updated_at: string;
    version_number: string;
  }>;
  claimed_at?: string;
  created_at: string;
  description: string;
  hardware_serial: null;
  hide_rpkg_in_my_roli: boolean;
  id: string;
  include_as_claim?: boolean;
  included_additional_content: Array<{
    acts_as_singleton: boolean;
    builds: Record<string, {
      _id: string;
      build: {
        checksum: string;
        dependencies: Array<unknown>;
        enabled: boolean;
        platform_code: string;
        release_notes?: string;
        s3_path: string;
        variant: string;
      };
      created_at: string;
      published: boolean;
      release_notes?: string;
      segments: Array<string>;
      sequential: boolean;
      updated_at: string;
      version_number: string;
    }>;
    created_at: string;
    description: string;
    hardware_serial: null;
    hide_rpkg_in_my_roli: boolean;
    id: string;
    included_additional_content: Array<unknown>;
    is_auto_updatable: boolean;
    is_singleton: boolean;
    is_updatable: boolean;
    is_user_unregisterable: boolean;
    licences: Array<unknown>;
    links_and_downloads: Array<unknown>;
    metadata: {
      images: Array<unknown>;
      internal_id: string;
    };
    name: string;
    public_description: string;
    public_id: string;
    rpkg_available: boolean;
    serial: null;
    slug: string;
    store_url_path: string;
    type: string;
    user_downloadable: boolean;
    user_owns_product: boolean;
  }>;
  is_auto_updatable: boolean;
  is_updatable: boolean;
  is_user_unregisterable: boolean;
  licences: Array<unknown>;
  links_and_downloads: Array<{
    accepted_licence_types: Array<unknown>;
    description: string;
    id: string;
    name: string;
    type: string;
    url: string;
    url_type: string;
  }>;
  metadata: {
    images: Array<unknown>;
    internal_id: null | string;
  };
  name: string;
  previously_registered?: boolean;
  public_description: string;
  public_id: null | string;
  registered_product_id?: string;
  rpkg_available?: boolean;
  serial: null | string;
  slug: string;
  status?: string;
  store_url_path: null | string;
  type: string;
  user_downloadable: boolean;
  user_owns_product: boolean;
}>;
```

For records with `type: "hardware"`, read the product serial number from `serial`. Both hardware entries in the supplied response had a string `serial` and `hardware_serial: null`. Other product types may have `serial: null` or include registration fields used by the claim flow.

**Known enum values**

These values come from the supplied response and the renderer’s serial handling. The field models remain open to additional strings.

| Field | Known values |
| --- | --- |
| `type` | `external`, `hardware`, `software` |
| `included_additional_content[].type` | `additional_content` |
| `status` | `claimed`, `unclaimed` |
| `builds` keys and `builds[platform].build.platform_code` | `osx`, `windows32`, `windows64` |
| `builds[platform].build.variant` | `installer`, `rpkg` |
| `links_and_downloads[].type` | `manual`, `software` |
| `links_and_downloads[].url_type` | `normal` |

**Record interpretation**

| Area | What the supplied response shows |
| --- | --- |
| Ownership and downloadability | Nested `additional_content` records had `user_owns_product: false` and `user_downloadable: true`. Read these flags independently. |
| Hardware identity | Both hardware records had `public_id: null`, a `registered_product_id`, a string `serial`, and `builds: []`. Requiring a non-null `public_id` would exclude them. |
| Build shape | Downloadable software used a platform-keyed `builds` object. Hardware and the external product used an empty array. |
| Installer and RPKG availability | Dashboard had `user_downloadable: true` and `rpkg_available: false`. Its builds used `variant: "installer"`, so filtering for `rpkg_available` alone would exclude this downloadable product. |
| External products | The sampled external product had `status: "claimed"`, a serial, and a supplemental link. It also had `user_downloadable: false` and `builds: []`. |
| Licence data | Owned, downloadable software records could have `licences: []`. The product-level array alone does not establish entitlement status. |

These observations describe the supplied response. Server-side download authorization rules remain unverified.

</td>
</tr>
</table>

</details>

<details>
<summary><code>POST /user/products</code> — Register a product by serial number.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

Connect sends the token header when a usable session is available. Upstream token and cookie requirements for this operation remain unverified.

**Body and parameters**

```typescript
type RequestBody = {
  serial_number: string;
  hardware_serial?: string;
};
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| `serial_number` | The serial supplied to the product registration form. |
| `hardware_serial` | The software registration caller omits this field. Hardware product responses use `serial` for the device serial number. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

Live response status and headers remain unverified.

**Body**

```typescript
// Success response body shape has not been verified.
```

This response model comes from static inspection.

JSON value passed to the product store. No narrower success schema was identified.

</td>
</tr>
</table>

</details>

<details>
<summary><code>GET /user/products/soundpacks?variant=rpkg</code> — List the current account’s soundpacks for ROLI Package Manager.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

A request with this token header can omit the `Cookie` header. An unauthenticated request returns HTTP 401.

**Query parameters**

| Parameter | Interpretation |
| --- | --- |
| `variant` | Connect sends `rpkg` for the package-manager variant. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

```http
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
X-Auth-Token: <session token>
Set-Cookie: <cookie value>
```

**Body**

```typescript
type ResponseBody = Array<{
  connect_artwork_offset_y: number;
  download_url: string;
  id: string;
  manifest_id: string;
  metadata: {
    authoring_users: Array<{
      name: string;
      user: null | string;
    }>;
    authors: Array<string>;
    colors: Array<string>;
    descriptions: Array<{
      language: string;
      text: string;
    }>;
    featured: boolean;
    images: Array<{
      cloudinary_id: string;
      crop_options: Array<unknown>;
      src: string;
      type: string;
    }>;
    internal_id: null | string;
    manifest_id: string;
    presets: Array<{
      colors: Array<unknown>;
      engine: string;
      name: string;
      preview: null;
      uuid: string;
    }>;
    preview: string;
    redeem_methods: Array<{
      redeem_method: string;
      redeem_method_id: string;
    }>;
  };
  name: string;
  public_id: string;
  rpkg_available: boolean;
}>;
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `manifest_id` | Connect uses the top-level value as the soundpack item’s `public_id`. |
| `metadata.manifest_id` | The response can also carry the identifier in nested metadata. |
| `download_url` | The soundpack record includes a download URL. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>POST /user/products/{id}/claim</code> — Claim a serial number for a registered product.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

Connect sends the token header when a usable session is available. Upstream token and cookie requirements for this operation remain unverified.

**Path parameters**

| Parameter | Type | Interpretation |
| --- | --- | --- |
| `id` | `string` | The product record’s `registered_product_id`. |

**Body**

```typescript
type RequestBody = {};
```

</td>
<td width="50%" valign="top">

**Response**

**Headers**

Live response status and headers remain unverified.

**Body**

```typescript
type ResponseBody = {
  serial_number: string;
};
```

**Response interpretation**

| Field or area | Interpretation |
| --- | --- |
| `serial_number` | The renderer stores the returned serial on the claimed product record. This response field was identified from the caller. |

</td>
</tr>
</table>

</details>

<details>
<summary><code>PUT /user/splice</code> — Report the current Splice lease state for Equator2.</summary>

<table width="100%">
<tr>
<td width="50%" valign="top">

**Request**

**Headers and cookies**

```http
Accept: application/json
Content-Type: application/json
User-Agent: ROLI_CONNECT/1.6.4
X-Access-Token: <session token>
```

Connect sends the token header when a usable session is available. Upstream token and cookie requirements for this operation remain unverified.

**Body and parameters**

```typescript
type RequestBody = {
  product_id: "equator2";
  lease_status?: "not_active" | "active" | "complete";
  splice_id: unknown;
};
```

**Request interpretation**

| Field or area | Interpretation |
| --- | --- |
| `lease_status` | Connect omits the field when the decoded lease state has no mapping. |
| `splice_id` | The decoded lease’s `user` value, passed through without a type check. |

</td>
<td width="50%" valign="top">

**Response**

**Headers**

Live response status and headers remain unverified.

**Body**

```typescript
// Success response body shape has not been verified.
```

This response model comes from static inspection.

JSON value. The traced caller reads no response fields.

</td>
</tr>
</table>

</details>

### Native entitlement response

Dashboard reads the signed JSON body and verifies the three signature headers. The [entitlement response model](#get-user-entitlements) shows the sampled body fields and types. The top-level `uid` identifies the account by the account response’s `id`.

An individual entitlement can also carry its own `expiration` field. Airwave Player entitlements can have `expiration: null`. Dashboard’s traced expiry check uses the top-level numeric `expiration`. The meaning of a null entry expiry, the type and units of non-null values, and their effect on client acceptance remain unverified.

Dashboard also reads the trial expiry when both trial fields are present. See the [Dashboard wire model and verification rules](roli-dashboard-entitlements.md#signed-entitlement-response).

### Status and token handling

The renderer accepts HTTP statuses 200 through 299 before parsing the response. Other statuses become request errors. If reading or parsing a successful response fails, the API wrapper returns status and headers with an error field. A visible `x-auth-token` response header can replace the stored token after a successful API response if a token is already present or the request was the sign-in route. The sign-in store then also sets the token from the response body. On a 401 with a stored token, the API client clears the token by default. The `PUT /user` account update explicitly opts out of this behavior.

The product and download routes support catalog, registration, and installation. The signed download URL grants access to a build artifact. Its handling is separate from the native consumer's entitlement response and signature checks.

## Validation and signature handling

### Public key distribution

Dashboard 4.7.2 uses two public keys for entitlement verification.

| Key | Source | Use |
| --- | --- | --- |
| Root public key | Embedded in the Dashboard executable | Verifies `X-Signer-Certificate-Signature` over the Base64 certificate text. The [Dashboard spec](roli-dashboard-entitlements.md#embedded-root-key-locations) records the key’s file offsets and identifies the referenced copy. |
| Signer public key | Delivered in the entitlement response’s `X-Signer-Certificate` header | Verifies `X-Message-Signature` over the response body after Dashboard verifies the certificate and checks its expiry. |

The entitlement request supplies the signer certificate in the same response as the body. Dashboard can verify it with the embedded root without a separate key request. Connect forwards the certificate and signatures and preserves the headers in the shared entitlement file. Key distribution for other consumers remains unverified.

### Session tokens

The renderer initializes from Electron local storage under the key `token`. It sends the initial token and later updates to the main process through `auth-token:notify:initialized` and `auth-token:notify:updated`. A token returned by the auth store must decode as a JWT. If the decoded `exp` is truthy, the renderer requires it to be strictly later than the current Unix time in seconds and clears the session on expiry. An absent or falsy `exp` skips that comparison. An undecodable token is withheld by the getter.

The main process accepts an IPC-supplied token into proxy state when the JWT decoder returns a payload. It decodes `id` for cache partitioning and account-change detection. It does not run the renderer's expiry comparison. A caller-supplied `x-access-token` reaches the upstream proxy path if present and nonempty. The local HTTP gate checks presence, and decoding on the cache path does not validate the signature. The traced token paths call the JWT library's decoder. The bundle also includes its signing and verification functions, but those functions were not called by the traced token paths. The remote issuer's token algorithm, verification key, and acceptance policy remain unknown.

### Entitlement responses

Connect's proxy and shared-file writer apply transport, cache, and JSON parsing rules. The traced code has no entitlement signature, signer expiry, payload expiry, or entitlement account-binding check. A bounded scan found no Dashboard signature-header literals in the shipped main and renderer JavaScript, bundled executables, or native add-ons. The proxy forwards these headers through its general response-header path when present, and the shared writer stores upstream headers in the JSON wrapper. A cache write therefore establishes that Connect accepted the response for caching. Signature acceptance is a separate step in the consuming app.

[Dashboard 4.7.2](roli-dashboard-entitlements.md) reads `x-message-signature`, `x-signer-certificate`, and `x-signer-certificate-signature`. It verifies a certificate chain rooted in an embedded public key and checks the certificate expiry, signed payload expiry, and account identity. That evidence applies to Dashboard's consumer path. The same checks in other apps require separate evidence.

Both entitlement route variants return the signed entitlement model. Dashboard verifies the canonical Base64 certificate text against its embedded trust anchor and verifies the exact JSON body bytes with the certified key. See the [Dashboard verification sequence](roli-dashboard-entitlements.md#verification-sequence).

For offline playback, preserve genuine account and entitlement responses together, including the exact entitlement body bytes and signature headers for HTTP playback. Preserve the parsed wrapper for shared-file playback. Dashboard reserializes the wrapper's `body` before verification, so an HTTP fixture and its shared-file equivalent need separate tests. A Connect cache lifetime does not extend a signed payload's or certificate's lifetime.

## Consumer evidence

The four Windows standalone executables and their corresponding installed VST3 binaries each contain the exact literals `roli_connect_ipc_`, `/user/`, and `/user/entitlements/`. The standalone builds report the following product versions.

| Product | Standalone version |
| --- | --- |
| Equator2 | 2.5.2 |
| ROLI Studio Player | 1.4.1 |
| ROLI Studio Drums | 1.4.1 |
| ROLI Airwave Player | 1.4.1 |

The Studio Player executable also contains code references to those three literals and to `https://api.roli.com/api/v1`. The local pipe prefix, trailing-slash route fragments, and remote base are present in that consumer. Transport selection, cache fallback order, route construction, and the native licensing decision remain unverified.

The Studio Player executable SHA-256 is `e777ee1565c54781d2ad234942171cb31a6be868e8205290aabf10336318f0c5`.

## Compatibility criteria

Offline compatibility depends on each consumer’s transport, cache behavior, and entitlement validation.

1. Record a baseline for an already licensed account and machine. Capture the first launch, successful licensed launch, and relaunch with the network unavailable. Record whether each request uses the named pipe, TCP, or a direct upstream connection, and which shared files are opened.
2. Preserve genuine authorized account and entitlement responses as private fixtures. Record their structural shapes, status, relevant headers, and exact byte lengths separately from fixture values. Keep credentials, account identifiers, and entitlement contents out of the repository.
3. In an isolated profile, test the local HTTP interface with the genuine fixtures, then test shared-file playback separately. Check both spellings of each route. Compare behavior with Connect available, Connect absent, and with an upstream lookup failure.
4. Exercise a missing token, a missing cache entry, a malformed response, a known expired entitlement if available, a different account, and a product absent from the entitlement set. A service should supply only entitlements demonstrably granted to the account and maintain account separation when publishing or retiring shared files.
5. Repeat the successful and negative cases for each standalone app and plug-in build in scope. Record whether the app opens and whether it loads licensed content and saves and reopens a project.

Compatibility remains unverified until these checks identify the native apps' required fields, validity rules, and behavior with genuine data after upstream loss. A product name or serial number alone is insufficient evidence for the wire payload or the native acceptance decision.
