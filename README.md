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
- **Culture Filtering**: Filter by archaeological culture with multi-select dropdown
- **Cascading Filters**: Available cultures update based on date range selection
- **Color by Age**: Color ramp visualization of temporal distribution (viridis, plasma, spectral, and more)
- **Color by Culture**: Categorical coloring by archaeological culture
- **Multiple Tile Layers**: OpenStreetMap, OpenTopoMap, Humanitarian OSM
- **Collapsible Sidebar**: Toggle the filter panel for more map space

## Architecture

ArcheoGeneticMap uses a **thin client** architecture where filtering, color assignment, and data analysis happen server-side. The frontend is a minimal display layer that:

- Fetches configuration from `/api/config` on load
- Sends filter requests to `/api/query`
- Renders pre-colored features on the map

This design keeps logic in Julia, makes the system easier to test, and scales well as new filters are added.

## API Endpoints

| Path | Method | Description |
|------|--------|-------------|
| `/` | GET | Main map with OpenStreetMap tiles |
| `/topo` | GET | OpenTopoMap tiles (terrain) |
| `/humanitarian` | GET | Humanitarian OSM tiles |
| `/api/config` | GET | Frontend configuration (color ramps, defaults, initial statistics) |
| `/api/query` | POST | Filter and retrieve samples with colors assigned |
| `/api/samples` | GET | Raw GeoJSON data (legacy) |
| `/health` | GET | Server health check |

### Query API

```bash
# Example query request
curl -X POST http://localhost:8000/api/query \
  -H "Content-Type: application/json" \
  -d '{
    "dateMin": 5000,
    "dateMax": 10000,
    "includeUndated": true,
    "cultureFilter": {"mode": "all", "selected": []},
    "includeNoCulture": true,
    "colorBy": "age",
    "colorRamp": "viridis"
  }'
```

Response includes:
- `features`: GeoJSON features with `_color` property pre-assigned
- `meta`: Counts, available cultures (for cascading filters), date statistics

## Module Structure

```
ArcheoGeneticMap/
├── Project.toml              # Package dependencies
├── README.md                 # This file
├── data/                     # GeoPackage files to serve
├── src/
│   ├── ArcheoGeneticMap.jl   # Main module entry point
│   ├── config.jl             # Configuration constants
│   ├── types.jl              # Data structures (MapBounds, FilterRequest, etc.)
│   ├── io.jl                 # GeoPackage reading
│   ├── geometry.jl           # Spatial calculations
│   ├── colors.jl             # Color ramp definitions and interpolation
│   ├── filters.jl            # Filter application logic
│   ├── analysis.jl           # Statistics and cascading filter options
│   ├── query.jl              # Query orchestration
│   ├── server.jl             # Genie routes and API endpoints
│   └── templates/
│       ├── templates.jl      # Template loader and JS concatenation
│       ├── map_base.html     # HTML shell with Alpine.js bindings
│       ├── map_styles.css    # All CSS styling
│       ├── piecewise_scale.js # Slider scale with outlier compression
│       ├── popup_builder.js  # Popup content builder
│       └── map_app.js        # Alpine.js controller + Leaflet integration
├── bin/
│   └── run_server.jl         # CLI entry point
└── test/
    └── runtests.jl           # Unit tests
```

### Load Order

**Julia:** `config.jl` → `types.jl` → `io.jl` → `colors.jl` → `geometry.jl` → `analysis.jl` → `filters.jl` → `query.jl` → `templates.jl` → `server.jl`

**JavaScript:** `piecewise_scale.js` → `popup_builder.js` → `map_app.js`

## Configuration

Configuration is centralized in Julia and served to the frontend via `/api/config`.

### Julia Configuration (`config.jl`)

```julia
# Map display defaults
DEFAULT_PADDING = 5.0          # degrees around data bounds
DEFAULT_ZOOM = 6               # initial zoom level
DEFAULT_POINT_COLOR = "#e41a1c"
DEFAULT_POINT_RADIUS = 4

# Date range defaults (when no dated samples exist)
DEFAULT_MIN_AGE = 0.0
DEFAULT_MAX_AGE = 50000.0

# Tile layer defaults
DEFAULT_TILE_URL = "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
DEFAULT_TILE_ATTRIBUTION = "© OpenStreetMap contributors"
```

### Color Ramps (`colors.jl`)

Color ramps are defined server-side and served to the frontend:

```julia
const COLOR_RAMPS = Dict{String, ColorRamp}(
    "viridis" => ColorRamp("viridis", ["#440154", ...], "Viridis (purple → yellow)"),
    "plasma" => ColorRamp("plasma", [...], "Plasma (purple → orange)"),
    # ...
)
```

To add a new color ramp, add it to `COLOR_RAMPS` in `colors.jl`.

## Customization

### Using Tile Presets

```julia
# Use a preset
settings = MapSettings(:topo)

# Or customize
settings = MapSettings(
    padding = 2.0,
    initial_zoom = 8,
    point_color = "#0000ff",
    point_radius = 8
)

serve_map("data/samples.gpkg", settings=settings)
```

### Programmatic Query Processing

```julia
using ArcheoGeneticMap

# Load data
geojson = read_geopackage("data/samples.gpkg")

# Create a filter request
request = FilterRequest(
    date_min = 5000.0,
    date_max = 10000.0,
    culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
    color_by = :age,
    color_ramp = "viridis"
)

# Process query
response = process_query(geojson, request)

# Access results
println("Filtered: $(response.meta.filtered_count) samples")
println("Available cultures: $(response.meta.available_cultures)")
```

## Development

### Running Tests

```bash
julia test/runtests.jl
```

### Template Development

Templates are cached by default. During development, call `clear_template_cache()` to pick up changes without restarting the server.

The frontend JavaScript is minimal - most logic lives server-side. The JS modules handle:

| File | Purpose |
|------|---------|
| `piecewise_scale.js` | Slider-to-value conversion for outlier compression |
| `popup_builder.js` | HTML popup generation for map markers |
| `map_app.js` | Alpine.js state management, API calls, Leaflet rendering |

## Data Format

ArcheoGeneticMap expects GeoPackage files with point geometry and these attribute columns:

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `sample_id` | String | Yes | Unique identifier |
| `y_haplogroup` | String | No | Y-chromosome haplogroup |
| `mtdna` | String | No | Mitochondrial DNA haplogroup |
| `culture` | String | No | Archaeological culture |
| `average_age_calbp` | Float | No | Calibrated age in years BP |

## Roadmap

- [x] Color by age with selectable color ramps
- [x] Piecewise slider scaling for better outlier handling
- [x] Centralized configuration files
- [x] Server-side percentile calculation
- [x] First major reorganization of code
- [x] Culture filter and color coding 
- [x] Second major reorganization (thin client architecture)
- [x] Cascading filters (cultures update based on date range)
- [x] Y-haplogroup filter and color coding
- [x] mtDNA filter and color coding
- [ ] integrated geopackage maker
- [ ] haplotree controls
- [ ] Docker build and runtime tools
- [ ] Performance and scalability 
    - [ ] vector tiles  
    - [ ] dynamic clustering
    - [ ] progressive loading
- [ ] Refine popups
- [ ] Display customization
    - [ ] Marker radius customization
    - [ ] Basemap layer customization
- [ ] Nice to have data management
    - [ ] Export filtered dataset
    - [ ] URL state persistence
