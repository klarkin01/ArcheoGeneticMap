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
- **Date Filtering**: Filter samples by calibrated BP date range
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
│   ├── ArcheoGeneticMap.jl          # Main module
│   ├── types.jl              # Data structures (MapBounds, MapSettings, etc.)
│   ├── io.jl                 # GeoPackage reading
│   ├── geometry.jl           # Spatial calculations
│   ├── server.jl             # Genie routes and server
│   └── templates/
│       ├── templates.jl      # Template loader
│       ├── map_base.html     # HTML shell
│       ├── map_styles.css    # All CSS
│       └── map_app.js        # Alpine.js + Leaflet app
├── bin/
│   └── run_server.jl         # CLI entry point
└── test/
    └── runtests.jl           # Unit tests
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

The frontend is split into three files for easy editing:

- `map_base.html` - HTML structure and Alpine.js bindings
- `map_styles.css` - All styling
- `map_app.js` - JavaScript logic (Alpine.js state + Leaflet map)

Templates are cached by default. During development, call `clear_template_cache()` 
to pick up changes without restarting the server.

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

- [ ] Culture filter with hierarchical grouping
- [ ] Y-haplogroup color coding
- [ ] mtDNA filter
- [ ] Marker clustering for large datasets
- [ ] Time animation slider
