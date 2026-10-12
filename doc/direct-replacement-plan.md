# Direct replacement without retained originals

User-approved change supersedes original-backup and original-restoration
requirements for new processing tasks. Keep existing task ledgers readable.

1. Red tests for backup-free commit and irreversible UI confirmation.
2. Bind the new default profile to direct replacement; do not copy originals.
3. Record the policy in the journal and reconcile committed output by SHA even
   when no backup exists. Retain original until validated atomic rename.
4. Remove restore controls; guard the internal legacy restore API against new
   backup-free jobs. Keep old transactions compatible, not silently rewritten.
5. Test failure boundaries, actual default Service processing/restart with no
   original artifact, full regressions, reviewer check, commit and CI.
