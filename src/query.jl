"""
    ArcheoGeneticMap.Query

Orchestration layer for processing filter queries.
Combines filtering, color assignment, and metadata computation.
"""

export process_query, assign_colors!

# =============================================================================
# Color Assignment
# =============================================================================

"""
    assign_colors!(features::Vector, request::FilterRequest, 
                   available_cultures::Vector{String},
                   date_range::Tuple{Float64, Float64}) -> Nothing

Assign colors to features in-place based on the request's color settings.
Adds a `_color` property to each feature's properties.

# Arguments
- `features`: Vector of GeoJSON feature Dicts (modified in place)
- `request`: FilterRequest specifying color_by and color_ramp
- `available_cultures`: List of cultures for categorical coloring
- `date_range`: (min, max) date range for age-based coloring
"""
function assign_colors!(features::Vector,
                        request::FilterRequest,
                        available_cultures::Vector{String},
                        date_range::Tuple{Float64, Float64})
    color_by = request.color_by
    
    # Default color from config
    default_color = DEFAULT_POINT_COLOR
    
    for feature in features
        props = feature["properties"]
        
        if color_by == :age
            age = get(props, "average_age_calbp", nothing)
            props["_color"] = color_for_age(
                age,
                date_range[1],
                date_range[2],
                request.color_ramp,
                default_color = default_color
            )
        elseif color_by == :culture
            culture = get(props, "culture", nothing)
            props["_color"] = color_for_culture(
                culture,
                available_cultures,
                default_color = default_color
            )
        else
            # No coloring - use default
            props["_color"] = default_color
        end
    end
    
    return nothing
end

# =============================================================================
# Query Processing
# =============================================================================

"""
    process_query(all_features::Vector, request::FilterRequest) -> QueryResponse

Process a complete filter query.

This is the main entry point for the /api/query endpoint. It:
1. Applies all filters to get matching features
2. Computes metadata (counts, available options)
3. Assigns colors to filtered features
4. Returns the complete response

# Arguments
- `all_features`: Complete dataset as vector of GeoJSON feature Dicts
- `request`: FilterRequest from the frontend

# Returns
QueryResponse with filtered features and metadata
"""
function process_query(all_features::Vector, request::FilterRequest)
    # Step 1: Apply filters
    filtered_features = apply_filters(all_features, request)
    
    # Step 2: Build metadata (includes cascading options)
    meta = build_filter_meta(all_features, filtered_features, request)
    
    # Step 3: Assign colors to filtered features
    # Use the date range from filtered features for better color distribution
    filtered_date_range = if isempty(filtered_features)
        (meta.date_statistics.min, meta.date_statistics.max)
    else
        calculate_date_range(filtered_features)
    end
    
    assign_colors!(
        filtered_features,
        request,
        meta.available_cultures,
        filtered_date_range
    )
    
    # Step 4: Build and return response
    return QueryResponse(filtered_features, meta)
end

"""
    process_query(geojson::Dict, request::FilterRequest) -> QueryResponse

Convenience method that accepts a GeoJSON FeatureCollection Dict.
"""
function process_query(geojson::Dict, request::FilterRequest)
    return process_query(geojson["features"], request)
end
