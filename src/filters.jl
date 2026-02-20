"""
    ArcheoGeneticMap.Filters

Filter application logic for GeoJSON features.
Each filter function takes a collection of features and returns a filtered subset.
"""

export apply_date_filter, apply_culture_filter, apply_y_haplogroup_filter, apply_mtdna_filter, apply_y_haplotree_filter, apply_filters

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
        
        if age === nothing || ismissing(age)
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
    apply_culture_filter(features, culture_filter::CultureFilter, include_no_culture::Bool) -> Vector

Filter features by culture.
"""
function apply_culture_filter(features::Vector, 
                              culture_filter::CultureFilter, 
                              include_no_culture::Bool)
    selected = Set(culture_filter.selected)
    
    if isempty(selected) && !include_no_culture
        return Dict{String, Any}[]
    end
    
    return filter(features) do feature
        culture = get(feature["properties"], "culture", nothing)
        
        if culture === nothing || ismissing(culture) || culture == ""
            return include_no_culture
        end
        
        if isempty(selected)
            return false
        end
        
        return culture in selected
    end
end

"""
    apply_y_haplogroup_filter(features, haplogroup_filter::HaplogroupFilter, include_no_y_haplogroup::Bool) -> Vector

Filter features by Y-haplogroup.
"""
function apply_y_haplogroup_filter(features::Vector,
                                   haplogroup_filter::HaplogroupFilter,
                                   include_no_y_haplogroup::Bool)
    selected = Set(haplogroup_filter.selected)
    
    if isempty(selected) && !include_no_y_haplogroup
        return Dict{String, Any}[]
    end
    
    return filter(features) do feature
        y_hap = get(feature["properties"], "y_haplogroup", nothing)
        
        if y_hap === nothing || ismissing(y_hap) || y_hap == ""
            return include_no_y_haplogroup
        end
        
        if isempty(selected)
            return false
        end
        
        return y_hap in selected
    end
end

"""
    apply_mtdna_filter(features, mtdna_filter::HaplogroupFilter, include_no_mtdna::Bool) -> Vector

Filter features by mtDNA haplogroup.
"""
function apply_mtdna_filter(features::Vector,
                           mtdna_filter::HaplogroupFilter,
                           include_no_mtdna::Bool)
    selected = Set(mtdna_filter.selected)
    
    if isempty(selected) && !include_no_mtdna
        return Dict{String, Any}[]
    end
    
    return filter(features) do feature
        mtdna = get(feature["properties"], "mtdna", nothing)
        
        if mtdna === nothing || ismissing(mtdna) || mtdna == ""
            return include_no_mtdna
        end
        
        if isempty(selected)
            return false
        end
        
        return mtdna in selected
    end
end

# =============================================================================
# Combined Filter Application
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
    # No terms → no filter applied
    if isempty(y_haplotree_filter.terms)
        return features
    end

    # Normalise terms to lowercase once
    terms_lower = Set(lowercase(t) for t in y_haplotree_filter.terms)

    return filter(features) do feature
        path = get(feature["properties"], "y_haplotree", nothing)

        # Hide samples with no haplotree data when filter is active
        if path === nothing || ismissing(path) || path == ""
            return false
        end

        # Split path on '>', trim whitespace, compare lowercase tokens
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

Note: y_haplogroup_filter and y_haplotree_filter are mutually exclusive.
When y_haplotree_filter has terms, y_haplogroup_filter is ignored, and vice versa.
The frontend enforces that only one is active at a time; this function respects
that contract by preferring y_haplotree_filter when both are non-empty.
"""
function apply_filters(features::Vector, request::FilterRequest)
    result = features

    # Apply date filter
    result = apply_date_filter(
        result,
        request.date_min,
        request.date_max,
        request.include_undated
    )

    # Apply culture filter
    result = apply_culture_filter(
        result,
        request.culture_filter,
        request.include_no_culture
    )

    # Apply Y-haplogroup OR Y-haplotree filter (mutually exclusive)
    if !isempty(request.y_haplotree_filter.terms)
        # Y-haplotree takes precedence
        result = apply_y_haplotree_filter(result, request.y_haplotree_filter)
    else
        result = apply_y_haplogroup_filter(
            result,
            request.y_haplogroup_filter,
            request.include_no_y_haplogroup
        )
    end

    # Apply mtDNA filter
    result = apply_mtdna_filter(
        result,
        request.mtdna_filter,
        request.include_no_mtdna
    )

    return result
end
