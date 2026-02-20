"""
    ArcheoGeneticMap.Colors

Color ramp definitions and interpolation for data visualization.
This is the single source of truth for color configuration.
"""

export COLOR_RAMPS, CULTURE_PALETTE
export interpolate_color, color_for_age, color_for_culture, color_for_haplogroup, color_for_y_haplotree_term
export hex_to_rgb, rgb_to_hex

# =============================================================================
# Color Ramp Definitions
# =============================================================================

"""
Pre-defined color ramps for data visualization.
Each ramp is an array of hex colors from low to high values.
"""
const COLOR_RAMPS = Dict{String, ColorRamp}(
    "viridis" => ColorRamp(
        "viridis",
        ["#440154", "#482777", "#3e4a89", "#31688e", "#26838f",
         "#1f9d8a", "#6cce5a", "#b6de2b", "#fee825"],
        "Viridis (purple → yellow)"
    ),
    "plasma" => ColorRamp(
        "plasma",
        ["#0d0887", "#46039f", "#7201a8", "#9c179e", "#bd3786",
         "#d8576b", "#ed7953", "#fb9f3a", "#fdca26"],
        "Plasma (purple → orange)"
    ),
    "warm" => ColorRamp(
        "warm",
        ["#4575b4", "#74add1", "#abd9e9", "#e0f3f8", "#ffffbf",
         "#fee090", "#fdae61", "#f46d43", "#d73027"],
        "Warm (blue → red)"
    ),
    "cool" => ColorRamp(
        "cool",
        ["#d73027", "#f46d43", "#fdae61", "#fee090", "#ffffbf",
         "#e0f3f8", "#abd9e9", "#74add1", "#4575b4"],
        "Cool (red → blue)"
    ),
    "spectral" => ColorRamp(
        "spectral",
        ["#9e0142", "#d53e4f", "#f46d43", "#fdae61", "#fee08b",
         "#e6f598", "#abdda4", "#66c2a5", "#3288bd"],
        "Spectral (red → blue)"
    ),
    "turbo" => ColorRamp(
        "turbo",
        ["#30123b", "#4662d7", "#36aaf9", "#1ae4b6", "#72fe5e",
         "#c8ef34", "#fcce2e", "#f38b20", "#ca3e13"],
        "Turbo (rainbow)"
    )
)

"""
Color palette for categorical culture coloring.
DEPRECATED: Now using color ramps for categorical data.
Kept for backward compatibility.
"""
const CULTURE_PALETTE = [
    "#e41a1c", "#377eb8", "#4daf4a", "#984ea3", "#ff7f00",
    "#ffff33", "#a65628", "#f781bf", "#999999", "#66c2a5",
    "#fc8d62", "#8da0cb", "#e78ac3", "#a6d854", "#ffd92f",
    "#1b9e77", "#d95f02", "#7570b3", "#e7298a", "#66a61e"
]

# =============================================================================
# Color Conversion Utilities
# =============================================================================

"""
    hex_to_rgb(hex::String) -> Tuple{Int, Int, Int}

Convert a hex color string to RGB tuple.
Handles both "#RRGGBB" and "RRGGBB" formats.
"""
function hex_to_rgb(hex::String)
    hex = lstrip(hex, '#')
    if length(hex) != 6
        return (0, 0, 0)
    end
    r = parse(Int, hex[1:2], base=16)
    g = parse(Int, hex[3:4], base=16)
    b = parse(Int, hex[5:6], base=16)
    return (r, g, b)
end

"""
    rgb_to_hex(r::Int, g::Int, b::Int) -> String

Convert RGB values (0-255) to hex color string with # prefix.
"""
function rgb_to_hex(r::Int, g::Int, b::Int)
    return "#" * string(r, base=16, pad=2) * 
                 string(g, base=16, pad=2) * 
                 string(b, base=16, pad=2)
end

# =============================================================================
# Color Interpolation
# =============================================================================

"""
    interpolate_color(ramp::ColorRamp, t::Float64) -> String

Interpolate a color from a ramp based on normalized value t (0-1).
Returns a hex color string.
"""
function interpolate_color(ramp::ColorRamp, t::Float64)
    # Clamp t to [0, 1]
    t = clamp(t, 0.0, 1.0)
    
    colors = ramp.colors
    n = length(colors)
    
    if n == 0
        return "#808080"  # Gray fallback
    elseif n == 1
        return colors[1]
    end
    
    # Find the two colors to interpolate between
    scaled_t = t * (n - 1)
    lower_idx = floor(Int, scaled_t) + 1  # Julia is 1-indexed
    upper_idx = min(lower_idx + 1, n)
    local_t = scaled_t - (lower_idx - 1)
    
    # Parse colors
    r1, g1, b1 = hex_to_rgb(colors[lower_idx])
    r2, g2, b2 = hex_to_rgb(colors[upper_idx])
    
    # Interpolate
    r = round(Int, r1 + (r2 - r1) * local_t)
    g = round(Int, g1 + (g2 - g1) * local_t)
    b = round(Int, b1 + (b2 - b1) * local_t)
    
    return rgb_to_hex(r, g, b)
end

"""
    interpolate_color(ramp_name::String, t::Float64) -> String

Interpolate a color by ramp name. Falls back to gray if ramp not found.
"""
function interpolate_color(ramp_name::String, t::Float64)
    ramp = get(COLOR_RAMPS, ramp_name, nothing)
    if ramp === nothing
        @warn "Unknown color ramp: $ramp_name, using gray"
        return "#808080"
    end
    return interpolate_color(ramp, t)
end

# =============================================================================
# Application-Specific Color Functions
# =============================================================================

"""
    color_for_age(age, date_min::Float64, date_max::Float64, ramp_name::String) -> String

Get color for an age value within a date range.

Ages are in cal BP (larger = older). The color mapping is:
- Oldest samples (large BP values) → start of ramp (t=0)
- Youngest samples (small BP values) → end of ramp (t=1)

Returns default color for missing/nothing age values.
"""
function color_for_age(age, date_min::Float64, date_max::Float64, ramp_name::String;
                       default_color::String = "#808080")
    if age === nothing || ismissing(age)
        return default_color
    end
    
    range = date_max - date_min
    if range == 0
        return interpolate_color(ramp_name, 0.5)
    end
    
    # Normalize: t=0 for oldest (date_max), t=1 for youngest (date_min)
    t = (date_max - Float64(age)) / range
    return interpolate_color(ramp_name, t)
end

"""
    color_for_culture(culture, selected_cultures::Vector{String}, ramp_name::String) -> String

Get color for a culture based on its position in the selected cultures list.
Uses sequential color ramp interpolation.

Returns default color for missing/nothing culture values or cultures not in the selected list.
"""
function color_for_culture(culture, selected_cultures::Vector{String}, ramp_name::String;
                           default_color::String = "#808080")
    if culture === nothing || ismissing(culture) || culture == ""
        return default_color
    end
    
    if isempty(selected_cultures)
        return default_color
    end
    
    idx = findfirst(==(culture), selected_cultures)
    if idx === nothing
        return default_color
    end
    
    # Map index to [0, 1] range for color ramp interpolation
    n = length(selected_cultures)
    if n == 1
        t = 0.5  # Center of ramp for single item
    else
        t = (idx - 1) / (n - 1)
    end
    
    return interpolate_color(ramp_name, t)
end

"""
    color_for_haplogroup(haplogroup, selected_haplogroups::Vector{String}, ramp_name::String) -> String

Get color for a haplogroup based on its position in the selected haplogroups list.
Uses sequential color ramp interpolation.

Returns default color for missing/nothing haplogroup values or haplogroups not in the selected list.
"""
function color_for_haplogroup(haplogroup, selected_haplogroups::Vector{String}, ramp_name::String;
                             default_color::String = "#808080")
    if haplogroup === nothing || ismissing(haplogroup) || haplogroup == ""
        return default_color
    end
    
    if isempty(selected_haplogroups)
        return default_color
    end
    
    idx = findfirst(==(haplogroup), selected_haplogroups)
    if idx === nothing
        return default_color
    end
    
    # Map index to [0, 1] range for color ramp interpolation
    n = length(selected_haplogroups)
    if n == 1
        t = 0.5  # Center of ramp for single item
    else
        t = (idx - 1) / (n - 1)
    end
    
    return interpolate_color(ramp_name, t)
end

"""
    color_for_y_haplotree_term(path, terms::Vector{String}, ramp_name::String) -> String

Get color for a sample's Y-haplotree path based on which term from `terms` first
matches a node in the path (first-match-wins, case-insensitive token comparison).

Returns `default_color` when:
- path is nothing/missing/empty
- terms is empty
- no term matches any node in the path
"""
function color_for_y_haplotree_term(path, terms::Vector{String}, ramp_name::String;
                                    default_color::String = "#808080")
    if path === nothing || ismissing(path) || path == ""
        return default_color
    end

    if isempty(terms)
        return default_color
    end

    tokens = Set(lowercase(strip(tok)) for tok in split(string(path), '>'))
    n = length(terms)

    for (idx, term) in enumerate(terms)
        if lowercase(term) in tokens
            t = n == 1 ? 0.5 : (idx - 1) / (n - 1)
            return interpolate_color(ramp_name, t)
        end
    end

    return default_color
end

"""
    get_color_ramp_info() -> Dict

Get color ramp information for API response.
Returns a Dict suitable for JSON serialization.
"""
function get_color_ramp_info()
    return Dict(
        name => Dict(
            "colors" => ramp.colors,
            "label" => ramp.label
        )
        for (name, ramp) in COLOR_RAMPS
    )
end
