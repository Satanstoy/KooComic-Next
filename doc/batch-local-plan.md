# B1: selection and batch local deletion

Approved NV-04/14/15 scope. Keep the accepted ordinary shelf appearance; replace
the same footer only while selecting. Download queue remains a separate D1 gate.

1. Add failing selection specs: account-scoped entry IDs, cross-page toggles,
   refresh/reorder resolution, pruning and account reset. Implement pure model.
2. Add failing Storage specs: indexed EPUB only, outside-root/link refusal,
   reading/processing lock, identity mismatch and preserved .part/sidecar.
3. Add failing LocalManager specs: real-file deduped preview, skipped unindexed
   records, bounded serial scheduled execution, partial failure and byte totals.
4. Bind long-press, checked outlines and selection footer to the actual grid;
   bind controller/series menu deletion with explicit ConfirmBox and final report.
5. Verify active account again after confirmation, and preserve selection across
   pages/filtering without treating group count as physical file count.
6. Run actual KOReader temporary-files integration and selection render, all Lua
   regressions, EPUB/catalog integrations, review, commit and push.

Execution re-stats identities, refuses open/active targets and retains .part
indexes when partial files remain. No recursive deletion, remote delete calls,
sidecar deletion or auto-delete based on reading progress is introduced.
