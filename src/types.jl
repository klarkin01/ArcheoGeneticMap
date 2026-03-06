"""
    ArcheoGeneticMap.Types

Core data structures for archaeological map visualization.
"""

# Import config constants (config.jl must be included before this file)
# Uses: DEFAULT_PADDING, DEFAULT_ZOOM, DEFAULT_POINT_COLOR, DEFAULT_POINT_RADIUS,
#       DEFAULT_TILE_URL, DEFAULT_TILE_ATTRIBUTION

export MapBounds, MapSettings, MapConfig, DateStatistics, CultureStatistics, TilePreset, TILE_PRESETS
export ColorRamp, AbstractSelectionFilter, CultureFilter, YHaplogroupFilter, MtdnaFilter, YHaplotreeFilter, FilterRequest, FilterMeta, QueryResponse
export is_missing_value, has_value, property_key

# =============================================================================
# Data Presence Helpers
# =============================================================================

"""
    is_missing_value(v) -> Bool

Return `true` when a property value should be treated as absent.
Covers the three ways a field can be "not there" in our GeoJSON properties:
- `nothing`  — field not present in the Dict
- `missing`  — field present but marked as SQL/DataFrame missing
- `""`       — field present but an empty string

Use this for all string fields (culture, haplogroup, path, etc.).
For numeric fields where `""` cannot occur, `nothing` and `missing` are
still handled correctly because the `== ""` branch is unreachable for non-strings.
"""
is_missing_value(v) = v === nothing || ismissing(v) || v == ""

"""
    has_value(v) -> Bool

Inverse of `is_missing_value`. Returns `true` when `v` is a real, non-empty value.
"""
has_value(v) = !is_missing_value(v)

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
        "© OpenStreetMap contributors"
    ),
    :topo => TilePreset(
        "OpenTopoMap", 
        "https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png",
        "© OpenStreetMap contributors, © OpenTopoMap"
    ),
    :humanitarian => TilePreset(
        "Humanitarian",
        "https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png",
        "© OpenStreetMap contributors"
    ),
    :dark => TilePreset(
        "CartoDB Dark Matter",
        "https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png",
        "© OpenStreetMap contributors, © CARTO"
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
    AbstractSelectionFilter

Abstract supertype for all selection-based filters.

All subtypes must have a `selected::Vector{String}` field and implement
`property_key(::MyFilterType)` returning the GeoJSON property key to filter on.

This enables `apply_filter` to dispatch on filter type and look up the correct
property key without any conditional logic.
"""
abstract type AbstractSelectionFilter end

"""
    property_key(filter::AbstractSelectionFilter) -> String

Return the GeoJSON property key that this filter operates on.
Implemented for each concrete filter type — this is the trait that drives
dispatch-based filter application.
"""
function property_key end

"""
    CultureFilter

Specifies which cultures to include in the filter.

# Fields
- `selected`: Vector of culture names to include (empty = none selected)

The interpretation is:
- Empty array + include_no_culture=false → show nothing
- Empty array + include_no_culture=true → show only samples without culture
- Non-empty array → show selected cultures (+ no-culture samples if flag set)
"""
struct CultureFilter <: AbstractSelectionFilter
    selected::Vector{String}
end

CultureFilter() = CultureFilter(String[])
property_key(::CultureFilter) = "culture"

"""
    YHaplogroupFilter

Specifies Y-haplogroup filtering with text search capability.

# Fields
- `search_text`: Text to filter haplogroup list (case-insensitive prefix match)
- `selected`: Vector of haplogroup names to include (empty = none selected)

The interpretation is:
- Empty array + include_no_y_haplogroup=false → show nothing
- Empty array + include_no_y_haplogroup=true → show only samples without Y-haplogroup
- Non-empty array → show selected haplogroups (+ no-haplogroup samples if flag set)

Mutually exclusive with YHaplotreeFilter — only one should be active at a time.
"""
struct YHaplogroupFilter <: AbstractSelectionFilter
    search_text::String
    selected::Vector{String}
end

YHaplogroupFilter() = YHaplogroupFilter("", String[])
property_key(::YHaplogroupFilter) = "y_haplogroup"

"""
    MtdnaFilter

Specifies mtDNA haplogroup filtering with text search capability.

# Fields
- `search_text`: Text to filter haplogroup list (case-insensitive prefix match)
- `selected`: Vector of mtDNA haplogroup names to include (empty = none selected)

The interpretation is:
- Empty array + include_no_mtdna=false → show nothing
- Empty array + include_no_mtdna=true → show only samples without mtDNA
- Non-empty array → show selected haplogroups (+ no-haplogroup samples if flag set)
"""
struct MtdnaFilter <: AbstractSelectionFilter
    search_text::String
    selected::Vector{String}
end

MtdnaFilter() = MtdnaFilter("", String[])
property_key(::MtdnaFilter) = "mtdna"

"""
    SourceFilter

Specifies which studies/sources to include in the filter.

# Fields
- `selected`: Vector of source names to include (empty = none selected)

The interpretation is:
- Empty array → show nothing
- Non-empty array → show selected sources
Samples with no source are always included (see `apply_filters`).
"""
struct SourceFilter <: AbstractSelectionFilter
    selected::Vector{String}
end

SourceFilter() = SourceFilter(String[])
property_key(::SourceFilter) = "source"

"""
    YHaplotreeFilter

Specifies Y-haplotree filtering by a list of token strings.

Each token is matched against the haplotree path (e.g. "R-M207>M173>M343>...")
by splitting on '>' and comparing each node token case-insensitively.
A sample passes if ANY token in `terms` exactly matches ANY node in its path.

# Fields
- `terms`: Vector of node strings to match (empty = no filter applied)

When active (non-empty terms), this filter is mutually exclusive with the
y_haplogroup filter — only one should be active at a time.
"""
struct YHaplotreeFilter
    terms::Vector{String}
end

# Default constructor
YHaplotreeFilter() = YHaplotreeFilter(String[])

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
- `y_haplogroup_filter`: Y-haplogroup filter specification (mutually exclusive with y_haplotree_filter)
- `include_no_y_haplogroup`: Whether to include samples without Y-haplogroup
- `mtdna_filter`: mtDNA haplogroup filter specification
- `include_no_mtdna`: Whether to include samples without mtDNA
- `y_haplotree_filter`: Y-haplotree token filter (mutually exclusive with y_haplogroup_filter)
- `source_filter`: Source/study filter specification
- `color_by`: How to color markers (:age, :culture, :y_haplogroup, :mtdna, :y_haplotree, or nothing)
- `color_ramp`: Name of color ramp to use for age coloring (e.g., "viridis")
- `culture_color_ramp`: Name of color ramp to use for culture coloring
- `y_haplogroup_color_ramp`: Name of color ramp to use for Y-haplogroup coloring
- `mtdna_color_ramp`: Name of color ramp to use for mtDNA coloring
- `y_haplotree_color_ramp`: Name of color ramp to use for Y-haplotree coloring
"""
struct FilterRequest
    date_min::Union{Float64, Nothing}
    date_max::Union{Float64, Nothing}
    include_undated::Bool
    culture_filter::CultureFilter
    include_no_culture::Bool
    y_haplogroup_filter::YHaplogroupFilter
    include_no_y_haplogroup::Bool
    mtdna_filter::MtdnaFilter
    include_no_mtdna::Bool
    y_haplotree_filter::YHaplotreeFilter
    source_filter::SourceFilter
    color_by::Union{Symbol, Nothing}
    color_ramp::String
    culture_color_ramp::String
    y_haplogroup_color_ramp::String
    mtdna_color_ramp::String
    y_haplotree_color_ramp::String
end

# Default constructor with sensible defaults
function FilterRequest(;
    date_min::Union{Float64, Nothing} = nothing,
    date_max::Union{Float64, Nothing} = nothing,
    include_undated::Bool = true,
    culture_filter::CultureFilter = CultureFilter(),
    include_no_culture::Bool = true,
    y_haplogroup_filter::YHaplogroupFilter = YHaplogroupFilter(),
    include_no_y_haplogroup::Bool = true,
    mtdna_filter::MtdnaFilter = MtdnaFilter(),
    include_no_mtdna::Bool = true,
    y_haplotree_filter::YHaplotreeFilter = YHaplotreeFilter(),
    source_filter::SourceFilter = SourceFilter(),
    color_by::Union{Symbol, Nothing} = nothing,
    color_ramp::String = DEFAULT_COLOR_RAMP,
    culture_color_ramp::String = DEFAULT_COLOR_RAMP,
    y_haplogroup_color_ramp::String = DEFAULT_COLOR_RAMP,
    mtdna_color_ramp::String = DEFAULT_COLOR_RAMP,
    y_haplotree_color_ramp::String = DEFAULT_COLOR_RAMP
)
    FilterRequest(
        date_min, date_max, include_undated,
        culture_filter, include_no_culture,
        y_haplogroup_filter, include_no_y_haplogroup,
        mtdna_filter, include_no_mtdna,
        y_haplotree_filter,
        source_filter,
        color_by, color_ramp,
        culture_color_ramp, y_haplogroup_color_ramp, mtdna_color_ramp,
        y_haplotree_color_ramp
    )
end

"""
    FilterMeta

Metadata about filtered results and available options.
This drives what the UI can display for cascading filters.

# Fields
- `total_count`: Total number of samples in the dataset
- `filtered_count`: Number of samples after filtering
- `available_cultures`: Cultures available given current filters
- `available_y_haplogroups`: Y-haplogroups available given current filters
- `available_mtdna`: mtDNA haplogroups available given current filters
- `available_sources`: Sources available given current filters
- `filtered_y_haplogroups`: Y-haplogroups after search text filtering
- `filtered_mtdna`: mtDNA haplogroups after search text filtering
- `available_date_range`: Date range available given current filters
- `date_statistics`: Full date statistics for slider configuration
- `culture_legend`: Vector of (culture_name, color) pairs for legend display
- `y_haplogroup_legend`: Vector of (haplogroup, color) pairs for legend display
- `mtdna_legend`: Vector of (haplogroup, color) pairs for legend display
- `y_haplotree_legend`: Vector of (term, color) pairs for legend display
"""
struct FilterMeta
    total_count::Int
    filtered_count::Int
    available_cultures::Vector{String}
    available_y_haplogroups::Vector{String}
    available_mtdna::Vector{String}
    available_sources::Vector{String}
    filtered_y_haplogroups::Vector{String}
    filtered_mtdna::Vector{String}
    available_date_range::Tuple{Float64, Float64}
    date_statistics::DateStatistics
    culture_legend::Vector{Tuple{String, String}}
    y_haplogroup_legend::Vector{Tuple{String, String}}
    mtdna_legend::Vector{Tuple{String, String}}
    y_haplotree_legend::Vector{Tuple{String, String}}
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
