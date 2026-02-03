"""
    ArcheoGeneticMap.Types

Core data structures for archaeological map visualization.
"""

# Import config constants (config.jl must be included before this file)
# Uses: DEFAULT_PADDING, DEFAULT_ZOOM, DEFAULT_POINT_COLOR, DEFAULT_POINT_RADIUS,
#       DEFAULT_TILE_URL, DEFAULT_TILE_ATTRIBUTION

export MapBounds, MapSettings, MapConfig, DateStatistics, CultureStatistics, TilePreset, TILE_PRESETS

"""
    MapBounds

Represents the geographic bounding box for map display.
"""
struct MapBounds
    min_lon::Float64
    max_lon::Float64
    min_lat::Float64
    max_lat::Float64
end

"""
    MapSettings

Configuration for map display and styling.

# Fields
- `padding`: Extra space around data bounds (degrees)
- `initial_zoom`: Starting zoom level (1-18)
- `point_color`: CSS color for markers
- `point_radius`: Marker radius in pixels
- `tile_url`: URL template for tile server
- `tile_attribution`: Attribution text for tiles
"""
struct MapSettings
    padding::Float64
    initial_zoom::Int
    point_color::String
    point_radius::Int
    tile_url::String
    tile_attribution::String
end

"""
    MapSettings(; kwargs...)

Construct MapSettings with keyword arguments and sensible defaults.
"""
function MapSettings(;
    padding::Float64 = DEFAULT_PADDING,
    initial_zoom::Int = DEFAULT_ZOOM,
    point_color::String = DEFAULT_POINT_COLOR,
    point_radius::Int = DEFAULT_POINT_RADIUS,
    tile_url::String = DEFAULT_TILE_URL,
    tile_attribution::String = DEFAULT_TILE_ATTRIBUTION
)
    MapSettings(padding, initial_zoom, point_color, point_radius, tile_url, tile_attribution)
end

"""
    TilePreset

Named tile layer configuration.
"""
struct TilePreset
    name::String
    url::String
    attribution::String
end

"""
Pre-configured tile layer options.
"""
const TILE_PRESETS = Dict{Symbol, TilePreset}(
    :osm => TilePreset(
        "OpenStreetMap",
        "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
        "Â© OpenStreetMap contributors"
    ),
    :topo => TilePreset(
        "OpenTopoMap", 
        "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
        "Â© OpenStreetMap contributors, Â© OpenTopoMap"
    ),
    :humanitarian => TilePreset(
        "Humanitarian",
        "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
        "Â© OpenStreetMap contributors"
    )
)

"""
    MapSettings(preset::Symbol; kwargs...)

Create MapSettings from a tile preset, with optional overrides.
"""
function MapSettings(preset::Symbol; kwargs...)
    tile = get(TILE_PRESETS, preset, TILE_PRESETS[:osm])
    MapSettings(;
        tile_url = tile.url,
        tile_attribution = tile.attribution,
        kwargs...
    )
end

"""
    DateStatistics

Statistics about the date range of samples, used for piecewise slider scaling.

# Fields
- `min`: Absolute minimum age (youngest sample)
- `max`: Absolute maximum age (oldest sample)
- `p2`: 2nd percentile age (for slider compression)
- `p98`: 98th percentile age (for slider compression)
"""
struct DateStatistics
    min::Float64
    max::Float64
    p2::Float64
    p98::Float64
end

"""
    CultureStatistics

Statistics about unique cultures in the dataset.
"""
struct CultureStatistics
    #unique_cultures::Int
    #culture_counts::Dict{String, Int}
    culture_names::Vector{String}
end

"""
    MapConfig

Complete configuration for rendering a map, including computed values.
Used to pass data from Julia to the template layer.
"""
struct MapConfig
    center_lat::Float64
    center_lon::Float64
    zoom::Int
    date_stats::DateStatistics
    culture_stats::CultureStatistics
    settings::MapSettings
end
