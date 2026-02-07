"""
    ArcheoGeneticMap.Types

Core data structures for archaeological map visualization.
"""

# Import config constants (config.jl must be included before this file)
# Uses: DEFAULT_PADDING, DEFAULT_ZOOM, DEFAULT_POINT_COLOR, DEFAULT_POINT_RADIUS,
#       DEFAULT_TILE_URL, DEFAULT_TILE_ATTRIBUTION

export MapBounds, MapSettings, MapConfig, DateStatistics, CultureStatistics, TilePreset, TILE_PRESETS
export ColorRamp, CultureFilter, FilterRequest, FilterMeta, QueryResponse

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
        "Ã‚Â© OpenStreetMap contributors"
    ),
    :topo => TilePreset(
        "OpenTopoMap", 
        "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
        "Ã‚Â© OpenStreetMap contributors, Ã‚Â© OpenTopoMap"
    ),
    :humanitarian => TilePreset(
        "Humanitarian",
        "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
        "Ã‚Â© OpenStreetMap contributors"
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

# =============================================================================
# Color Types
# =============================================================================

"""
    ColorRamp

Definition of a color ramp for data visualization.

# Fields
- `name`: Identifier used in API requests (e.g., "viridis")
- `colors`: Array of hex colors from low to high values
- `label`: Human-readable label for UI display
"""
struct ColorRamp
    name::String
    colors::Vector{String}
    label::String
end

# =============================================================================
# Filter/Query Types
# =============================================================================

"""
    CultureFilter

Specifies which cultures to include in the filter.

# Fields
- `selected`: Vector of culture names to include (empty = none selected)

The interpretation is:
- Empty array + include_no_culture=false → show nothing
- Empty array + include_no_culture=true → show only samples without culture
- Non-empty array → show selected cultures (+ no-culture samples if flag set)

# Examples
```julia
CultureFilter(String[])           # No cultures selected
CultureFilter(["Yamnaya"])        # Show only Yamnaya
CultureFilter(["Yamnaya", "Bell Beaker"])  # Show multiple cultures
```
"""
struct CultureFilter
    selected::Vector{String}
end

# Default constructor is already provided by the struct
# CultureFilter() creates an instance with an uninitialized selected field,
# so we need an explicit zero-arg constructor
CultureFilter() = CultureFilter(String[])

"""
    FilterRequest

Represents a filter request from the frontend.
All filter fields are optional - nothing means "no filter applied".

# Fields
- `date_min`: Minimum age in cal BP (nothing = no lower bound)
- `date_max`: Maximum age in cal BP (nothing = no upper bound)
- `include_undated`: Whether to include samples without dates
- `culture_filter`: Culture filter specification
- `include_no_culture`: Whether to include samples without culture data
- `color_by`: How to color markers (:age, :culture, or nothing for default)
- `color_ramp`: Name of color ramp to use (e.g., "viridis")
"""
struct FilterRequest
    date_min::Union{Float64, Nothing}
    date_max::Union{Float64, Nothing}
    include_undated::Bool
    culture_filter::CultureFilter
    include_no_culture::Bool
    color_by::Union{Symbol, Nothing}
    color_ramp::String
end

# Default constructor with sensible defaults
function FilterRequest(;
    date_min::Union{Float64, Nothing} = nothing,
    date_max::Union{Float64, Nothing} = nothing,
    include_undated::Bool = true,
    culture_filter::CultureFilter = CultureFilter(),
    include_no_culture::Bool = true,
    color_by::Union{Symbol, Nothing} = nothing,
    color_ramp::String = "viridis"
)
    FilterRequest(date_min, date_max, include_undated, culture_filter, include_no_culture, color_by, color_ramp)
end

"""
    FilterMeta

Metadata about filtered results and available options.
This drives what the UI can display for cascading filters.

# Fields
- `total_count`: Total number of samples in the dataset
- `filtered_count`: Number of samples after filtering
- `available_cultures`: Cultures available given current date filter
- `available_date_range`: Date range available given current culture filter
- `date_statistics`: Full date statistics for slider configuration
- `culture_legend`: Vector of (culture_name, color) pairs for legend display
"""
struct FilterMeta
    total_count::Int
    filtered_count::Int
    available_cultures::Vector{String}
    available_date_range::Tuple{Float64, Float64}
    date_statistics::DateStatistics
    culture_legend::Vector{Tuple{String, String}}
end

"""
    QueryResponse

Complete response to a filter query.

# Fields
- `features`: GeoJSON features with `_color` property added
- `meta`: Metadata about the results and available options
"""
struct QueryResponse
    features::Vector{Dict{String, Any}}
    meta::FilterMeta
end
