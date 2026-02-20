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
                   meta::FilterMeta,
                   date_range::Tuple{Float64, Float64}) -> Nothing

Assign colors to features in-place based on the request's color settings.
Adds a `_color` property to each feature's properties.
"""
function assign_colors!(features::Vector,
                        request::FilterRequest,
                        meta::FilterMeta,
                        date_range::Tuple{Float64, Float64})
    color_by = request.color_by
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
                request.culture_filter.selected,
                request.culture_color_ramp,
                default_color = default_color
            )
        elseif color_by == :y_haplogroup
            y_hap = get(props, "y_haplogroup", nothing)
            props["_color"] = color_for_haplogroup(
                y_hap,
                request.y_haplogroup_filter.selected,
                request.y_haplogroup_color_ramp,
                default_color = default_color
            )
        elseif color_by == :mtdna
            mtdna = get(props, "mtdna", nothing)
            props["_color"] = color_for_haplogroup(
                mtdna,
                request.mtdna_filter.selected,
                request.mtdna_color_ramp,
                default_color = default_color
            )
        elseif color_by == :y_haplotree
            path = get(props, "y_haplotree", nothing)
            props["_color"] = color_for_y_haplotree_term(
                path,
                request.y_haplotree_filter.terms,
                request.y_haplotree_color_ramp,
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
        meta,
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
