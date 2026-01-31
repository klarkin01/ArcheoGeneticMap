using Test

# Add the src directory to the load path
push!(LOAD_PATH, joinpath(@__DIR__, "..", "src"))

using ArcheoGeneticMap

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
        @test settings.point_radius == 6
        
        # Test MapSettings with preset
        topo_settings = MapSettings(:topo)
        @test occursin("opentopomap", topo_settings.tile_url)
        
        # Test MapSettings with custom values
        custom = MapSettings(padding=2.0, point_color="#0000ff")
        @test custom.padding == 2.0
        @test custom.point_color == "#0000ff"
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
        
        # Test calculate_date_range
        geojson_with_dates = Dict(
            "type" => "FeatureCollection",
            "features" => [
                Dict(
                    "type" => "Feature",
                    "geometry" => Dict("type" => "Point", "coordinates" => [0.0, 0.0]),
                    "properties" => Dict("average_age_calbp" => 5000.0)
                ),
                Dict(
                    "type" => "Feature",
                    "geometry" => Dict("type" => "Point", "coordinates" => [1.0, 1.0]),
                    "properties" => Dict("average_age_calbp" => 10000.0)
                ),
                Dict(
                    "type" => "Feature",
                    "geometry" => Dict("type" => "Point", "coordinates" => [2.0, 2.0]),
                    "properties" => Dict("average_age_calbp" => nothing)  # undated
                )
            ]
        )
        
        min_age, max_age = calculate_date_range(geojson_with_dates)
        @test min_age == 5000.0
        @test max_age == 10000.0
        
        # Test date range with no dated samples
        geojson_no_dates = Dict(
            "type" => "FeatureCollection",
            "features" => [
                Dict(
                    "type" => "Feature",
                    "geometry" => Dict("type" => "Point", "coordinates" => [0.0, 0.0]),
                    "properties" => Dict("average_age_calbp" => nothing)
                )
            ]
        )
        
        min_age, max_age = calculate_date_range(geojson_no_dates)
        @test min_age == 0.0
        @test max_age == 50000.0
    end
    
    @testset "Templates" begin
        # Test that template files exist
        template_path = joinpath(@__DIR__, "..", "src", "templates")
        @test isfile(joinpath(template_path, "map_base.html"))
        @test isfile(joinpath(template_path, "map_styles.css"))
        @test isfile(joinpath(template_path, "map_app.js"))
        
        # Test config rendering
        settings = MapSettings()
        config = MapConfig(45.0, -75.0, 6, 5000.0, 15000.0, settings)
        
        html = render_map_html(config)
        
        # Check that key elements are present
        @test occursin("ArcheoGeneticMap_CONFIG", html)
        @test occursin("filterController", html)
        @test occursin("leaflet", lowercase(html))
        @test occursin("#e41a1c", html)  # default point color
    end
end

println("All tests passed!")
