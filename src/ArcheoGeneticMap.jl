"""
    ArcheoGeneticMap

Archaeological sample visualization on interactive web maps.

# Quick Start

```julia
using ArcheoGeneticMap
serve_map("samples.gpkg")
```

Then open http://localhost:8000 in your browser.

# Module Structure

- `Config`: Centralized configuration constants
- `Types`: Core data structures (MapBounds, MapSettings, MapConfig, FilterRequest, etc.)
- `IO`: GeoPackage file reading
- `Geometry`: Spatial calculations (bounds, center)
- `Colors`: Color ramp definitions and interpolation
- `Filters`: Filter application logic
- `Analysis`: Statistical analysis and cascading filter options
- `Query`: Orchestration layer for processing queries
- `Templates`: HTML/CSS/JS template rendering
- `Server`: Genie web server and routes

# Tile Presets

Use preset tile layers with `MapSettings(:preset_name)`:
- `:osm` - OpenStreetMap (default)
- `:topo` - OpenTopoMap
- `:humanitarian` - Humanitarian OpenStreetMap
"""
module ArcheoGeneticMap

# =============================================================================
# Submodules - order matters for dependencies
# =============================================================================

# Config must come first (no dependencies, provides constants for other modules)
include("../config/map_config.jl")

# IO depends on nothing internal
include("io.jl")

# Types depends on Config
include("types.jl")

# Colors depends on Config and Types
include("colors.jl")

# Geometry depends on Config
include("geometry.jl")

# Analysis depends on Config and Types
include("analysis.jl")

# Filters depends on Types
include("filters.jl")

# Query depends on Filters, Analysis, Colors
include("query.jl")

# Templates depends on Types
include("templates/templates.jl")

# Server depends on everything
include("server.jl")

# =============================================================================
# Exports
# =============================================================================

# Core types
export MapBounds, MapSettings, MapConfig, DateStatistics, CultureStatistics
export TilePreset, TILE_PRESETS

# Query types
export ColorRamp, CultureFilter, FilterRequest, FilterMeta, QueryResponse

# Color exports
export COLOR_RAMPS, CULTURE_PALETTE
export interpolate_color, color_for_age, color_for_culture

# IO functions
export read_geopackage

# Geometry functions
export calculate_bounds, calculate_center

# Analysis functions
export calculate_date_range, calculate_date_statistics, calculate_culture_statistics
export compute_available_cultures, compute_available_date_range, build_filter_meta

# Filter functions
export apply_date_filter, apply_culture_filter, apply_filters

# Query functions
export process_query, assign_colors!

# Template functions
export render_map_html, clear_template_cache

# Server functions
export serve_map, start_server, setup_routes, configure_data_source

end # module
