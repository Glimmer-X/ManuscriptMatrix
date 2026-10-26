# Visual system

## Direction

The interface should feel like a calm research instrument: warm neutral canvas, ink-like typography, restrained colour, precise dividers and deliberate density. Avoid generic dashboard cards, excessive gradients and oversized navigation chrome.

## Density

- detailed manuscript columns use 204 pt;
- the detailed journal identity column uses 240 pt;
- detailed matrix rows use 112 pt;
- compact cards show manuscript label, state, live elapsed days and one contextual line;
- expanded cards add targets, history and relationships without navigating away from the matrix.
- semantic overview uses 104 pt manuscript columns, a 194 pt frozen journal
  column and 60 pt rows;
- overview manuscript headers retain the short title and status dot only;
- overview journal cells retain rank, journal name and a publisher dot: Nature
  is monochrome, IEEE is blue, Elsevier is orange and ACM is cyan;
- overview journal names may wrap to two lines; Transactions titles use the
  presentation-only `Trans. on …` prefix so their distinguishing subject remains
  visible without changing persisted journal identity;
- overview manuscript status uses a fixed-height, centred colour bar above a
  reserved two-line title area, so one- and two-line labels remain aligned;
- awaiting-submission bars use a grey track with a jade stage fill in overview;
  detailed preparation cards repeat the same fill along their bottom edge;
- journal rows promote IF, CCF and the latest CAS partition into one strong
  typographic line in both densities; CCF and CAS grades use consistent semantic
  colour while JCR, annual history and emerging rankings remain secondary;
- missing IF/CCF/CAS values render consistently as `—`; journal editing uses
  finite pickers for partition systems and grades instead of free-form text;
- the journal library reuses matrix publisher marks and metric hierarchy instead
  of maintaining a separate visual vocabulary;
- manuscript relationship indicators are reserved for detailed density and do
  not appear in overview headers;
- manuscript headers remain pinned during vertical matrix scrolling, while the
  journal rail remains pinned during horizontal scrolling;
- compact orthogonal fold controls can temporarily remove globally unused
  journal rows or incomplete/accepted manuscript columns without changing data
  or the sidebar's current-state scope;
- the two fold glyphs share one fixed icon canvas; manuscript-column folding
  uses a purpose-drawn horizontal glyph instead of relying on symbol rotation;
- overview live and historical marks show a compact status glyph plus elapsed
  days (`paperplane 23d`, `xmark 4d`) in their semantic colour; live badges use
  a stronger fill while historical badges are quieter. Target marks remain
  label-free dashed blocks.

## Semantic colour

- indigo: live submitted state;
- amber: revisions and decisions requiring attention;
- vermilion: rejection;
- jade: acceptance, target planning, preparation progress and completion;
- graphite: historical, withdrawn and pre-completion preparation states;
- warm paper: application canvas.

Colour is never the sole carrier of meaning. In overview mode, colour and shape
provide the at-a-glance layer while the complete state remains available through
the cell's accessibility label and click action.

Primary creation uses a borderless light-indigo capsule so it reads as an
action without competing with live-status colours.

## Motion

Use short, low-distance transitions. Card expansion may use a subtle 3D flip or matched geometry after the core flows are stable. Historical events should not animate as if they are active.

Semantic zoom uses a restrained 300 ms spring. Hovering an overview status mark
adds only a small scale and glow, preserving the matrix rhythm.

Horizontal scrolling updates only the pinned manuscript-header viewport. Cell
presentation data is indexed once per board snapshot, equatable cells avoid
unrelated redraws, and empty matrix cells do not install hover tracking regions.

## Accessibility

- support system text scaling where matrix geometry permits;
- preserve readable contrast in light and dark appearances;
- expose complete VoiceOver labels for status, dates and target priority;
- provide keyboard alternatives later without making shortcuts mandatory.
