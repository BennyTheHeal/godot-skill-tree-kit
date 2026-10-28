# Changelog

All notable changes to Skill Tree Kit are documented here. Versions follow [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-10-28

### Added
- Active abilities: `TKSkill.ability` and `ability_rank`; `TKSkills.ability_unlocked` / `ability_locked` signals (learn, unlearn, reset, load), `has_ability()`, `get_abilities()`. The tree view shows "Unlocks: ...".
- Exclusive branches: `TKSkill.exclusive_group` ("choose A or B" across all trees). Learning one locks the others with `EXCLUSIVE_TAKEN` (`TKResult.excluded_by`); unlearn or reset frees the choice. `get_exclusive_choice()`, `get_exclusive_rivals()`, `is_excluded()`. Dashed line and greyed-out side in the view; validation refuses exclusive skills that require each other.
- Free placement: `TKSkill.use_free_position` / `free_position` (grid units) and `place()`; `TKSkillTree.get_extent()`; `TKTreeView.line_style` (Auto, Elbow, Curve, Straight), curved links for free trees.
- Demo: Whirlwind or Bulwark in the Warrior tree, a freely placed Survivor tree with curved links, abilities shown with the stats. 19 automated tests.

### Compatibility
- Trees and saves made with 1.0 load unchanged (same save format, version 1); grid trees are drawn exactly as before. When an update makes two learned skills exclusive, `load_data()` keeps the first one in tree order and refunds the other.

## [1.0.0] - 2026-10-26

### Added
- `TKSkill`, `TKSkillTree`: skills on a grid with ranks, cost, requirements, effects per rank, row gates, validation.
- `TKSkills`: points, learn, unlearn (protecting dependent skills and row gates), resets with an optional item cost paid through Inventory Kit, stat bonuses across trees, save / load.
- `TKTreeView`: tabs per tree, lines between requirements, ranks, details, Learn / Unlearn / Reset, mouse, keyboard and gamepad.
- Demo with a Warrior and a Survivor tree in the four Inventory Kit art styles; 14 automated tests; translation template.
