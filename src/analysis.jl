"""
    ArcheoGeneticMap.Analysis

Statistical analysis functions for sample attributes and cascading filter options.
"""

export calculate_date_range, calculate_date_statistics, calculate_culture_statistics
export compute_available_cultures, compute_available_y_haplogroups, compute_available_mtdna
export compute_available_date_range, build_filter_meta
export extract_ages, extract_cultures, extract_y_haplogroups, extract_mtdna
export build_culture_legend, build_haplogroup_legend
export filter_haplogroups_by_search

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

"""
    extract_y_haplogroups(features::Vector) -> Vector{String}

Extract all unique Y-haplogroup values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
function extract_y_haplogroups(features::Vector)
    haplogroup_set = Set{String}()
    for feature in features
        haplogroup = get(feature["properties"], "y_haplogroup", nothing)
        if haplogroup !== nothing && !ismissing(haplogroup) && haplogroup != ""
            push!(haplogroup_set, String(haplogroup))
        end
    end
    return sort(collect(haplogroup_set))
end

"""
    extract_mtdna(features::Vector) -> Vector{String}

Extract all unique mtDNA haplogroup values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
function extract_mtdna(features::Vector)
    mtdna_set = Set{String}()
    for feature in features
        mtdna = get(feature["properties"], "mtdna", nothing)
        if mtdna !== nothing && !ismissing(mtdna) && mtdna != ""
            push!(mtdna_set, String(mtdna))
        end
    end
    return sort(collect(mtdna_set))
end

# =============================================================================
# Basic Statistics
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
                               include_undated=true,
                               y_haplogroup_filter=nothing,
                               mtdna_filter=nothing) -> Vector{String}

Compute which cultures are available given date and haplogroup constraints.
"""
function compute_available_cultures(features::Vector;
                                    date_min::Union{Float64, Nothing} = nothing,
                                    date_max::Union{Float64, Nothing} = nothing,
                                    include_undated::Bool = true,
                                    y_haplogroup_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                    include_no_y_haplogroup::Bool = true,
                                    mtdna_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                    include_no_mtdna::Bool = true)
    culture_set = Set{String}()
    
    y_selected = y_haplogroup_filter !== nothing ? Set(y_haplogroup_filter.selected) : Set{String}()
    mtdna_selected = mtdna_filter !== nothing ? Set(mtdna_filter.selected) : Set{String}()
    
    for feature in features
        props = feature["properties"]
        age = get(props, "average_age_calbp", nothing)
        culture = get(props, "culture", nothing)
        y_hap = get(props, "y_haplogroup", nothing)
        mtdna_hap = get(props, "mtdna", nothing)
        
        # Skip if no culture
        if culture === nothing || ismissing(culture) || culture == ""
            continue
        end
        
        # Check date constraints
        if age === nothing || ismissing(age)
            if !include_undated
                continue
            end
        else
            age_val = Float64(age)
            if date_min !== nothing && age_val < date_min
                continue
            end
            if date_max !== nothing && age_val > date_max
                continue
            end
        end
        
        # Check Y-haplogroup constraints
        if y_haplogroup_filter !== nothing && !isempty(y_selected)
            if y_hap === nothing || ismissing(y_hap) || y_hap == ""
                if !include_no_y_haplogroup
                    continue
                end
            elseif !(y_hap in y_selected)
                continue
            end
        end
        
        # Check mtDNA constraints
        if mtdna_filter !== nothing && !isempty(mtdna_selected)
            if mtdna_hap === nothing || ismissing(mtdna_hap) || mtdna_hap == ""
                if !include_no_mtdna
                    continue
                end
            elseif !(mtdna_hap in mtdna_selected)
                continue
            end
        end
        
        push!(culture_set, String(culture))
    end
    
    return sort(collect(culture_set))
end

"""
    compute_available_y_haplogroups(features::Vector; filters...) -> Vector{String}

Compute which Y-haplogroups are available given date, culture, and mtDNA constraints.
"""
function compute_available_y_haplogroups(features::Vector;
                                        date_min::Union{Float64, Nothing} = nothing,
                                        date_max::Union{Float64, Nothing} = nothing,
                                        include_undated::Bool = true,
                                        culture_filter::Union{CultureFilter, Nothing} = nothing,
                                        include_no_culture::Bool = true,
                                        mtdna_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                        include_no_mtdna::Bool = true)
    haplogroup_set = Set{String}()
    
    culture_selected = culture_filter !== nothing ? Set(culture_filter.selected) : Set{String}()
    mtdna_selected = mtdna_filter !== nothing ? Set(mtdna_filter.selected) : Set{String}()
    
    for feature in features
        props = feature["properties"]
        age = get(props, "average_age_calbp", nothing)
        culture = get(props, "culture", nothing)
        y_hap = get(props, "y_haplogroup", nothing)
        mtdna_hap = get(props, "mtdna", nothing)
        
        # Skip if no Y-haplogroup
        if y_hap === nothing || ismissing(y_hap) || y_hap == ""
            continue
        end
        
        # Check date constraints
        if age === nothing || ismissing(age)
            if !include_undated
                continue
            end
        else
            age_val = Float64(age)
            if date_min !== nothing && age_val < date_min
                continue
            end
            if date_max !== nothing && age_val > date_max
                continue
            end
        end
        
        # Check culture constraints
        if culture_filter !== nothing && !isempty(culture_selected)
            if culture === nothing || ismissing(culture) || culture == ""
                if !include_no_culture
                    continue
                end
            elseif !(culture in culture_selected)
                continue
            end
        end
        
        # Check mtDNA constraints
        if mtdna_filter !== nothing && !isempty(mtdna_selected)
            if mtdna_hap === nothing || ismissing(mtdna_hap) || mtdna_hap == ""
                if !include_no_mtdna
                    continue
                end
            elseif !(mtdna_hap in mtdna_selected)
                continue
            end
        end
        
        push!(haplogroup_set, String(y_hap))
    end
    
    return sort(collect(haplogroup_set))
end

"""
    compute_available_mtdna(features::Vector; filters...) -> Vector{String}

Compute which mtDNA haplogroups are available given date, culture, and Y-haplogroup constraints.
"""
function compute_available_mtdna(features::Vector;
                                date_min::Union{Float64, Nothing} = nothing,
                                date_max::Union{Float64, Nothing} = nothing,
                                include_undated::Bool = true,
                                culture_filter::Union{CultureFilter, Nothing} = nothing,
                                include_no_culture::Bool = true,
                                y_haplogroup_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                include_no_y_haplogroup::Bool = true)
    mtdna_set = Set{String}()
    
    culture_selected = culture_filter !== nothing ? Set(culture_filter.selected) : Set{String}()
    y_selected = y_haplogroup_filter !== nothing ? Set(y_haplogroup_filter.selected) : Set{String}()
    
    for feature in features
        props = feature["properties"]
        age = get(props, "average_age_calbp", nothing)
        culture = get(props, "culture", nothing)
        y_hap = get(props, "y_haplogroup", nothing)
        mtdna_hap = get(props, "mtdna", nothing)
        
        # Skip if no mtDNA
        if mtdna_hap === nothing || ismissing(mtdna_hap) || mtdna_hap == ""
            continue
        end
        
        # Check date constraints
        if age === nothing || ismissing(age)
            if !include_undated
                continue
            end
        else
            age_val = Float64(age)
            if date_min !== nothing && age_val < date_min
                continue
            end
            if date_max !== nothing && age_val > date_max
                continue
            end
        end
        
        # Check culture constraints
        if culture_filter !== nothing && !isempty(culture_selected)
            if culture === nothing || ismissing(culture) || culture == ""
                if !include_no_culture
                    continue
                end
            elseif !(culture in culture_selected)
                continue
            end
        end
        
        # Check Y-haplogroup constraints
        if y_haplogroup_filter !== nothing && !isempty(y_selected)
            if y_hap === nothing || ismissing(y_hap) || y_hap == ""
                if !include_no_y_haplogroup
                    continue
                end
            elseif !(y_hap in y_selected)
                continue
            end
        end
        
        push!(mtdna_set, String(mtdna_hap))
    end
    
    return sort(collect(mtdna_set))
end

"""
    compute_available_date_range(features::Vector, filters...) -> Tuple{Float64, Float64}

Compute the date range available given culture and haplogroup constraints.
"""
function compute_available_date_range(features::Vector,
                                      culture_filter::CultureFilter;
                                      include_no_culture::Bool = true,
                                      y_haplogroup_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                      include_no_y_haplogroup::Bool = true,
                                      mtdna_filter::Union{HaplogroupFilter, Nothing} = nothing,
                                      include_no_mtdna::Bool = true)
    ages = Float64[]
    culture_selected = Set(culture_filter.selected)
    y_selected = y_haplogroup_filter !== nothing ? Set(y_haplogroup_filter.selected) : Set{String}()
    mtdna_selected = mtdna_filter !== nothing ? Set(mtdna_filter.selected) : Set{String}()
    
    for feature in features
        props = feature["properties"]
        age = get(props, "average_age_calbp", nothing)
        culture = get(props, "culture", nothing)
        y_hap = get(props, "y_haplogroup", nothing)
        mtdna_hap = get(props, "mtdna", nothing)
        
        # Skip if no age
        if age === nothing || ismissing(age)
            continue
        end
        
        # Check culture constraints
        if !isempty(culture_selected)
            if culture === nothing || ismissing(culture) || culture == ""
                if !include_no_culture
                    continue
                end
            elseif !(culture in culture_selected)
                continue
            end
        end
        
        # Check Y-haplogroup constraints
        if y_haplogroup_filter !== nothing && !isempty(y_selected)
            if y_hap === nothing || ismissing(y_hap) || y_hap == ""
                if !include_no_y_haplogroup
                    continue
                end
            elseif !(y_hap in y_selected)
                continue
            end
        end
        
        # Check mtDNA constraints
        if mtdna_filter !== nothing && !isempty(mtdna_selected)
            if mtdna_hap === nothing || ismissing(mtdna_hap) || mtdna_hap == ""
                if !include_no_mtdna
                    continue
                end
            elseif !(mtdna_hap in mtdna_selected)
                continue
            end
        end
        
        push!(ages, Float64(age))
    end
    
    if isempty(ages)
        return (DEFAULT_MIN_AGE, DEFAULT_MAX_AGE)
    end
    
    return (minimum(ages), maximum(ages))
end

# =============================================================================
# Search Filtering
# =============================================================================

"""
    filter_haplogroups_by_search(haplogroups::Vector{String}, search_text::String) -> Vector{String}

Filter haplogroups by case-insensitive prefix match.
Returns haplogroups that start with the search text.
"""
function filter_haplogroups_by_search(haplogroups::Vector{String}, search_text::String)
    if isempty(search_text)
        return haplogroups
    end
    
    search_lower = lowercase(search_text)
    return filter(h -> startswith(lowercase(h), search_lower), haplogroups)
end

# =============================================================================
# Legend Builders
# =============================================================================

"""
    build_culture_legend(selected_cultures::Vector{String},
                        culture_color_ramp::String) -> Vector{Tuple{String, String}}

Build a culture legend with (name, color) pairs for display.
Returns all selected cultures with their colors based on the color ramp.
"""
function build_culture_legend(selected_cultures::Vector{String},
                              culture_color_ramp::String)
    legend = Tuple{String, String}[]
    
    for culture in selected_cultures
        color = color_for_culture(culture, selected_cultures, culture_color_ramp)
        push!(legend, (culture, color))
    end
    
    return legend
end

"""
    build_haplogroup_legend(selected_haplogroups::Vector{String},
                           haplogroup_color_ramp::String) -> Vector{Tuple{String, String}}

Build a haplogroup legend with (name, color) pairs for display.
Returns all selected haplogroups with their colors based on the color ramp.
"""
function build_haplogroup_legend(selected_haplogroups::Vector{String},
                                haplogroup_color_ramp::String)
    legend = Tuple{String, String}[]
    
    for haplogroup in selected_haplogroups
        color = color_for_haplogroup(haplogroup, selected_haplogroups, haplogroup_color_ramp)
        push!(legend, (haplogroup, color))
    end
    
    return legend
end

# =============================================================================
# Filter Metadata Builder
# =============================================================================

"""
    build_filter_meta(all_features::Vector, 
                      filtered_features::Vector,
                      request::FilterRequest) -> FilterMeta

Build complete filter metadata for a query response.
"""
function build_filter_meta(all_features::Vector,
                           filtered_features::Vector,
                           request::FilterRequest)
    # Counts
    total_count = length(all_features)
    filtered_count = length(filtered_features)
    
    # Available options given current filters (cascading)
    available_cultures = compute_available_cultures(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        y_haplogroup_filter = request.y_haplogroup_filter,
        include_no_y_haplogroup = request.include_no_y_haplogroup,
        mtdna_filter = request.mtdna_filter,
        include_no_mtdna = request.include_no_mtdna
    )
    
    available_y_haplogroups = compute_available_y_haplogroups(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        culture_filter = request.culture_filter,
        include_no_culture = request.include_no_culture,
        mtdna_filter = request.mtdna_filter,
        include_no_mtdna = request.include_no_mtdna
    )
    
    available_mtdna = compute_available_mtdna(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        culture_filter = request.culture_filter,
        include_no_culture = request.include_no_culture,
        y_haplogroup_filter = request.y_haplogroup_filter,
        include_no_y_haplogroup = request.include_no_y_haplogroup
    )
    
    # Apply search text filtering for haplogroups
    filtered_y_haplogroups = filter_haplogroups_by_search(
        available_y_haplogroups,
        request.y_haplogroup_filter.search_text
    )
    
    filtered_mtdna = filter_haplogroups_by_search(
        available_mtdna,
        request.mtdna_filter.search_text
    )
    
    # Available date range given current filters
    available_date_range = compute_available_date_range(
        all_features,
        request.culture_filter,
        include_no_culture = request.include_no_culture,
        y_haplogroup_filter = request.y_haplogroup_filter,
        include_no_y_haplogroup = request.include_no_y_haplogroup,
        mtdna_filter = request.mtdna_filter,
        include_no_mtdna = request.include_no_mtdna
    )
    
    # Full date statistics for slider configuration
    date_statistics = calculate_date_statistics(all_features)
    
    # Build legends - only for selected items with their color ramps
    culture_legend = build_culture_legend(
        request.culture_filter.selected,
        request.culture_color_ramp
    )
    
    y_haplogroup_legend = build_haplogroup_legend(
        request.y_haplogroup_filter.selected,
        request.y_haplogroup_color_ramp
    )
    
    mtdna_legend = build_haplogroup_legend(
        request.mtdna_filter.selected,
        request.mtdna_color_ramp
    )
    
    return FilterMeta(
        total_count,
        filtered_count,
        available_cultures,
        available_y_haplogroups,
        available_mtdna,
        filtered_y_haplogroups,
        filtered_mtdna,
        available_date_range,
        date_statistics,
        culture_legend,
        y_haplogroup_legend,
        mtdna_legend
    )
end
