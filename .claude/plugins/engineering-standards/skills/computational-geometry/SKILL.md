---
name: computational-geometry
description: Use this skill when working on 2D vector graphics, path operations, bezier curves, bounding boxes, compositing, or any geometric computation in a design engine or canvas application. Trigger on any task involving coordinate transforms, boolean path operations, curve fitting, clipping masks, or spatial layout.
---

# Computational Geometry for 2D Vector Engines

Mathematical foundations, coordinate conventions, and algorithmic patterns for 2D vector design engines (Figma/Illustrator-class applications). Violating these produces visually broken output.

---

## 1. Coordinate System Conventions

### The Cardinal Rule

**ALL node positions use top-left origin.** When `transform = { x: 100, y: 200 }`:
- The node's bounding box top-left corner is at world position (100, 200)
- This applies to ALL node types: rectangles, ellipses, circles, polygons, stars, paths, text, groups
- There are NO exceptions. Ellipses are NOT centered at their transform position.

### How Each Node Type Works

| Node Type | transform.x/y means | Local geometry | World bbox top-left |
|-----------|---------------------|---------------|-------------------|
| Rectangle | Top-left corner | (0,0) to (width, height) | (t.x, t.y) |
| Ellipse | Top-left of bbox | Oval from (0,0) to (2*radiusX, 2*radiusY) | (t.x, t.y) |
| Circle | Top-left of bbox | Same as ellipse with radiusX = radiusY | (t.x, t.y) |
| Polygon | Top-left of bbox | Vertices within (0,0) to (2*radius, 2*radius) | (t.x, t.y) |
| Star | Top-left of bbox | Vertices within (0,0) to (2*outerRadius, 2*outerRadius) | (t.x, t.y) |
| Path | Offset origin | Commands define local geometry; t.x/y offsets all points | (t.x + minX, t.y + minY) |
| Text | Top-left of text box | Paragraph laid out from (0,0) downward | (t.x, t.y) |
| Group | Group position | Children positioned relative to group | Recursive union of children + group offset |

### To Center an Element at (cx, cy)

```
For rectangle: transform.x = cx - width/2,  transform.y = cy - height/2
For ellipse:   transform.x = cx - radiusX,  transform.y = cy - radiusY
For circle:    transform.x = cx - radius,    transform.y = cy - radius
For polygon:   transform.x = cx - radius,    transform.y = cy - radius
For star:      transform.x = cx - outerR,    transform.y = cy - outerR
```

### The Transform Pipeline

Transforms are applied in this order by the renderer:
```
1. canvas.save()
2. canvas.translate(transform.x, transform.y)     // position
3. canvas.translate(pivotX, pivotY)                 // move to rotation center
4. canvas.rotate(transform.rotation)                // rotate
5. canvas.scale(transform.scaleX, transform.scaleY) // scale
6. canvas.skew(transform.skewX, transform.skewY)   // skew (radians)
7. canvas.translate(-pivotX, -pivotY)               // undo pivot
8. draw local geometry at (0, 0)
9. canvas.restore()
```

The pivot point is the center of the local bounding box: `(width/2, height/2)` for rects, `(radiusX, radiusY)` for ellipses, etc.

---

## 2. Bezier Curve Mathematics

### The Cubic Bezier

A cubic Bezier curve B(t) is defined by 4 control points P0, P1, P2, P3:
```
B(t) = (1-t)^3 * P0 + 3(1-t)^2 * t * P1 + 3(1-t) * t^2 * P2 + t^3 * P3
```
where t ranges from 0 to 1. B(0) = P0, B(1) = P3. The curve passes through the endpoints but generally NOT through P1, P2 (the control points).

### De Casteljau's Algorithm

To evaluate B(t) without computing the full polynomial:
```
P01 = lerp(P0, P1, t)
P12 = lerp(P1, P2, t)
P23 = lerp(P2, P3, t)
P012 = lerp(P01, P12, t)
P123 = lerp(P12, P23, t)
P0123 = lerp(P012, P123, t)  // This is B(t)
```

This also gives the tangent direction (P123 - P012) and can split the curve at t into two sub-curves.

### KAPPA: The Circle Approximation Constant

A quarter-circle arc of radius r is approximated by a cubic Bezier with:
```
KAPPA = (4 * (sqrt(2) - 1)) / 3 = 0.5522847498307936...
```

Control point distance from the endpoint = `r * KAPPA`.

A full circle requires 4 cubic Bezier segments (one per quadrant). Each segment has:
- Start: on the circle
- End: next quadrant point on the circle
- CP1: start + KAPPA * r in the tangent direction
- CP2: end - KAPPA * r in the tangent direction

**Maximum error:** ~0.027% of the radius. Visually imperceptible at any practical scale.

**Never truncate KAPPA.** Use the full computed value `(4 * (sqrt(2) - 1)) / 3`, not a hardcoded decimal. Truncated constants compound errors in nested operations (boolean ops, offset curves).

### Tight Bounding Box for Cubic Bezier

The **axis-aligned bounding box (AABB)** of a cubic Bezier is NOT the bounding box of its control points. Control points can extend far beyond the actual curve.

**Correct algorithm:** Find parameter values where the derivative equals zero (curve extremes):

```
B'(t) = 3[(1-t)^2(P1-P0) + 2(1-t)t(P2-P1) + t^2(P3-P2)]
```

Setting B'(t) = 0 for each axis gives a quadratic: `at^2 + bt + c = 0` where:
```
a = -P0 + 3*P1 - 3*P2 + P3
b = 2*P0 - 4*P1 + 2*P2
c = -P0 + P1
```

Solve via quadratic formula. Keep only real roots where 0 < t < 1. Evaluate B(t) at those roots plus t=0 and t=1. The min/max of all evaluated points = the tight AABB for that axis.

For **quadratic Bezier** (3 control points), B'(t) = 0 is linear:
```
t = (P0 - P1) / (P0 - 2*P1 + P2)
```

**Why this matters:** The control-point-hull approach (just taking min/max of all control points) can overestimate by 20%+ for S-curves and loops. This causes incorrect alignment, snap detection, and spatial relationship computation.

### Curve Splitting (Subdivision)

To split a cubic at parameter t, use de Casteljau:
- Left sub-curve: P0, P01, P012, P0123
- Right sub-curve: P0123, P123, P23, P3

This is exact (no approximation). Used in:
- Boolean operations (split at intersection points)
- Path editing (insert point on curve)
- Adaptive rendering (flatten to polylines within tolerance)

### Curve-Curve Intersection

Finding where two Bezier curves intersect is hard. Approaches:
1. **Bezier clipping** (most practical): Recursively subdivide both curves, discard segments whose bounding boxes don't overlap. Converges quickly for transversal intersections.
2. **Implicitization**: Convert one curve to implicit form, substitute the other. Produces a polynomial whose roots are intersection parameters.
3. **Subdivision + Newton refinement**: Binary search to tolerance, then Newton's method for exact parameter.

Paper.js uses approach 1 (Bezier clipping). This is the recommended approach for a 2D vector engine.

---

## 3. Boolean Operations on Paths

### The Problem

Boolean operations (union, subtract, intersect, xor) on paths with Bezier curves require:
1. Finding all intersection points between the two paths
2. Splitting both paths at intersection points
3. Classifying each segment as "inside" or "outside" the other path
4. Tracing the correct segments to build the result path

### Implementation: Clipper2 Pipeline

The recommended approach uses **Clipper2** for robust polygon boolean operations. The pipeline is:

```
PathCommand[] -> flatten beziers to polylines -> Clipper2 boolean -> polylineToCommands()
```

**Step-by-step:**
1. Convert each target node to a Path representation
2. Extract PathCommand[] (moveTo, lineTo, cubicTo, close)
3. Flatten all bezier curves to polyline contours via adaptive subdivision
4. Apply each node's transform to the flattened points (world-space coordinates for Clipper2)
5. Run Clipper2 boolean operation with `FillRule.NonZero`
6. Convert result contours back to PathCommand[]
7. Create a new path node, inherit fills/strokes from the first target, remove originals

**Supported operations:**
| Operation | Clipper2 function | Description |
|-----------|------------------|-------------|
| `union` | `Clipper.union()` | Merge all shapes into one |
| `subtract` | `Clipper.difference()` | Remove clip from subject |
| `intersect` | `Clipper.intersect()` | Keep only overlapping area |
| `xor` | `Clipper.xor()` | Keep only non-overlapping areas |

**Multi-shape support:** When more than 2 targets are provided, operations are applied sequentially -- first shape is the initial subject, each subsequent shape is clipped against the accumulated result.

### Bezier Flattening (Adaptive De Casteljau Subdivision)

Converts PathCommand[] containing bezier curves into polyline contours suitable for Clipper2.

**Algorithm:** Adaptive subdivision using De Casteljau's algorithm at t=0.5. At each level, the **flatness** of the cubic segment is tested -- if the maximum perpendicular distance from the control points to the line segment P0-P3 is below the tolerance, the endpoint is emitted directly. Otherwise, the curve is split in half and each half is recursively flattened.

**Recommended constants:**
- `DEFAULT_FLATTEN_TOLERANCE = 0.5` (pixels) -- maximum allowed deviation from the true curve
- `MAX_SUBDIVISION_DEPTH = 16` -- depth limit (2^16 = 65536 segments maximum per curve)
- Tolerance is squared internally (`toleranceSq = tolerance * tolerance`) for comparison without sqrt

**Flatness test for cubics:**
```
distance1 = abs((p1x - p0x) * dy - (p1y - p0y) * dx)  // perpendicular distance of CP1 to P0-P3 line
distance2 = abs((p2x - p0x) * dy - (p2y - p0y) * dx)  // perpendicular distance of CP2 to P0-P3 line
flatness = max(distance1, distance2)^2 / (dx^2 + dy^2) // normalized squared distance
```

**Quadratic bezier flattening** uses the same adaptive approach but with a single control point and correspondingly simpler subdivision.

**Contour handling:** Each `moveTo` starts a new contour. `close` commands finalize the current contour. Clipper2 auto-closes polygons internally.

**Safety:** All recursive subdivision algorithms MUST include a maximum recursion depth parameter. Unbounded recursion on degenerate input causes stack overflow.

### Polyline-to-Commands Conversion

Converts Clipper2 result contours back to PathCommand[]. Emits `moveTo` + `lineTo` + `close` sequences (polyline output). For smooth curve results, use curve fitting (Schneider algorithm) on the output to refit cubic beziers through the polyline points.

---

## 4. Bounding Box Computation

### World-Space AABB

For any node, the world-space axis-aligned bounding box (AABB) is:

```typescript
function worldAABB(node): { x, y, width, height } {
  // Step 1: Get local bbox
  const local = localBBox(node);  // depends on node type

  // Step 2: Apply transform
  // For unrotated, unscaled nodes: simple offset
  if (node.transform.rotation === 0 && node.transform.scaleX === 1 && node.transform.scaleY === 1) {
    return { x: node.transform.x + local.x, y: node.transform.y + local.y,
             width: local.width, height: local.height };
  }

  // Step 3: For rotated/scaled, use fast AABB formula
  const hw = local.width / 2, hh = local.height / 2;
  const cos = Math.abs(Math.cos(rotation)), sin = Math.abs(Math.sin(rotation));
  const dx = hw * cos + hh * sin;
  const dy = hw * sin + hh * cos;
  const cx = transform.x + local.x + hw, cy = transform.y + local.y + hh;
  return { x: cx - dx, y: cy - dy, width: 2 * dx, height: 2 * dy };
}
```

### Group Bounding Boxes

A group's AABB is the union of its children's world-space AABBs, PLUS the group's own transform offset:

```
groupBox.x = group.transform.x + min(child.box.x for all children)
groupBox.y = group.transform.y + min(child.box.y for all children)
groupBox.width = max(child.box.x + child.box.width) - min(child.box.x)
groupBox.height = max(child.box.y + child.box.height) - min(child.box.y)
```

**If children store LOCAL coordinates** (relative to parent), the group transform shifts the entire children union. If children store WORLD coordinates, the group transform is NOT added.

### Text Bounding Boxes

Never estimate text width as `content.length * fontSize * factor`. This ignores:
- Variable-width characters (W vs i)
- Kerning pairs (AV, To, etc.)
- Ligatures (fi, fl, ffi)
- Font metrics (ascent, descent, leading)

Always use the text layout engine's actual measurements:
```
paragraph.layout(maxWidth);
width = paragraph.getLongestLine();
height = paragraph.getHeight();
```

---

## 5. Path Representation

### SVG Path Commands

The SVG path `d` attribute uses these commands:

| Command | Parameters | Description |
|---------|-----------|-------------|
| M x y | moveTo | Start new subpath |
| L x y | lineTo | Straight line |
| H x | horizontal | Horizontal line |
| V y | vertical | Vertical line |
| C x1 y1 x2 y2 x y | cubicTo | Cubic Bezier (2 control points) |
| S x2 y2 x y | smoothCubicTo | Smooth cubic (reflected CP1) |
| Q cx cy x y | quadTo | Quadratic Bezier (1 control point) |
| T x y | smoothQuadTo | Smooth quadratic (reflected CP) |
| A rx ry rot large sweep x y | arcTo | Elliptical arc |
| Z | closePath | Close subpath |

Lowercase variants (m, l, c, etc.) use **relative** coordinates (offset from current point).

### Arc-to-Cubic Conversion

SVG arcs (A command) are converted to cubic Bezier approximations for internal representation. The standard approach:
1. Convert endpoint parameterization to center parameterization (SVG spec appendix)
2. Split the arc into segments of at most 90 degrees
3. Approximate each segment with a cubic Bezier using KAPPA-derived control points

### Path Winding and Fill Rules

- **NonZero (default):** A point is "inside" if the winding number is non-zero. Overlapping clockwise contours accumulate.
- **EvenOdd:** A point is "inside" if a ray from it crosses an odd number of path edges. Overlapping contours toggle between inside/outside.

EvenOdd is useful for "hollow" shapes -- the inner contour of a ring is counter-clockwise, so the center is "outside" (hollow).

---

## 6. Compositing and Blending

### Porter-Duff Operators

The 12 Porter-Duff compositing operations define how source (S) and destination (D) pixels combine. Each pixel has color (c) and alpha (a).

Most relevant for a design engine:

| Operator | Formula (alpha) | Use |
|----------|----------------|-----|
| Source Over | aS + aD(1 - aS) | Default layer compositing |
| Source In | aS * aD | Masking/clipping |
| Source Out | aS * (1 - aD) | Knockout |
| Destination Over | aD + aS(1 - aD) | Paint behind |

**Linear vs sRGB blending:** Alpha blending MUST be performed in linear color space, not sRGB. Blending in sRGB produces visible dark halos around semi-transparent edges. Convert sRGB -> linear, blend, convert back.

### Blend Modes

Beyond Porter-Duff, blend modes modify how colors interact:
- **Multiply:** `result = S * D` -- darkens, used for shadows
- **Screen:** `result = 1 - (1-S)(1-D)` -- lightens, used for highlights
- **Overlay:** Multiply if D < 0.5, Screen if D >= 0.5 -- adds contrast

---

## 7. Curve Fitting (Schneider Algorithm)

Converts rough polyline points into smooth cubic bezier path commands. This is the inverse of bezier flattening -- it takes polyline output (e.g., from boolean ops) and produces smooth curves.

### Algorithm

The **Schneider curve-fitting algorithm**:
1. Computes tangent directions at endpoints
2. Iteratively fits a cubic bezier to the point sequence
3. If error exceeds tolerance, splits at the worst point and fits each half recursively
4. Converges to a minimal set of cubic beziers that approximate the polyline within tolerance

### Corner Detection

Before fitting, detect sharp turns in the polyline where the angle formed by three consecutive points is below a threshold. At these corners, the polyline is split into independent segments, each fitted separately. This preserves G0 continuity at corners (positional continuity, not tangent continuity).

**Algorithm:** For each interior point, compute the angle between incoming and outgoing vectors using `atan2(|cross|, dot)`. If the angle is below the corner threshold, mark as a corner.

### Recommended Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `maxError` | 2.5 | Maximum allowed deviation from input points (pixels) |
| `cornerThreshold` | 60 | Angle in degrees below which a point is treated as a sharp corner |
| `closed` | false | When true, appends first point to close the loop and emits a `close` command |

### Segment Continuity

When multiple segments are produced (due to corner splitting), only the first segment emits a `moveTo`. Subsequent segments skip their `moveTo` since the previous segment already ended at the shared corner point, maintaining path continuity.

---

## 8. Clipping Masks

### How Clipping Works

Groups can have a `clipPathId` property referencing a shape/path node. When set, the renderer clips all children of the group to the clip shape's outline.

**Allowed clip sources:** rectangle, ellipse, polygon, star, line, path. Text and group nodes should NOT be used as clip sources (convert text to path first).

### Renderer Pipeline

To apply a clip before rendering group children:

1. Look up the clip node by ID. Skip silently if node was deleted or is non-shape type.
2. Convert clip node to a path representation
3. Build the full affine transform matrix matching the canonical pipeline:
   ```
   translate(pos) * translate(pivot) * rotate * scale * skew * translate(-pivot)
   ```
4. Pivot is computed from the node's local bounds center
5. Apply the transformed path as a clip (intersect mode, anti-aliased)
6. Properly clean up all intermediate objects

**Key detail:** The clip node is NOT hidden automatically. Its own fills/strokes still render. Set opacity to 0 or remove fills if you want it invisible.

### SVG Export

For SVG export, clipping masks produce `<clipPath>` elements in `<defs>`:
1. Groups with a clip path are registered during def collection
2. The clip node's shape is serialized inside a `<clipPath id="clip-{groupId}">` element with its transform
3. The group element receives `clip-path="url(#clip-{groupId})"` attribute

---

## 9. Optical Spacing Corrections

### The Problem

A circle inscribed in its bounding box has ~21% of the bbox area as empty corners. When placing a circle 20px below a rectangle, the visual gap appears larger than 20px because the circle's curvature recedes from the bbox edge.

### Correction Factors

| Node Type | Factor | Reduction | Rationale |
|-----------|--------|-----------|-----------|
| `ellipse` | 0.82 | ~18% | Curve recedes from bbox edge |
| `star` | 0.85 | ~15% | Pointy outer vertices |
| `path` | 0.88 | ~12% | Average for organic shapes |
| `polygon` | 0.90 | ~10% | Pointed vertices |
| `text` | 0.94 | ~6% | Built-in line spacing |
| `rectangle`, `line`, `group` | 1.0 | 0% | Box-filling shapes |

### Formula

```
combinedFactor = (factorA + factorB) / 2
adjustedGap = rawGap * combinedFactor
```

The combined factor averages the two shapes' factors. Two rectangles = no correction. Two ellipses = 0.82x gap. Rectangle + ellipse = 0.91x gap.

**Not applied when:** anchor is center-based, or gap is 0.

---

## 10. Common Mistakes

1. **Assuming ellipse position is center.** It's top-left of the bounding box.
2. **Not accounting for path offset in layout ops.** For path nodes, `box.x != transform.x`. Always compute the offset.
3. **Guessing text dimensions.** Use the text layout engine for actual width/height before positioning.
4. **Trusting control-point bounding boxes.** Bezier control points can extend far beyond the curve. Use tight AABB computation (B'(t)=0 roots).
5. **Ignoring rotation when computing bounds.** A 45-degree rotated 100x100 square has an AABB of ~141x141.
6. **Blending in sRGB color space.** Always blend in linear space to avoid dark halos.
7. **Forgetting to refit curves after boolean ops.** Boolean ops via Clipper2 output polyline segments. Use curve fitting if smooth curves are needed.
8. **Using text as a clip source.** Convert to path outlines first.
9. **Unbounded recursion in subdivision.** Always include a max depth parameter.

---

## 11. Key References

| Resource | What it covers | Format |
|----------|---------------|--------|
| **"A Primer on Bezier Curves"** -- Pomax | Bezier math, KAPPA, tight bbox, intersection, offset curves | Free online (pomax.github.io/bezierinfo) |
| **Paper.js** `PathItem.Boolean.js` | Bezier boolean ops in JavaScript | Open source (github.com/paperjs/paper.js) |
| **Clipper2** | Polygon boolean ops (Vatti algorithm) | Open source (github.com/AngusJohnson/Clipper2) |
| **fit-curve** | Schneider curve-fitting algorithm | npm (github.com/niceDev0908/fit-curve) |
| **kurbo** | Mathematically rigorous 2D curve library (Rust) | Open source (github.com/linebender/kurbo) |
| **"Computational Geometry in C"** -- O'Rourke | Polygon boolean ops, point-in-polygon, convex hull | Textbook (code free at cs.smith.edu) |
| **"The NURBS Book"** -- Piegl & Tiller | Bezier/B-spline theory, curve fitting | Textbook (Springer) |
| **SVG 2 Spec** -- W3C | Path data syntax, fill rules, gradients, transforms | Free (w3.org/TR/SVG2) |
| **Skia** `src/pathops/` | Production bezier boolean operations | Open source (skia.org) |
| **Porter-Duff 1984 paper** | Compositing operators | Free paper |
| **"Fonts & Encodings"** -- Haralambous | OpenType internals, kerning, ligatures | Textbook (O'Reilly) |
