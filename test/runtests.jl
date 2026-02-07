using Test

# Add the project directory to the load path
push!(LOAD_PATH, @__DIR__)

include("ArcheoGeneticMap.jl")
using .ArcheoGeneticMap

@testset "ArcheoGeneticMap Tests" begin
    
    @testset "Types" begin
        # Test MapBounds construction
        bounds = MapBounds(-10.0, 10.0, -5.0, 5.0)
        @test bounds.min_lon == -10.0
        @test bounds.max_lon == 10.0
        @test bounds.min_lat == -5.0
        @test bounds.max_lat == 5.0
        
        # Test MapSettings with defaults
        settings = MapSettings()
        @test settings.padding == 5.0
        @test settings.initial_zoom == 6
        @test settings.point_color == "#e41a1c"
        @test settings.point_radius == 4
        
        # Test MapSettings with preset
        topo_settings = MapSettings(:topo)
        @test occursin("opentopomap", topo_settings.tile_url)
        
        # Test MapSettings with custom values
        custom = MapSettings(padding=2.0, point_color="#0000ff")
        @test custom.padding == 2.0
        @test custom.point_color == "#0000ff"
        
        # Test DateStatistics construction
        date_stats = DateStatistics(100.0, 10000.0, 500.0, 9000.0)
        @test date_stats.min == 100.0
        @test date_stats.max == 10000.0
        @test date_stats.p2 == 500.0
        @test date_stats.p98 == 9000.0
        
        # Test CultureFilter construction
        cf_all = CultureFilter()
        @test cf_all.mode == :all
        @test isempty(cf_all.selected)
        
        cf_selected = CultureFilter(["Yamnaya", "Bell Beaker"])
        @test cf_selected.mode == :selected
        @test length(cf_selected.selected) == 2
        
        cf_none = CultureFilter(:none, String[])
        @test cf_none.mode == :none
        
        # Test FilterRequest construction
        fr = FilterRequest()
        @test fr.date_min === nothing
        @test fr.date_max === nothing
        @test fr.include_undated == true
        @test fr.culture_filter.mode == :all
        @test fr.color_ramp == "viridis"
        
        fr_custom = FilterRequest(
            date_min = 5000.0,
            date_max = 10000.0,
            include_undated = false,
            culture_filter = CultureFilter(["Yamnaya"]),
            color_by = :age
        )
        @test fr_custom.date_min == 5000.0
        @test fr_custom.date_max == 10000.0
        @test fr_custom.include_undated == false
        @test fr_custom.color_by == :age
    end
    
    @testset "Colors" begin
        # Test hex to RGB conversion
        r, g, b = hex_to_rgb("#ff0000")
        @test r == 255
        @test g == 0
        @test b == 0
        
        r, g, b = hex_to_rgb("00ff00")
        @test r == 0
        @test g == 255
        @test b == 0
        
        # Test color interpolation
        color = interpolate_color("viridis", 0.0)
        @test startswith(color, "#")
        
        color = interpolate_color("viridis", 1.0)
        @test startswith(color, "#")
        
        color = interpolate_color("viridis", 0.5)
        @test startswith(color, "#")
        
        # Test color for age
        color = color_for_age(5000.0, 0.0, 10000.0, "viridis")
        @test startswith(color, "#")
        
        # Test missing age returns default
        color = color_for_age(nothing, 0.0, 10000.0, "viridis", default_color="#gray")
        @test color == "#gray"
        
        # Test color for culture
        cultures = ["Yamnaya", "Bell Beaker", "Corded Ware"]
        color = color_for_culture("Yamnaya", cultures)
        @test startswith(color, "#")
        
        # Different cultures get different colors
        color1 = color_for_culture("Yamnaya", cultures)
        color2 = color_for_culture("Bell Beaker", cultures)
        @test color1 != color2
    end
    
    @testset "Filters" begin
        # Create test features
        features = [
            Dict("properties" => Dict("average_age_calbp" => 5000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => 8000.0, "culture" => "Bell Beaker")),
            Dict("properties" => Dict("average_age_calbp" => 12000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => nothing, "culture" => "Corded Ware")),
            Dict("properties" => Dict("average_age_calbp" => 6000.0, "culture" => nothing))
        ]
        
        # Test date filter - with range
        filtered = apply_date_filter(features, 4000.0, 9000.0, true)
        @test length(filtered) == 3  # 5000, 8000, and undated
        
        # Test date filter - exclude undated
        filtered = apply_date_filter(features, 4000.0, 9000.0, false)
        @test length(filtered) == 2  # 5000 and 8000
        
        # Test date filter - no constraints
        filtered = apply_date_filter(features, nothing, nothing, true)
        @test length(filtered) == 5
        
        # Test culture filter - all
        filtered = apply_culture_filter(features, CultureFilter(:all, String[]), true)
        @test length(filtered) == 5
        
        # Test culture filter - selected
        filtered = apply_culture_filter(features, CultureFilter(["Yamnaya"]), false)
        @test length(filtered) == 2  # Two Yamnaya samples
        
        # Test culture filter - none
        filtered = apply_culture_filter(features, CultureFilter(:none, String[]), false)
        @test length(filtered) == 0
        
        # Test combined filters
        request = FilterRequest(
            date_min = 4000.0,
            date_max = 10000.0,
            include_undated = false,
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false
        )
        filtered = apply_filters(features, request)
        @test length(filtered) == 2  # 5000 Yamnaya and 8000 Bell Beaker
    end
    
    @testset "Analysis" begin
        # Test features
        features = [
            Dict("properties" => Dict("average_age_calbp" => 5000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => 8000.0, "culture" => "Bell Beaker")),
            Dict("properties" => Dict("average_age_calbp" => 12000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => nothing, "culture" => "Corded Ware"))
        ]
        
        # Test extract_ages
        ages = extract_ages(features)
        @test length(ages) == 3
        @test 5000.0 in ages
        @test 12000.0 in ages
        
        # Test extract_cultures
        cultures = extract_cultures(features)
        @test length(cultures) == 3
        @test "Yamnaya" in cultures
        @test "Bell Beaker" in cultures
        @test "Corded Ware" in cultures
        
        # Test compute_available_cultures with date filter (cascading filter test)
        available = compute_available_cultures(features, date_min=4000.0, date_max=9000.0, include_undated=false)
        @test "Yamnaya" in available
        @test "Bell Beaker" in available
        @test !("Corded Ware" in available)  # Corded Ware is undated, excluded
        
        # With include_undated=true, Corded Ware should be included
        available = compute_available_cultures(features, date_min=4000.0, date_max=9000.0, include_undated=true)
        @test "Corded Ware" in available
        
        # Test that date range excludes cultures outside range
        available = compute_available_cultures(features, date_min=10000.0, date_max=15000.0, include_undated=false)
        @test "Yamnaya" in available  # Has a 12000 sample
        @test !("Bell Beaker" in available)  # Only has 8000 sample
        
        # Test calculate_date_range
        min_age, max_age = calculate_date_range(features)
        @test min_age == 5000.0
        @test max_age == 12000.0
        
        # Test calculate_date_statistics
        stats = calculate_date_statistics(features)
        @test stats.min == 5000.0
        @test stats.max == 12000.0
    end
    
    @testset "Query" begin
        # Test features with geometry
        features = [
            Dict(
                "type" => "Feature",
                "geometry" => Dict("type" => "Point", "coordinates" => [0.0, 0.0]),
                "properties" => Dict("average_age_calbp" => 5000.0, "culture" => "Yamnaya")
            ),
            Dict(
                "type" => "Feature",
                "geometry" => Dict("type" => "Point", "coordinates" => [1.0, 1.0]),
                "properties" => Dict("average_age_calbp" => 8000.0, "culture" => "Bell Beaker")
            )
        ]
        
        # Test process_query with default request
        request = FilterRequest()
        response = process_query(features, request)
        
        @test response.meta.total_count == 2
        @test response.meta.filtered_count == 2
        @test length(response.features) == 2
        
        # Check that colors were assigned
        @test haskey(response.features[1]["properties"], "_color")
        @test startswith(response.features[1]["properties"]["_color"], "#")
        
        # Test with color by age
        request_age = FilterRequest(color_by = :age)
        response_age = process_query(features, request_age)
        @test haskey(response_age.features[1]["properties"], "_color")
        
        # Test with color by culture
        request_culture = FilterRequest(color_by = :culture)
        response_culture = process_query(features, request_culture)
        @test haskey(response_culture.features[1]["properties"], "_color")
        
        # Test cascading filter metadata
        @test length(response.meta.available_cultures) == 2
        @test "Yamnaya" in response.meta.available_cultures
        @test "Bell Beaker" in response.meta.available_cultures
        
        # Test with date filter that excludes Bell Beaker
        request_filtered = FilterRequest(date_min = 4000.0, date_max = 6000.0)
        response_filtered = process_query(features, request_filtered)
        @test response_filtered.meta.filtered_count == 1
        # Available cultures should still show what's in range
        @test "Yamnaya" in response_filtered.meta.available_cultures
    end
    
    @testset "Geometry" begin
        # Test calculate_center
        bounds = MapBounds(-10.0, 10.0, -5.0, 5.0)
        center_lat, center_lon = calculate_center(bounds)
        @test center_lat == 0.0
        @test center_lon == 0.0
        
        # Test calculate_bounds with sample GeoJSON
        geojson = Dict(
            "type" => "FeatureCollection",
            "features" => [
                Dict(
                    "type" => "Feature",
                    "geometry" => Dict("type" => "Point", "coordinates" => [0.0, 0.0])
                ),
                Dict(
                    "type" => "Feature", 
                    "geometry" => Dict("type" => "Point", "coordinates" => [10.0, 5.0])
                )
            ]
        )
        
        bounds = calculate_bounds(geojson, 1.0)
        @test bounds.min_lon == -1.0
        @test bounds.max_lon == 11.0
        @test bounds.min_lat == -1.0
        @test bounds.max_lat == 6.0
    end
    
    @testset "Templates" begin
        # Test that template files exist in templates directory
        templates_dir = joinpath(@__DIR__, "src", "templates")
        @test isfile(joinpath(templates_dir, "map_base.html"))
        @test isfile(joinpath(templates_dir, "map_styles.css"))
        @test isfile(joinpath(templates_dir, "map_app.js"))
        @test isfile(joinpath(templates_dir, "piecewise_scale.js"))
        @test isfile(joinpath(templates_dir, "popup_builder.js"))
        
        # config.js and color_ramps.js should NOT exist (removed in refactor)
        @test !isfile(joinpath(templates_dir, "config.js"))
        @test !isfile(joinpath(templates_dir, "color_ramps.js"))
    end
end

println("All tests passed!")
