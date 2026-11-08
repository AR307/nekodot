# Office preview dependencies

Pinned MIT-licensed source distributions from pub.dev:

- `quds_office_editor` 1.6.0
- `quds_office_engine` 1.5.0
- Upstream: https://github.com/MohammedAsaadAsaad/quds_office_suite

Runtime source, required fonts/assets and original licenses only. No upstream
examples, build products or tests are included. Font licenses remain in `fonts/`.

Local fixes, reproduced with the product's independently generated Office fixtures:

1. Read Word run-level `w:br` elements, preserving explicit page/column/line breaks.
2. Dispose decoded Office images with their render objects, and do not repaint
   a disposed canvas when an asynchronous decode completes.
3. Use each presentation's original slide dimensions instead of a fixed
   720 x 405 point canvas, avoiding cropped widescreen and portrait slides.
4. Render slide text at the parsed font size rather than a fixed 16 points;
   preserve explicit text bold and solid slide background colors.

The sources are checked in so builds do not mutate a shared package cache.
DOCX/XLSX/PPTX use these native read-only surfaces; PDF keeps the existing pdfrx
reader. Legacy binary DOC/XLS/PPT and exact Microsoft Office fidelity are not
claimed. No external conversion service receives document contents.
