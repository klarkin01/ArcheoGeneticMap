"""
    ArcheoGeneticMap.Geometry

Spatial calculations and utility functions.
"""

export calculate_bounds, calculate_center, calculate_date_range

# MapBounds is defined in types.jl and available in the same module scope

"""
    calculate_bounds(geojson::Dict, padding::Float64) -> MapBounds

Calculate the geographic bounding box from a GeoJSON FeatureCollection.
Adds padding (in degrees) to all sides.
"""
function calculate_bounds(geojson::Dict, padding::Float64)
    features = geojson["features"]
    
    if isempty(features)
        # Default to world view if no features
        return MapBounds(-180.0, 180.0, -90.0, 90.0)
    end
    
    lons = [f["geometry"]["coordinates"][1] for f in features]
    lats = [f["geometry"]["coordinates"][2] for f in features]
    
    MapBounds(
        minimum(lons) - padding,
        maximum(lons) + padding,
        minimum(lats) - padding,
        maximum(lats) + padding
    )
end

"""
    calculate_center(bounds::MapBounds) -> Tuple{Float64, Float64}

Calculate the center point of a bounding box.
Returns (center_lat, center_lon).
"""
function calculate_center(bounds::MapBounds)
    center_lat = (bounds.min_lat + bounds.max_lat) / 2
    center_lon = (bounds.min_lon + bounds.max_lon) / 2
    return (center_lat, center_lon)
end

"""
    calculate_date_range(geojson::Dict) -> Tuple{Float64, Float64}

Extract the minimum and maximum ages from a GeoJSON FeatureCollection.
Returns (min_age, max_age) in cal BP.

If no dated samples exist, returns (0.0, 50000.0) as a reasonable default
for archaeological data.
"""
function calculate_date_range(geojson::Dict)
    ages = Float64[]
    
    for feature in geojson["features"]
        age = get(feature["properties"], "average_age_calbp", nothing)
        if age !== nothing && !ismissing(age)
            push!(ages, Float64(age))
        end
    end
    
    if isempty(ages)
        return (0.0, 50000.0)
    end
    
    return (minimum(ages), maximum(ages))
end

"""
    estimate_zoom_level(bounds::MapBounds) -> Int

Estimate an appropriate zoom level based on the geographic extent.
Returns a value between 1 and 18.
"""
function estimate_zoom_level(bounds::MapBounds)
    lat_span = bounds.max_lat - bounds.min_lat
    lon_span = bounds.max_lon - bounds.min_lon
    max_span = max(lat_span, lon_span)
    
    # Rough heuristic based on span
    if max_span > 100
        return 2
    elseif max_span > 50
        return 3
    elseif max_span > 20
        return 4
    elseif max_span > 10
        return 5
    elseif max_span > 5
        return 6
    elseif max_span > 2
        return 7
    elseif max_span > 1
        return 8
    else
        return 10
    end
end
