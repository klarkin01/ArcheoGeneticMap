"""
    ArcheoGeneticMap.Filters

Filter application logic for GeoJSON features.
Each filter function takes a collection of features and returns a filtered subset.
"""

export apply_date_filter, apply_culture_filter, apply_filters

# =============================================================================
# Individual Filter Functions
# =============================================================================

"""
    apply_date_filter(features, date_min, date_max, include_undated::Bool) -> Vector

Filter features by date range.

# Arguments
- `features`: Vector of GeoJSON feature Dicts
- `date_min`: Minimum age in cal BP (nothing = no lower bound)
- `date_max`: Maximum age in cal BP (nothing = no upper bound)
- `include_undated`: Whether to include samples without dates

# Returns
Filtered vector of features
"""
function apply_date_filter(features::Vector, 
                           date_min::Union{Float64, Nothing}, 
                           date_max::Union{Float64, Nothing}, 
                           include_undated::Bool)
    # No date constraints and including undated = return all
    if date_min === nothing && date_max === nothing && include_undated
        return features
    end
    
    return filter(features) do feature
        age = get(feature["properties"], "average_age_calbp", nothing)
        
        # Handle undated samples
        if age === nothing || ismissing(age)
            return include_undated
        end
        
        age = Float64(age)
        
        # Check bounds
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

Filter features by culture with explicit control over samples without culture data.

# Arguments
- `features`: Vector of GeoJSON feature Dicts
- `culture_filter`: CultureFilter with selected cultures
- `include_no_culture`: Whether to include samples without culture data

# Returns
Filtered vector of features
"""
function apply_culture_filter(features::Vector, 
                              culture_filter::CultureFilter, 
                              include_no_culture::Bool)
    selected = Set(culture_filter.selected)
    
    # If no cultures selected and not including no-culture samples, return empty
    if isempty(selected) && !include_no_culture
        return Dict{String, Any}[]
    end
    
    return filter(features) do feature
        culture = get(feature["properties"], "culture", nothing)
        
        # Handle samples with no culture
        if culture === nothing || ismissing(culture) || culture == ""
            return include_no_culture
        end
        
        # If no cultures selected, only show no-culture samples (already handled above)
        if isempty(selected)
            return false
        end
        
        return culture in selected
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

# Arguments
- `features`: Vector of GeoJSON feature Dicts
- `request`: FilterRequest specifying all filter parameters

# Returns
Filtered vector of features
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
    result = apply_culture_filter(result, request.culture_filter, request.include_no_culture)
    
    return result
end
