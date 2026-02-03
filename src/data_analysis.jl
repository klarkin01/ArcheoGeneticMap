"""
    ArcheoGeneticMap.DataAnalysis

Statistical analysis functions for sample attributes (dates, haplogroups, etc.).
"""

export calculate_date_range, calculate_date_statistics, calculate_culture_statistics

"""
    calculate_date_range(geojson::Dict) -> Tuple{Float64, Float64}

Extract the minimum and maximum ages from a GeoJSON FeatureCollection.
Returns (min_age, max_age) in cal BP.

If no dated samples exist, returns default values from config.
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
    ages = Float64[]
    
    for feature in geojson["features"]
        age = get(feature["properties"], "average_age_calbp", nothing)
        if age !== nothing && !ismissing(age)
            push!(ages, Float64(age))
        end
    end
    
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
    identify_unique_cultures(geojson::Dict) -> Vector{String}

Identify unique culture names from a GeoJSON FeatureCollection.
Returns a sorted vector of unique culture names, excluding missing or empty values.
"""
function calculate_culture_statistics(geojson::Dict)
    culture_set = Set{String}()
    for feature in geojson["features"]
        culture = get(feature["properties"], "culture", nothing)
        if culture !== nothing && !ismissing(culture) && culture != ""
            push!(culture_set, String(culture))
        end
    end
    sorted_set = sort(collect(culture_set))
    return CultureStatistics(sorted_set)
end