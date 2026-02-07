"""
    ArcheoGeneticMap.Analysis

Statistical analysis functions for sample attributes and cascading filter options.
"""

export calculate_date_range, calculate_date_statistics, calculate_culture_statistics
export compute_available_cultures, compute_available_date_range, build_filter_meta
export extract_ages, extract_cultures, build_culture_legend

# =============================================================================
# Extraction Helpers
# =============================================================================

"""
    extract_ages(features::Vector) -> Vector{Float64}

Extract all valid age values from a collection of features.
Filters out nothing and missing values.
"""
function extract_ages(features::Vector)
    ages = Float64[]
    for feature in features
        age = get(feature["properties"], "average_age_calbp", nothing)
        if age !== nothing && !ismissing(age)
            push!(ages, Float64(age))
        end
    end
    return ages
end

"""
    extract_cultures(features::Vector) -> Vector{String}

Extract all unique culture values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
function extract_cultures(features::Vector)
    culture_set = Set{String}()
    for feature in features
        culture = get(feature["properties"], "culture", nothing)
        if culture !== nothing && !ismissing(culture) && culture != ""
            push!(culture_set, String(culture))
        end
    end
    return sort(collect(culture_set))
end

# =============================================================================
# Basic Statistics (from original data_analysis.jl)
# =============================================================================

"""
    calculate_date_range(geojson::Dict) -> Tuple{Float64, Float64}

Extract the minimum and maximum ages from a GeoJSON FeatureCollection.
Returns (min_age, max_age) in cal BP.

If no dated samples exist, returns default values from config.
"""
function calculate_date_range(geojson::Dict)
    ages = extract_ages(geojson["features"])
    
    if isempty(ages)
        return (DEFAULT_MIN_AGE, DEFAULT_MAX_AGE)
    end
    
    return (minimum(ages), maximum(ages))
end

"""
    calculate_date_range(features::Vector) -> Tuple{Float64, Float64}

Extract the minimum and maximum ages from a vector of features.
"""
function calculate_date_range(features::Vector)
    ages = extract_ages(features)
    
    if isempty(ages)
        return (DEFAULT_MIN_AGE, DEFAULT_MAX_AGE)
    end
    
    return (minimum(ages), maximum(ages))
end

"""
    calculate_date_statistics(geojson::Dict) -> DateStatistics

Calculate date range statistics including percentiles for piecewise slider scaling.
Returns a DateStatistics struct with min, max, p2, and p98.

If no dated samples exist, returns default values from config with p2=p98=midpoint.
"""
function calculate_date_statistics(geojson::Dict)
    return calculate_date_statistics(geojson["features"])
end

"""
    calculate_date_statistics(features::Vector) -> DateStatistics

Calculate date range statistics from a vector of features.
"""
function calculate_date_statistics(features::Vector)
    ages = extract_ages(features)
    
    if isempty(ages)
        # No dated samples - use defaults with linear scaling
        midpoint = (DEFAULT_MIN_AGE + DEFAULT_MAX_AGE) / 2
        return DateStatistics(DEFAULT_MIN_AGE, DEFAULT_MAX_AGE, midpoint, midpoint)
    end
    
    # Sort for percentile calculation
    sort!(ages)
    n = length(ages)
    
    # Calculate percentile indices
    p2_idx = max(1, floor(Int, n * 0.02))
    p98_idx = min(n, ceil(Int, n * 0.98))
    
    return DateStatistics(
        ages[1],        # min (youngest)
        ages[end],      # max (oldest)
        ages[p2_idx],   # 2nd percentile
        ages[p98_idx]   # 98th percentile
    )
end

"""
    calculate_culture_statistics(geojson::Dict) -> CultureStatistics

Identify unique culture names from a GeoJSON FeatureCollection.
Returns a CultureStatistics with sorted culture names.
"""
function calculate_culture_statistics(geojson::Dict)
    return calculate_culture_statistics(geojson["features"])
end

"""
    calculate_culture_statistics(features::Vector) -> CultureStatistics

Identify unique culture names from a vector of features.
"""
function calculate_culture_statistics(features::Vector)
    cultures = extract_cultures(features)
    return CultureStatistics(cultures)
end

# =============================================================================
# Cascading Filter Options
# =============================================================================

"""
    compute_available_cultures(features::Vector; 
                               date_min=nothing, date_max=nothing, 
                               include_undated=true) -> Vector{String}

Compute which cultures are available given date constraints.
This enables cascading filters - when the user adjusts the date range,
the culture dropdown updates to show only cultures within that range.

# Arguments
- `features`: All features in the dataset
- `date_min`: Minimum age filter (nothing = no constraint)
- `date_max`: Maximum age filter (nothing = no constraint)
- `include_undated`: Whether undated samples contribute their cultures

# Returns
Sorted vector of culture names that have at least one sample in the date range.
"""
function compute_available_cultures(features::Vector;
                                    date_min::Union{Float64, Nothing} = nothing,
                                    date_max::Union{Float64, Nothing} = nothing,
                                    include_undated::Bool = true)
    culture_set = Set{String}()
    
    for feature in features
        age = get(feature["properties"], "average_age_calbp", nothing)
        culture = get(feature["properties"], "culture", nothing)
        
        # Skip if no culture
        if culture === nothing || ismissing(culture) || culture == ""
            continue
        end
        
        # Check date constraints
        if age === nothing || ismissing(age)
            # Undated sample
            if include_undated
                push!(culture_set, String(culture))
            end
        else
            age_val = Float64(age)
            in_range = true
            
            if date_min !== nothing && age_val < date_min
                in_range = false
            end
            if date_max !== nothing && age_val > date_max
                in_range = false
            end
            
            if in_range
                push!(culture_set, String(culture))
            end
        end
    end
    
    return sort(collect(culture_set))
end

"""
    compute_available_date_range(features::Vector, 
                                 culture_filter::CultureFilter;
                                 include_no_culture=true) -> Tuple{Float64, Float64}

Compute the date range available given culture constraints.
This enables cascading filters - when the user selects cultures,
the date slider can show the range of those cultures.

# Arguments
- `features`: All features in the dataset
- `culture_filter`: Current culture filter settings
- `include_no_culture`: Whether to include samples without culture data

# Returns
Tuple of (min_age, max_age) for samples matching the culture filter.
Returns default range if no matching samples have dates.
"""
function compute_available_date_range(features::Vector,
                                      culture_filter::CultureFilter;
                                      include_no_culture::Bool = true)
    ages = Float64[]
    selected_set = Set(culture_filter.selected)
    
    for feature in features
        culture = get(feature["properties"], "culture", nothing)
        age = get(feature["properties"], "average_age_calbp", nothing)
        
        # Skip if no age
        if age === nothing || ismissing(age)
            continue
        end
        
        # Check culture filter
        include_sample = false
        
        if isempty(selected_set)
            # No cultures selected - only include no-culture samples if flag set
            if culture === nothing || ismissing(culture) || culture == ""
                include_sample = include_no_culture
            else
                include_sample = false
            end
        else
            # Cultures selected
            if culture === nothing || ismissing(culture) || culture == ""
                include_sample = include_no_culture
            else
                include_sample = culture in selected_set
            end
        end
        
        if include_sample
            push!(ages, Float64(age))
        end
    end
    
    if isempty(ages)
        return (DEFAULT_MIN_AGE, DEFAULT_MAX_AGE)
    end
    
    return (minimum(ages), maximum(ages))
end

# =============================================================================
# Filter Metadata Builder
# =============================================================================

"""
    build_filter_meta(all_features::Vector, 
                      filtered_features::Vector,
                      request::FilterRequest) -> FilterMeta

Build complete filter metadata for a query response.

# Arguments
- `all_features`: Complete dataset (for total count and available options)
- `filtered_features`: Features after filtering (for filtered count)
- `request`: The filter request (to compute cascading options)

# Returns
FilterMeta with counts, available options, and culture legend for UI
"""
function build_filter_meta(all_features::Vector,
                           filtered_features::Vector,
                           request::FilterRequest)
    # Counts
    total_count = length(all_features)
    filtered_count = length(filtered_features)
    
    # Available cultures given current date filter
    available_cultures = compute_available_cultures(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated
    )
    
    # Available date range given current culture filter
    available_date_range = compute_available_date_range(
        all_features,
        request.culture_filter,
        include_no_culture = request.include_no_culture
    )
    
    # Full date statistics for slider configuration
    date_statistics = calculate_date_statistics(all_features)
    
    # Build culture legend (cultures to display with colors)
    culture_legend = build_culture_legend(
        available_cultures,
        request.culture_filter,
        request.include_no_culture
    )
    
    return FilterMeta(
        total_count,
        filtered_count,
        available_cultures,
        available_date_range,
        date_statistics,
        culture_legend
    )
end

"""
    build_culture_legend(available_cultures::Vector{String},
                        culture_filter::CultureFilter,
                        include_no_culture::Bool) -> Vector{Tuple{String, String}}

Build a culture legend with (name, color) pairs for display.
Returns up to 20 items for the legend.

# Logic
- If no cultures selected and include_no_culture=true: empty legend
- If cultures selected: show selected cultures with their colors (max 20)
- Colors are assigned using the CULTURE_PALETTE from colors.jl
"""
function build_culture_legend(available_cultures::Vector{String},
                              culture_filter::CultureFilter,
                              include_no_culture::Bool)
    # Determine which cultures to show in legend
    legend_cultures = if isempty(culture_filter.selected)
        # No cultures selected - don't show a culture legend
        String[]
    else
        # Show selected cultures that are available
        selected_set = Set(culture_filter.selected)
        filter(c -> c in selected_set, available_cultures)
    end
    
    # Limit to 20 entries
    legend_cultures = legend_cultures[1:min(20, length(legend_cultures))]
    
    # Assign colors using the same logic as color_for_culture
    legend = Tuple{String, String}[]
    for culture in legend_cultures
        color = color_for_culture(culture, available_cultures)
        push!(legend, (culture, color))
    end
    
    return legend
end
