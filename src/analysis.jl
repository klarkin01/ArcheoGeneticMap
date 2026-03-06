"""
    ArcheoGeneticMap.Analysis

Statistical analysis functions for sample attributes and cascading filter options.
"""

export calculate_date_range, calculate_date_statistics, calculate_culture_statistics
export passes_filter, compute_available
export compute_available_cultures, compute_available_y_haplogroups, compute_available_mtdna, compute_available_sources
export compute_available_date_range, build_filter_meta
export extract_ages, extract_unique_strings, extract_cultures, extract_y_haplogroups, extract_mtdna, extract_sources
export build_categorical_legend, build_culture_legend, build_haplogroup_legend, build_y_haplotree_legend
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
        if has_value(age)
            push!(ages, Float64(age))
        end
    end
    return ages
end

"""
    extract_unique_strings(features::Vector, property_key::String) -> Vector{String}

Extract all unique non-empty string values for a given property key from a
collection of features. Returns a sorted vector, excluding nothing, missing,
and empty strings.

This is the single implementation underlying `extract_cultures`,
`extract_y_haplogroups`, `extract_mtdna`, and any future string property
extractions. To support a new field, call this directly or add a named wrapper.
"""
function extract_unique_strings(features::Vector, property_key::String)
    value_set = Set{String}()
    for feature in features
        value = get(feature["properties"], property_key, nothing)
        if has_value(value)
            push!(value_set, String(value))
        end
    end
    return sort(collect(value_set))
end

# Named wrappers — preserve the stable public API and document intent clearly.
"""
    extract_cultures(features::Vector) -> Vector{String}

Extract all unique culture values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
extract_cultures(features::Vector) = extract_unique_strings(features, "culture")

"""
    extract_y_haplogroups(features::Vector) -> Vector{String}

Extract all unique Y-haplogroup values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
extract_y_haplogroups(features::Vector) = extract_unique_strings(features, "y_haplogroup")

"""
    extract_mtdna(features::Vector) -> Vector{String}

Extract all unique mtDNA haplogroup values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
extract_mtdna(features::Vector) = extract_unique_strings(features, "mtdna")

"""
    extract_sources(features::Vector) -> Vector{String}

Extract all unique source/study values from a collection of features.
Returns a sorted vector, excluding nothing, missing, and empty strings.
"""
extract_sources(features::Vector) = extract_unique_strings(features, "source")

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
    passes_filter(value, selected::Set{String}, include_missing::Bool) -> Bool

Check whether a single feature property value passes one selection filter's
constraints. Used as a building block inside `compute_available`.

- If `selected` is empty, the filter is inactive → always passes.
- If `value` is missing: passes only when `include_missing` is true.
- Otherwise: passes only when `value` is in `selected`.
"""
function passes_filter(value, selected::Set{String}, include_missing::Bool)
    isempty(selected) && return true
    is_missing_value(value) && return include_missing
    return value in selected
end

"""
    compute_available(features::Vector, target::AbstractSelectionFilter;
                      date_min, date_max, include_undated,
                      cross_filters) -> Vector{String}

Compute which values are available for the property identified by `target`,
given date and cross-filter constraints. Collects values from features that:
- Have a non-missing value for `property_key(target)`
- Pass the date constraint
- Pass all provided cross-filters

`cross_filters` is a vector of `(filter::AbstractSelectionFilter, include_missing::Bool)`
pairs representing every active filter *other than* the target's own filter.
The target filter is intentionally excluded — we want to know what's available
for that dimension regardless of what is currently selected in it.

This is the single implementation underlying `compute_available_cultures`,
`compute_available_y_haplogroups`, and `compute_available_mtdna`.
"""
function compute_available(features::Vector,
                           target::AbstractSelectionFilter;
                           date_min::Union{Float64, Nothing} = nothing,
                           date_max::Union{Float64, Nothing} = nothing,
                           include_undated::Bool = true,
                           cross_filters::Vector{Tuple{AbstractSelectionFilter, Bool}} =
                               Tuple{AbstractSelectionFilter, Bool}[])
    result_set = Set{String}()
    target_key = property_key(target)

    # Pre-compute selected sets for cross-filters once outside the loop
    cross_selected = [(Set(f.selected), include_m) for (f, include_m) in cross_filters]
    cross_keys = [property_key(f) for (f, _) in cross_filters]

    for feature in features
        props = feature["properties"]
        target_value = get(props, target_key, nothing)

        # Skip features with no value for the target dimension
        is_missing_value(target_value) && continue

        # Check date constraint
        age = get(props, "average_age_calbp", nothing)
        if is_missing_value(age)
            include_undated || continue
        else
            age_val = Float64(age)
            date_min !== nothing && age_val < date_min && continue
            date_max !== nothing && age_val > date_max && continue
        end

        # Check all cross-filter constraints
        passed = true
        for i in eachindex(cross_keys)
            value = get(props, cross_keys[i], nothing)
            if !passes_filter(value, cross_selected[i][1], cross_selected[i][2])
                passed = false
                break
            end
        end
        passed || continue

        push!(result_set, String(target_value))
    end

    return sort(collect(result_set))
end

# Named wrappers — stable public API, each excluding its own filter from cross-filters.
"""
    compute_available_cultures(features::Vector; filters...) -> Vector{String}

Compute which cultures are available given date and haplogroup constraints.
"""
function compute_available_cultures(features::Vector;
                                    date_min::Union{Float64, Nothing} = nothing,
                                    date_max::Union{Float64, Nothing} = nothing,
                                    include_undated::Bool = true,
                                    y_haplogroup_filter::Union{YHaplogroupFilter, Nothing} = nothing,
                                    include_no_y_haplogroup::Bool = true,
                                    mtdna_filter::Union{MtdnaFilter, Nothing} = nothing,
                                    include_no_mtdna::Bool = true,
                                    source_filter::Union{SourceFilter, Nothing} = nothing)
    cross_filters = Tuple{AbstractSelectionFilter, Bool}[]
    y_haplogroup_filter !== nothing && push!(cross_filters, (y_haplogroup_filter, include_no_y_haplogroup))
    mtdna_filter        !== nothing && push!(cross_filters, (mtdna_filter,        include_no_mtdna))
    source_filter       !== nothing && push!(cross_filters, (source_filter,       true))
    return compute_available(features, CultureFilter();
        date_min, date_max, include_undated, cross_filters)
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
                                         mtdna_filter::Union{MtdnaFilter, Nothing} = nothing,
                                         include_no_mtdna::Bool = true,
                                         source_filter::Union{SourceFilter, Nothing} = nothing)
    cross_filters = Tuple{AbstractSelectionFilter, Bool}[]
    culture_filter      !== nothing && push!(cross_filters, (culture_filter,      include_no_culture))
    mtdna_filter        !== nothing && push!(cross_filters, (mtdna_filter,        include_no_mtdna))
    source_filter       !== nothing && push!(cross_filters, (source_filter,       true))
    return compute_available(features, YHaplogroupFilter();
        date_min, date_max, include_undated, cross_filters)
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
                                 y_haplogroup_filter::Union{YHaplogroupFilter, Nothing} = nothing,
                                 include_no_y_haplogroup::Bool = true,
                                 source_filter::Union{SourceFilter, Nothing} = nothing)
    cross_filters = Tuple{AbstractSelectionFilter, Bool}[]
    culture_filter      !== nothing && push!(cross_filters, (culture_filter,      include_no_culture))
    y_haplogroup_filter !== nothing && push!(cross_filters, (y_haplogroup_filter, include_no_y_haplogroup))
    source_filter       !== nothing && push!(cross_filters, (source_filter,       true))
    return compute_available(features, MtdnaFilter();
        date_min, date_max, include_undated, cross_filters)
end

"""
    compute_available_sources(features::Vector; filters...) -> Vector{String}

Compute which sources are available given date, culture, and haplogroup constraints.
"""
function compute_available_sources(features::Vector;
                                   date_min::Union{Float64, Nothing} = nothing,
                                   date_max::Union{Float64, Nothing} = nothing,
                                   include_undated::Bool = true,
                                   culture_filter::Union{CultureFilter, Nothing} = nothing,
                                   include_no_culture::Bool = true,
                                   y_haplogroup_filter::Union{YHaplogroupFilter, Nothing} = nothing,
                                   include_no_y_haplogroup::Bool = true,
                                   mtdna_filter::Union{MtdnaFilter, Nothing} = nothing,
                                   include_no_mtdna::Bool = true)
    cross_filters = Tuple{AbstractSelectionFilter, Bool}[]
    culture_filter      !== nothing && push!(cross_filters, (culture_filter,      include_no_culture))
    y_haplogroup_filter !== nothing && push!(cross_filters, (y_haplogroup_filter, include_no_y_haplogroup))
    mtdna_filter        !== nothing && push!(cross_filters, (mtdna_filter,        include_no_mtdna))
    return compute_available(features, SourceFilter();
        date_min, date_max, include_undated, cross_filters)
end

"""
    compute_available_date_range(features::Vector, culture_filter::CultureFilter;
                                 filters...) -> Tuple{Float64, Float64}

Compute the date range available given culture and haplogroup constraints.
Uses the same cross-filter logic as `compute_available` but collects ages
rather than string values.
"""
function compute_available_date_range(features::Vector,
                                      culture_filter::CultureFilter;
                                      include_no_culture::Bool = true,
                                      y_haplogroup_filter::Union{YHaplogroupFilter, Nothing} = nothing,
                                      include_no_y_haplogroup::Bool = true,
                                      mtdna_filter::Union{MtdnaFilter, Nothing} = nothing,
                                      include_no_mtdna::Bool = true)
    cross_filters = Tuple{AbstractSelectionFilter, Bool}[
        (culture_filter, include_no_culture)
    ]
    y_haplogroup_filter !== nothing && push!(cross_filters, (y_haplogroup_filter, include_no_y_haplogroup))
    mtdna_filter !== nothing && push!(cross_filters, (mtdna_filter, include_no_mtdna))

    cross_selected = [(Set(f.selected), include_m) for (f, include_m) in cross_filters]
    cross_keys = [property_key(f) for (f, _) in cross_filters]

    ages = Float64[]
    for feature in features
        props = feature["properties"]
        age = get(props, "average_age_calbp", nothing)
        is_missing_value(age) && continue

        passed = true
        for i in eachindex(cross_keys)
            value = get(props, cross_keys[i], nothing)
            if !passes_filter(value, cross_selected[i][1], cross_selected[i][2])
                passed = false
                break
            end
        end
        passed || continue

        push!(ages, Float64(age))
    end

    isempty(ages) && return (DEFAULT_MIN_AGE, DEFAULT_MAX_AGE)
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
    build_categorical_legend(items::Vector{String}, ramp_name::String) -> Vector{Tuple{String, String}}

Build a legend as (name, color) pairs for any ordered list of categorical items.
Colors are assigned by position using `color_for_category`, so they match exactly
what markers on the map receive.

This is the single implementation underlying `build_culture_legend`,
`build_haplogroup_legend`, and `build_y_haplotree_legend`.
"""
function build_categorical_legend(items::Vector{String}, ramp_name::String)
    return [(item, color_for_category(item, items, ramp_name)) for item in items]
end

# Named wrappers — used by build_filter_meta and preserve the stable public API.
"""
    build_culture_legend(selected_cultures::Vector{String}, ramp_name::String) -> Vector{Tuple{String, String}}

Build a culture legend. Delegates to `build_categorical_legend`.
"""
build_culture_legend(selected_cultures::Vector{String}, ramp_name::String) =
    build_categorical_legend(selected_cultures, ramp_name)

"""
    build_haplogroup_legend(selected_haplogroups::Vector{String}, ramp_name::String) -> Vector{Tuple{String, String}}

Build a haplogroup legend. Delegates to `build_categorical_legend`.
"""
build_haplogroup_legend(selected_haplogroups::Vector{String}, ramp_name::String) =
    build_categorical_legend(selected_haplogroups, ramp_name)

"""
    build_y_haplotree_legend(terms::Vector{String}, ramp_name::String) -> Vector{Tuple{String, String}}

Build a Y-haplotree legend. Each term receives a color by its position in the
terms list, matching the first-match-wins color assignment in `color_for_y_haplotree_term`.
Delegates to `build_categorical_legend`.
"""
build_y_haplotree_legend(terms::Vector{String}, ramp_name::String) =
    build_categorical_legend(terms, ramp_name)

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
        include_no_mtdna = request.include_no_mtdna,
        source_filter = request.source_filter
    )
    
    available_y_haplogroups = compute_available_y_haplogroups(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        culture_filter = request.culture_filter,
        include_no_culture = request.include_no_culture,
        mtdna_filter = request.mtdna_filter,
        include_no_mtdna = request.include_no_mtdna,
        source_filter = request.source_filter
    )
    
    available_mtdna = compute_available_mtdna(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        culture_filter = request.culture_filter,
        include_no_culture = request.include_no_culture,
        y_haplogroup_filter = request.y_haplogroup_filter,
        include_no_y_haplogroup = request.include_no_y_haplogroup,
        source_filter = request.source_filter
    )

    available_sources = compute_available_sources(
        all_features,
        date_min = request.date_min,
        date_max = request.date_max,
        include_undated = request.include_undated,
        culture_filter = request.culture_filter,
        include_no_culture = request.include_no_culture,
        y_haplogroup_filter = request.y_haplogroup_filter,
        include_no_y_haplogroup = request.include_no_y_haplogroup,
        mtdna_filter = request.mtdna_filter,
        include_no_mtdna = request.include_no_mtdna
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

    y_haplotree_legend = build_y_haplotree_legend(
        request.y_haplotree_filter.terms,
        request.y_haplotree_color_ramp
    )
    
    return FilterMeta(
        total_count,
        filtered_count,
        available_cultures,
        available_y_haplogroups,
        available_mtdna,
        available_sources,
        filtered_y_haplogroups,
        filtered_mtdna,
        available_date_range,
        date_statistics,
        culture_legend,
        y_haplogroup_legend,
        mtdna_legend,
        y_haplotree_legend
    )
end
