# Third-Party Notices

MacMarkDown is released under the [MIT License](LICENSE). It builds on the
following third-party components. Where a component is bundled as a minified
asset, this file restores the attribution that minification removed.

## Swift packages

| Component | License | Home |
|-----------|---------|------|
| swift-markdown | Apache License 2.0 | https://github.com/apple/swift-markdown |
| Yams | MIT License | https://github.com/jpsim/Yams |

Both are resolved by Swift Package Manager at build time and ship with their
own license files.

## Bundled rendering engines

| Component | License | Home |
|-----------|---------|------|
| MathJax 3 (`MacMarkDown/Resources/Extensions/mathjax-tex-svg.js`) | Apache License 2.0 | https://www.mathjax.org |
| Mermaid (`MacMarkDown/Resources/Extensions/mermaid.min.js`) | MIT License | https://mermaid.js.org |
| Viz.js (`MacMarkDown/Resources/Extensions/viz.js`) | MIT License | https://github.com/mdaines/viz.js |

Notes:

- The Mermaid bundle includes its own third-party dependencies (dagre, d3 and
  others), all distributed under the MIT License; a dagre copyright notice is
  preserved inside the bundle.
- Viz.js embeds a compiled Graphviz built with Emscripten. Graphviz is
  distributed under the Eclipse Public License 1.0
  (https://graphviz.org); Emscripten is distributed under the MIT / University
  of Illinois license. Corresponding source is available from the upstream
  projects.

## Color schemes and styles

Editor themes and preview stylesheets use palettes and naming conventions that
are widely shared in the Markdown community. Credit where due:

| Scheme | Author | License |
|--------|--------|---------|
| Solarized | Ethan Schoonover | MIT |
| Tomorrow | Chris Kempson | MIT |
| GitHub Markdown styles | GitHub | MIT |

Other theme names (Clearness, Mou, Writer) are retained for familiarity with
the community's naming conventions.
