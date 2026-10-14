# C1: complete catalog and offline startup

Approved scope: keep accepted UI unchanged; implement NV-06/07/09 before batch
operations. Never call a truncated listing complete or replace a good snapshot
with one. No offset/page parameter is assumed without server evidence.

1. Add `spec/library_spec.lua`: reported total larger than 28 triggers a full
   request; missing/invalid totals, duplicate IDs, server caps and changing sets
   fail without replacing old data. Observe red, implement, rerun.
2. Extend `catalog_store_spec.lua` for offline reconstruction fields, timestamp,
   safe signed-data exclusion and schema-v1 backwards compatibility.
3. Bind the store in `main.lua` and library cache loading with account checks.
   Add offline and logout production-entry tests before changing startup.
4. Add a subprocess transport with bounded in-memory pipe communication; run
   real KOReader integration to verify no network work happens in the parent,
   cancellation and worker failure close/reap resources.
5. Connect asynchronous shelf refresh; reject stale account responses, show
   sync outcome without changing accepted chrome, and preserve navigation.
6. Add short-lived memory-only signature lookup to avoid per-book refresh;
   expired/missing addresses require verified fresh catalog, never disk tokens.
7. Run all Lua specs, real runtime catalog+EPUB integration and syntax checks;
   review, commit and push a coherent C1 checkpoint. Record remaining gates.

Request/resource safeguards are refusals, not truncated catalog fallbacks:
100,000 entries and 32 MiB serialized worker result. A larger library or server
cap returns an explicit error with old data preserved. The implementation must
be tested against the actual user catalog separately; synthetic fixtures do not
prove new server capacity limits.
