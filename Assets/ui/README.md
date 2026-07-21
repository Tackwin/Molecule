# Molecule UI skin direction

Reference concept: `molecule-ui-theme-concept.png`

## Visual language

- Dark hammered iron outer frame with small rivets and clipped corners.
- Quiet dark wood / charcoal center so gameplay remains readable.
- Deep desaturated teal-blue inner surfaces.
- Aged brass keylines and amber highlights for important affordances.
- Steel-blue raised buttons with a subtle glossy bevel.
- Small glossy icon tiles for actions, inventory, and resources.
- Use texture and bevel sparingly on repeated controls; reserve larger ornaments for panel corners and title bars.

## Suggested 9-slice primitive

Start with one reusable panel primitive rather than separate art for every window:

```text
source atlas cell: 256 x 256
corner inset:      24 px on every side
inner border:       3 px
```

The four 24x24 corners remain fixed. The top, bottom, left, and right strips stretch or tile. The center is a low-contrast charcoal/teal fill and may stretch freely.

Recommended variants:

1. `panel`: charcoal center, brass keyline, iron corners.
2. `panel_blue`: blue inner bevel for active/selected containers.
3. `button_primary`: brighter steel-blue face, amber hover edge.
4. `button_secondary`: dark iron face, low-contrast blue edge.
5. `slot`: square inset frame for units, abilities, and app-like action icons.

## Renderer integration notes

`src/GUI.jai` currently emits only solid quads. Add a textured quad kind and a helper that emits the nine regions using normalized atlas UVs. Keep the visual center quiet so the same panel can be used for the in-game HUD, lobby tables, dialogs, and settings screens.

Suggested draw order:

```text
panel shadow -> panel fill -> nine-slice frame -> title bar -> content -> controls
```

Do not put text into the sprite. Render labels with the existing MSDF font path so localization and scaling remain possible.

## Palette starting point

```text
iron       #151B20
wood       #2B211B
teal       #0C3445
steel      #537D9A
brass      #C79B35
gold       #F0C85C
emerald    #5CAA55
danger     #B84B3F
```

