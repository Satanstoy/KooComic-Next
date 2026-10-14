# Navigation and series styles

Each step is a 2-5 minute red/green unit, grouped into a validated checkpoint.

1. Extend `spec/settings_migration_spec.lua`: default divider and persisted
   valid style survive reload, corrupt style falls back without losing records.
2. Add imported-style tests to `spec/bookshelf_components_spec.lua`: six named
   modes, required external labels, pile count and diagonal collage placement.
3. Import ribbon/pile geometry from pinned upstream into
   `koobone/ui/vendor/bookshelf/stack_display.lua`, inject theme/font, and keep
   all upstream setting/cache/repository dependencies out.
4. Add failing `spec/bookshelf_grid_spec.lua` bindings for compact symbols-font
   navigation and per-style composition, then wire the production grid.
5. Add failing settings picker tests, implement explicit six-option menu and
   preserve page/query while redrawing. Bound collage prefetch to visible cards.
6. Render actual KOReader six-style artifacts, inspect glyphs/clip bounds and
   rerun all specs plus EPUB integration; review, checkpoint and push.
