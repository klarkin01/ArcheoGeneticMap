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

- `Types`: Core data structures (MapBounds, MapSettings, MapConfig)
- `IO`: GeoPackage file reading
- `Geometry`: Spatial calculations (bounds, center, date ranges)
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
# Dependencies
# =============================================================================

#using Reexport

# =============================================================================
# Submodules - order matters for dependencies
# =============================================================================

# Types must come first (no dependencies)
include("types.jl")

# IO depends on nothing internal
include("io.jl")

# Geometry depends on Types
include("geometry.jl")

# Templates depends on Types
include("templates/templates.jl")

# Server depends on everything
include("server.jl")

# =============================================================================
# Exports
# =============================================================================

# Re-export key types
export MapBounds, MapSettings, MapConfig, TilePreset, TILE_PRESETS

# Re-export IO functions
export read_geopackage

# Re-export geometry functions
export calculate_bounds, calculate_center, calculate_date_range

# Re-export template functions
export render_map_html, clear_template_cache

# Re-export server functions
export serve_map, start_server, setup_routes, configure_data_source

end # module
