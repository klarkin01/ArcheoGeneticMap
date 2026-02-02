# ArcheoGeneticMap

Archaeological and paleogenomic sample visualization on interactive web maps.

## Quick Start

```julia
# From Julia REPL
using Pkg
Pkg.activate("path/to/ArcheoGeneticMap")

using ArcheoGeneticMap
serve_map("data/samples.gpkg")
```

Or from the command line:

```bash
julia bin/run_server.jl data/samples.gpkg
```

Then open http://localhost:8000 in your browser.

## Features

- **Interactive Map**: Pan, zoom, and click on samples for details
- **Date Filtering**: Filter samples by calibrated BP date range with piecewise slider scaling for better control over outliers
- **Color by Age**: Optional color ramping to visualize temporal distribution (viridis, plasma, spectral, and more)
- **Multiple Tile Layers**: OpenStreetMap, OpenTopoMap, Humanitarian OSM
- **Collapsible Sidebar**: Toggle the filter panel for more map space

## URL Endpoints

| Path | Description |
|------|-------------|
| `/` | Main map with OpenStreetMap tiles |
| `/topo` | OpenTopoMap tiles (terrain) |
| `/humanitarian` | Humanitarian OSM tiles |
| `/api/samples` | Raw GeoJSON data |
| `/health` | Server health check |

## Module Structure

```
ArcheoGeneticMap/
├── Project.toml              # Package dependencies
├── README.md                 # Usage documentation
├── data/                     # GeoPackage files to serve
│   └── (samples.gpkg)
├── src/
│   ├── ArcheoGeneticMap.jl   # Main module entry point
│   ├── config.jl             # Julia configuration constants
│   ├── types.jl              # Data structures (MapBounds, MapSettings, etc.)
│   ├── io.jl                 # GeoPackage reading
│   ├── geometry.jl           # Spatial calculations
│   ├── server.jl             # Genie routes and server
│   └── templates/
│       ├── templates.jl      # Template loader and JS concatenation
│       ├── map_base.html     # HTML shell with Alpine.js bindings
│       ├── map_styles.css    # All CSS styling
│       ├── config.js         # JavaScript configuration (color ramps, slider settings)
│       ├── color_ramps.js    # Color interpolation utilities
│       ├── piecewise_scale.js # Slider scale with outlier compression
│       ├── popup_builder.js  # Configurable popup content builder
│       └── map_app.js        # Main Alpine.js controller + Leaflet integration
├── bin/
│   └── run_server.jl         # CLI entry point
└── test/
    └── runtests.jl           # Unit tests
```

### Load Order

Modules are loaded in dependency order to ensure configuration is available where needed.

**Julia:** `config.jl` → `types.jl` → `io.jl` → `geometry.jl` → `templates.jl` → `server.jl`

**JavaScript:** `config.js` → `color_ramps.js` → `piecewise_scale.js` → `popup_builder.js` → `map_app.js`

## Configuration

All configuration constants are centralized in two files for easy maintenance:

### Julia Configuration (`config.jl`)

```julia
# Map display defaults
DEFAULT_PADDING = 5.0          # degrees around data bounds
DEFAULT_ZOOM = 6               # initial zoom level
DEFAULT_POINT_COLOR = "#e41a1c"
DEFAULT_POINT_RADIUS = 6

# Date range defaults (when no dated samples exist)
DEFAULT_MIN_AGE = 0.0
DEFAULT_MAX_AGE = 50000.0

# Tile layer defaults
DEFAULT_TILE_URL = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
DEFAULT_TILE_ATTRIBUTION = "© OpenStreetMap contributors"
```

### JavaScript Configuration (`config.js`)

```javascript
Config.colorRamps      // Color ramp definitions (viridis, plasma, etc.)
Config.colorRampLabels // Human-readable labels for dropdowns
Config.slider          // Slider range (min: 0, max: 1000) and segment breakpoints
Config.defaults        // Default filter values (colorRamp, includeUndated, etc.)
```

To add a new color ramp, simply add it to `Config.colorRamps` and `Config.colorRampLabels` in `config.js`.

### Server-Provided Date Statistics

The server calculates date range statistics (min, max, p2, p98 percentiles) and passes them to the frontend via the `dateRange` config object. This enables the piecewise slider to compress outliers without client-side recalculation:

```javascript
// Available in window.ArcheoGeneticMap.config.dateRange
{
    min: 250,      // Absolute minimum age (youngest sample)
    max: 45000,    // Absolute maximum age (oldest sample)  
    p2: 1200,      // 2nd percentile (for slider left segment)
    p98: 12000     // 98th percentile (for slider right segment)
}
```

## Customization

### Using Tile Presets

```julia
# Use a preset
settings = MapSettings(:topo)

# Or customize
settings = MapSettings(
    padding = 2.0,           # degrees around data bounds
    initial_zoom = 8,
    point_color = "#0000ff",
    point_radius = 8
)

serve_map("data/samples.gpkg", settings=settings)
```

### Programmatic Usage

```julia
using ArcheoGeneticMap

# Load data
geojson = read_geopackage("data/samples.gpkg")

# Calculate bounds and center
bounds = calculate_bounds(geojson, 5.0)
center_lat, center_lon = calculate_center(bounds)
min_age, max_age = calculate_date_range(geojson)

# Render HTML (useful for embedding or custom servers)
settings = MapSettings()
config = MapConfig(center_lat, center_lon, 6, min_age, max_age, settings)
html = render_map_html(config)
```

## Development

### Running Tests

```bash
julia test/runtests.jl
```

### Template Development

The frontend JavaScript is split into focused modules:

| File | Purpose |
|------|---------|
| `config.js` | Centralized configuration (color ramps, slider settings, defaults) |
| `color_ramps.js` | Color interpolation utilities (uses Config for ramp definitions) |
| `piecewise_scale.js` | Bidirectional slider-to-value conversion (uses Config for breakpoints) |
| `popup_builder.js` | Configurable HTML popup generation for map markers |
| `map_app.js` | Main application logic (Alpine.js state management + Leaflet map) |

These modules are concatenated by `templates.jl` before injection into the HTML. Each module uses the IIFE pattern to avoid global namespace pollution while remaining compatible with browsers without a build step.

Templates are cached by default. During development, call `clear_template_cache()` to pick up changes without restarting the server.

### Reusing JavaScript Modules

The modules are designed for reuse when adding new filters:

```javascript
// Create a piecewise scale for any numeric variable
const scale = PiecewiseScale.fromValues(myDataArray);
const sliderPos = scale.toSlider(dataValue);
const dataValue = scale.toValue(sliderPos);

// Color any value using a ramp
const color = ColorRamps.forValue(value, min, max, 'viridis', '#gray');

// Get CSS gradient for legend display
const gradient = ColorRamps.gradient('plasma');

// Build popups with custom field configuration
const html = PopupBuilder.build(props, [
    { key: 'sample_id', label: 'Sample', bold: true },
    { key: 'age', label: 'Age', suffix: ' BP' }
]);
```

## Data Format

ArcheoGeneticMap expects GeoPackage files with point geometry and these attribute columns:

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `sample_id` | String | Yes | Unique identifier |
| `y_haplogroup` | String | No | Y-chromosome haplogroup |
| `mtdna` | String | No | Mitochondrial DNA haplogroup |
| `culture` | String | No | Archaeological culture |
| `average_age_calbp` | Float | No | Calibrated age in years BP |

Use `gpkg_maker_09.jl` to convert CSV files to this format.

## Roadmap

- [x] Color by age with selectable color ramps
- [x] Piecewise slider scaling for better outlier handling
- [x] Centralized configuration files
- [x] Server-side percentile calculation
- [x] First major reorganization of code
- [ ] Culture filter and color coding 
- [ ] Y-haplogroup filter and color coding
- [ ] mtDNA filter and color coding
- [ ] Second major reorganization of code
- [ ] Performance and scalability 
    - [ ] vector tiles  
    - [ ] dynamic clustering
    - [ ] progressive loading
- [ ] Clean up and package gpkg_maker
- [ ] Refine popups
- [ ] Display customization
    - [ ] Marker radius customization
    - [ ] Basemap layer customization
- [ ] Nice to have data management
    - [ ] Export filtered dataset
    - [ ] URL state persistence
- [ ] Extreme reaches
    - [ ] Spatial statistics
    - [ ] Simulations
