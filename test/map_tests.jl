using Test

# Add the project directory to the load path
push!(LOAD_PATH, @__DIR__)

include("../src/ArcheoGeneticMap.jl")
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
        # CultureFilter has a single `selected` field (no mode).
        # Empty selected = no cultures explicitly chosen.
        cf_empty = CultureFilter()
        @test isempty(cf_empty.selected)
        
        cf_selected = CultureFilter(["Yamnaya", "Bell Beaker"])
        @test length(cf_selected.selected) == 2
        @test "Yamnaya" in cf_selected.selected
        @test "Bell Beaker" in cf_selected.selected
        
        cf_explicit_empty = CultureFilter(String[])
        @test isempty(cf_explicit_empty.selected)
        
        # Test FilterRequest construction with defaults
        fr = FilterRequest()
        @test fr.date_min === nothing
        @test fr.date_max === nothing
        @test fr.include_undated == true
        @test isempty(fr.culture_filter.selected)
        @test fr.color_ramp == "viridis"
        @test isempty(fr.y_haplotree_filter.terms)
        @test fr.y_haplotree_color_ramp == "viridis"

        # Test YHaplotreeFilter construction
        ytf_empty = YHaplotreeFilter()
        @test isempty(ytf_empty.terms)

        ytf_terms = YHaplotreeFilter(["M269", "L51"])
        @test length(ytf_terms.terms) == 2
        @test "M269" in ytf_terms.terms
        @test "L51" in ytf_terms.terms
        
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
        @test "Yamnaya" in fr_custom.culture_filter.selected
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
        color = color_for_age(nothing, 0.0, 10000.0, "viridis", default_color="#808080")
        @test color == "#808080"
        
        # Test color for culture — requires culture, cultures vector, and ramp name
        cultures = ["Yamnaya", "Bell Beaker", "Corded Ware"]
        color = color_for_culture("Yamnaya", cultures, "viridis")
        @test startswith(color, "#")
        
        # Different cultures get different colors
        color1 = color_for_culture("Yamnaya", cultures, "viridis")
        color2 = color_for_culture("Bell Beaker", cultures, "viridis")
        @test color1 != color2
        
        # Missing culture returns default
        color = color_for_culture(nothing, cultures, "viridis", default_color="#808080")
        @test color == "#808080"
    end
    
    @testset "Filters" begin
        # Test features
        # - 5000 Yamnaya (dated, in-range for 4000-9000)
        # - 8000 Bell Beaker (dated, in-range for 4000-9000)
        # - 12000 Yamnaya (dated, out of 4000-9000 range)
        # - nothing Corded Ware (undated)
        # - 6000 nothing/no culture (dated, in-range, no culture)
        features = [
            Dict("properties" => Dict("average_age_calbp" => 5000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => 8000.0, "culture" => "Bell Beaker")),
            Dict("properties" => Dict("average_age_calbp" => 12000.0, "culture" => "Yamnaya")),
            Dict("properties" => Dict("average_age_calbp" => nothing, "culture" => "Corded Ware")),
            Dict("properties" => Dict("average_age_calbp" => 6000.0, "culture" => nothing))
        ]
        
        # Test date filter - with range, include undated
        # In-range dated: 5000, 8000, 6000 → 3; undated (Corded Ware) included → total 4
        filtered = apply_date_filter(features, 4000.0, 9000.0, true)
        @test length(filtered) == 4
        
        # Test date filter - exclude undated
        # In-range dated only: 5000, 8000, 6000 → 3
        filtered = apply_date_filter(features, 4000.0, 9000.0, false)
        @test length(filtered) == 3
        
        # Test date filter - no constraints, include undated → all 5
        filtered = apply_date_filter(features, nothing, nothing, true)
        @test length(filtered) == 5
        
        # Test culture filter - empty selected, include_no_culture=true
        # Empty selected means no named cultures pass the filter (isempty → return false for cultured)
        # Only no-culture samples pass when include_no_culture=true
        filtered = apply_culture_filter(features, CultureFilter(), true)
        @test length(filtered) == 1  # Only the no-culture (6000) sample
        
        # Test culture filter - empty selected, include_no_culture=false → nothing passes
        filtered = apply_culture_filter(features, CultureFilter(), false)
        @test length(filtered) == 0
        
        # Test culture filter - selected cultures, include_no_culture=false
        filtered = apply_culture_filter(features, CultureFilter(["Yamnaya"]), false)
        @test length(filtered) == 2  # Two Yamnaya samples
        
        # Test culture filter - selected + include_no_culture
        filtered = apply_culture_filter(features, CultureFilter(["Yamnaya"]), true)
        @test length(filtered) == 3  # Two Yamnaya + one no-culture sample
        
        # Test combined filters via FilterRequest
        # date 4000-9000, no undated, Yamnaya + Bell Beaker cultures, no no-culture samples
        request = FilterRequest(
            date_min = 4000.0,
            date_max = 9000.0,
            include_undated = false,
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false
        )
        filtered = apply_filters(features, request)
        @test length(filtered) == 2  # 5000 Yamnaya and 8000 Bell Beaker
    end

    @testset "Y-Haplotree Filter" begin
        # Features with y_haplotree paths
        features = [
            Dict("properties" => Dict(
                "y_haplotree" => "R-M207>M173>M343>L754>L389>P297>M269>L23>L51",
                "average_age_calbp" => 5000.0
            )),
            Dict("properties" => Dict(
                "y_haplotree" => "I-M258>M223>L801>CTS616",
                "average_age_calbp" => 4500.0
            )),
            Dict("properties" => Dict(
                "y_haplotree" => "G-M201>P15>L30>L32>L43>L141",
                "average_age_calbp" => 7000.0
            )),
            Dict("properties" => Dict(
                "y_haplotree" => "",
                "average_age_calbp" => 3000.0
            )),
            Dict("properties" => Dict(
                "average_age_calbp" => 6000.0
            ))
        ]

        # Empty filter = no filter applied (all pass)
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter())
        @test length(filtered) == 5

        # Token "M269" matches the R path
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["M269"]))
        @test length(filtered) == 1
        @test get(filtered[1]["properties"], "y_haplotree", "") == "R-M207>M173>M343>L754>L389>P297>M269>L23>L51"

        # Token "L141" matches only the G path
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["L141"]))
        @test length(filtered) == 1
        @test get(filtered[1]["properties"], "y_haplotree", "") == "G-M201>P15>L30>L32>L43>L141"

        # Two terms: "M269" OR "M223" → R and I paths
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["M269", "M223"]))
        @test length(filtered) == 2

        # Case-insensitive: "m269" should match "M269" token
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["m269"]))
        @test length(filtered) == 1

        # Partial match must NOT succeed: "L14" should not match "L141"
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["L14"]))
        @test length(filtered) == 0

        # Samples with empty or missing y_haplotree hidden when filter active
        filtered = apply_y_haplotree_filter(features, YHaplotreeFilter(["M269"]))
        paths = [get(f["properties"], "y_haplotree", "") for f in filtered]
        @test "" ∉ paths

        # Mutual exclusivity via apply_filters:
        # When y_haplotree_filter has terms, y_haplogroup_filter is ignored
        feat2 = [
            Dict("properties" => Dict(
                "y_haplotree"  => "R-M207>M173>M343>M269",
                "y_haplogroup" => "R1b",
                "average_age_calbp" => 5000.0
            )),
            Dict("properties" => Dict(
                "y_haplotree"  => "I-M258>M223",
                "y_haplogroup" => "I2",
                "average_age_calbp" => 4500.0
            ))
        ]
        # y_haplotree_filter active → y_haplogroup_filter should be ignored
        req = FilterRequest(
            y_haplogroup_filter = HaplogroupFilter("", ["R1b"]),
            include_no_y_haplogroup = false,
            y_haplotree_filter = YHaplotreeFilter(["M223"])
        )
        filtered = apply_filters(feat2, req)
        @test length(filtered) == 1  # only I sample (M223 match), R1b haplogroup filter ignored
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
        @test "Yamnaya" in available      # Has a 12000 sample
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
        
        # Test process_query with default request.
        # Default CultureFilter() is empty; default include_no_culture=true.
        # Empty selected + include_no_culture=true → only no-culture samples pass culture filter.
        # Neither feature has no culture, so filtered_count = 0.
        # To get all features, explicitly select both cultures.
        request_all = FilterRequest(
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false
        )
        response = process_query(features, request_all)
        
        @test response.meta.total_count == 2
        @test response.meta.filtered_count == 2
        @test length(response.features) == 2
        
        # Check that colors were assigned
        @test haskey(response.features[1]["properties"], "_color")
        @test startswith(response.features[1]["properties"]["_color"], "#")
        
        # Test with color by age
        request_age = FilterRequest(
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false,
            color_by = :age
        )
        response_age = process_query(features, request_age)
        @test haskey(response_age.features[1]["properties"], "_color")
        
        # Test with color by culture
        request_culture = FilterRequest(
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false,
            color_by = :culture
        )
        response_culture = process_query(features, request_culture)
        @test haskey(response_culture.features[1]["properties"], "_color")
        
        # Test cascading filter metadata
        @test length(response.meta.available_cultures) == 2
        @test "Yamnaya" in response.meta.available_cultures
        @test "Bell Beaker" in response.meta.available_cultures
        
        # Test with date filter that excludes Bell Beaker
        request_filtered = FilterRequest(
            date_min = 4000.0,
            date_max = 6000.0,
            culture_filter = CultureFilter(["Yamnaya", "Bell Beaker"]),
            include_no_culture = false
        )
        response_filtered = process_query(features, request_filtered)
        @test response_filtered.meta.filtered_count == 1
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
        # In the flat project layout, template files live alongside ArcheoGeneticMap.jl.
        # When running from the project root, @__DIR__ points to the project root.
        # Per the README, the actual layout uses src/templates/, but the web interface
        # uses a flat layout where templates are served from the project root.
        # Adjust this path to match your actual directory structure.
        templates_dir = joinpath(@__DIR__, "..", "src", "templates")
        @test isfile(joinpath(templates_dir, "map_base.html"))
        @test isfile(joinpath(templates_dir, "map_styles.css"))
        @test isfile(joinpath(templates_dir, "map_app.js"))
        @test isfile(joinpath(templates_dir, "piecewise_scale.js"))
        @test isfile(joinpath(templates_dir, "popup_builder.js"))
        
        # These files should NOT exist (removed in refactor)
        @test !isfile(joinpath(templates_dir, "config.js"))
        @test !isfile(joinpath(templates_dir, "color_ramps.js"))
    end
end

println("All tests passed!")
