"""
    ArcheoGeneticMap.IO

Data loading and conversion for GeoPackage files.
"""

using ArchGDAL

export read_geopackage, geojson_to_featurecollection

"""
    read_geopackage(filepath::String) -> Dict

Read a GeoPackage file and convert to GeoJSON-compatible Dict structure.

Returns a FeatureCollection with features containing:
- geometry: Point with [lon, lat] coordinates
- properties: sample_id, y_haplogroup, mtdna, culture, average_age_calbp
"""
function read_geopackage(filepath::String)
    dataset = ArchGDAL.read(filepath)
    layer = ArchGDAL.getlayer(dataset, 0)
    
    features = Vector{Dict{String, Any}}()
    
    for feature in layer
        geom = ArchGDAL.getgeom(feature)
        lon = ArchGDAL.getx(geom, 0)
        lat = ArchGDAL.gety(geom, 0)
        
        # Extract properties with safe fallbacks
        props = extract_properties(feature)
        
        push!(features, Dict{String, Any}(
            "type" => "Feature",
            "geometry" => Dict{String, Any}(
                "type" => "Point",
                "coordinates" => [lon, lat]
            ),
            "properties" => props
        ))
    end
    
    return Dict{String, Any}(
        "type" => "FeatureCollection",
        "features" => features
    )
end

"""
    extract_properties(feature) -> Dict{String, Any}

Safely extract standard properties from an ArchGDAL feature.
Converts empty strings and missing values to nothing.
"""
function extract_properties(feature)
    props = Dict{String, Any}()
    
    # Required field
    props["sample_id"] = safe_get_field(feature, "sample_id", "")
    
    # Optional string fields - convert empty to nothing
    for field in ["y_haplogroup", "mtdna", "culture", "y_haplotree"]
        value = safe_get_field(feature, field, "")
        props[field] = (value == "" || ismissing(value)) ? nothing : value
    end
    
    # Numeric field
    avg_age = safe_get_field(feature, "average_age_calbp", nothing)
    props["average_age_calbp"] = ismissing(avg_age) ? nothing : avg_age
    
    return props
end

"""
    safe_get_field(feature, fieldname, default)

Safely retrieve a field value from an ArchGDAL feature.
Returns default if the field doesn't exist or throws an error.
"""
function safe_get_field(feature, fieldname::String, default)
    try
        return ArchGDAL.getfield(feature, fieldname)
    catch
        return default
    end
end
