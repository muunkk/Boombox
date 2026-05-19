# ADR-0013: Runtime YouTube Music API Key Resolution

## Status
Accepted

## Context
Boombox calls YouTube Music's internal API through `YTMusicClient`. The previous implementation embedded a client key-like literal directly in production source. Even when such values are derived from public web clients, keeping key-shaped constants in source conflicts with the repository rule against checked-in API keys or tokens and makes future rotation harder.

## Decision
Resolve the YouTube Music internal API key at runtime from the YouTube Music bootstrap page. `YTMusicAPIKeyProvider` fetches the bootstrap configuration, extracts `INNERTUBE_API_KEY`, caches it in memory for the current app session, and supplies it to `YTMusicClient` when building API URLs. Tests cover bootstrap parsing without storing a real key.

## Consequences
Production source no longer contains a hard-coded API key-like value. API startup now depends on fetching and parsing the current YouTube Music bootstrap configuration, so failures in that bootstrap request surface as normal network or parse errors. The client can adapt to key rotation without a source change.
