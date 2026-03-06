"""
    ArcheoGeneticMap.Filters

Filter application logic for GeoJSON features.
Each filter function takes a collection of features and returns a filtered subset.
"""

export apply_date_filter, apply_filter, apply_culture_filter, apply_y_haplogroup_filter, apply_mtdna_filter, apply_source_filter, apply_y_haplotree_filter, apply_filters

# =============================================================================
# Individual Filter Functions
# =============================================================================

"""
    apply_date_filter(features, date_min, date_max, include_undated::Bool) -> Vector

Filter features by date range.
"""
function apply_date_filter(features::Vector,
                           date_min::Union{Float64, Nothing},
                           date_max::Union{Float64, Nothing},
                           include_undated::Bool)
    if date_min === nothing && date_max === nothing && include_undated
        return features
    end

    return filter(features) do feature
        age = get(feature["properties"], "average_age_calbp", nothing)

        if is_missing_value(age)
            return include_undated
        end

        age = Float64(age)

        if date_min !== nothing && age < date_min
            return false
        end
        if date_max !== nothing && age > date_max
            return false
        end

        return true
    end
end

"""
    apply_filter(features, filter::AbstractSelectionFilter, include_missing::Bool) -> Vector

Filter features by any selection-based filter. Dispatches on filter type to
determine which GeoJSON property key to check via `property_key(filter)`.

A feature is included when:
- Its property value is in `filter.selected`, OR
- Its property value is absent and `include_missing` is true

Adding a new selection filter type requires only a new struct, a `property_key`
method, and a named wrapper below — this function needs no changes.
"""
function apply_filter(features::Vector,
                      filter::AbstractSelectionFilter,
                      include_missing::Bool)
    selected = Set(filter.selected)
    key = property_key(filter)

    if isempty(selected) && !include_missing
        return Dict{String, Any}[]
    end

    return Base.filter(features) do feature
        value = get(feature["properties"], key, nothing)

        if is_missing_value(value)
            return include_missing
        end

        if isempty(selected)
            return false
        end

        return value in selected
    end
end

# Named wrappers — preserve the stable public API used in apply_filters and tests.
"""
    apply_culture_filter(features, culture_filter::CultureFilter,
                         include_no_culture::Bool) -> Vector

Filter features by culture. Delegates to `apply_filter`.
"""
apply_culture_filter(features::Vector,
                     culture_filter::CultureFilter,
                     include_no_culture::Bool) =
    apply_filter(features, culture_filter, include_no_culture)

"""
    apply_y_haplogroup_filter(features, haplogroup_filter::YHaplogroupFilter,
                              include_no_y_haplogroup::Bool) -> Vector

Filter features by Y-haplogroup. Delegates to `apply_filter`.
"""
apply_y_haplogroup_filter(features::Vector,
                          haplogroup_filter::YHaplogroupFilter,
                          include_no_y_haplogroup::Bool) =
    apply_filter(features, haplogroup_filter, include_no_y_haplogroup)

"""
    apply_mtdna_filter(features, mtdna_filter::MtdnaFilter,
                       include_no_mtdna::Bool) -> Vector

Filter features by mtDNA haplogroup. Delegates to `apply_filter`.
"""
apply_mtdna_filter(features::Vector,
                   mtdna_filter::MtdnaFilter,
                   include_no_mtdna::Bool) =
    apply_filter(features, mtdna_filter, include_no_mtdna)

"""
    apply_source_filter(features, source_filter::SourceFilter) -> Vector

Filter features by source/study. Delegates to `apply_filter`.
Samples with no source are always included (include_missing = true).
"""
apply_source_filter(features::Vector,
                    source_filter::SourceFilter) =
    apply_filter(features, source_filter, true)

# =============================================================================
# Haplotree Filter (structurally distinct — token matching, not set membership)
# =============================================================================

"""
    apply_y_haplotree_filter(features, y_haplotree_filter::YHaplotreeFilter) -> Vector

Filter features by Y-haplotree token matching.

Each term in the filter is matched case-insensitively against the nodes of a
sample's haplotree path (split on '>').  A sample is included if ANY term
matches ANY node exactly.  Empty terms list → no filter (all samples pass).
Samples with an empty/missing y_haplotree field are hidden when the filter is active.
"""
function apply_y_haplotree_filter(features::Vector,
                                  y_haplotree_filter::YHaplotreeFilter)
    if isempty(y_haplotree_filter.terms)
        return features
    end

    terms_lower = Set(lowercase(t) for t in y_haplotree_filter.terms)

    return Base.filter(features) do feature
        path = get(feature["properties"], "y_haplotree", nothing)

        if is_missing_value(path)
            return false
        end

        tokens = [lowercase(strip(tok)) for tok in split(string(path), '>')]
        return any(tok -> tok in terms_lower, tokens)
    end
end

# =============================================================================
# Combined Filter Application
# =============================================================================

"""
    apply_filters(features, request::FilterRequest) -> Vector

Apply all filters from a FilterRequest to a collection of features.

Filters are applied in order:
1. Date filter
2. Culture filter
3. Y-haplogroup filter (skipped when y_haplotree_filter is active)
4. mtDNA filter
5. Y-haplotree filter (skipped when y_haplogroup_filter is active)
6. Source filter

Note: y_haplogroup_filter and y_haplotree_filter are mutually exclusive.
When y_haplotree_filter has terms, y_haplogroup_filter is ignored, and vice versa.
The frontend enforces that only one is active at a time; this function respects
that contract by preferring y_haplotree_filter when both are non-empty.
"""
function apply_filters(features::Vector, request::FilterRequest)
    result = features

    result = apply_date_filter(
        result,
        request.date_min,
        request.date_max,
        request.include_undated
    )

    result = apply_filter(result, request.culture_filter, request.include_no_culture)

    if !isempty(request.y_haplotree_filter.terms)
        result = apply_y_haplotree_filter(result, request.y_haplotree_filter)
    else
        result = apply_filter(result, request.y_haplogroup_filter, request.include_no_y_haplogroup)
    end

    result = apply_filter(result, request.mtdna_filter, request.include_no_mtdna)

    result = apply_source_filter(result, request.source_filter)

    return result
end
