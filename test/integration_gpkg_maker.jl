using Test
using DataFrames
using GeoDataFrames

push!(LOAD_PATH, @__DIR__)

include("../src/gpkg_maker.jl")

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

const FIXTURE_CSV  = joinpath(@__DIR__, "fixtures", "sample.csv")
const TEMP_GPKG    = joinpath(tempdir(), "test_output_$(getpid()).gpkg")

# ---------------------------------------------------------------------------

@testset "GpkgMaker Integration Tests" begin

    # Run the full pipeline once; all testsets below inspect the result
    @testset "pipeline completes without error" begin
        @test_nowarn process_csv_to_geopackage(FIXTURE_CSV, TEMP_GPKG)
        @test isfile(TEMP_GPKG)
    end

    # Load the written file for subsequent assertions
    gdf = GeoDataFrames.read(TEMP_GPKG)

    @testset "correct sample count" begin
        # 12 rows in fixture; 2 should be skipped:
        #   SAMPLE009 - invalid latitude (999.0)
        #   SAMPLE010 - missing latitude
        @test nrow(gdf) == 10
    end

    @testset "expected columns are present" begin
        for col in [:sample_number, :sample_id, :latitude, :longitude,
                    :y_haplogroup, :mtdna, :culture, :average_age_calbp, :geometry]
            @test col in propertynames(gdf)
        end
    end

    @testset "fully populated sample is correct" begin
        row = gdf[gdf.sample_id .== "SAMPLE001", :]
        @test nrow(row) == 1
        @test row[1, :latitude]          ≈ 48.2092
        @test row[1, :longitude]         ≈ 16.3728
        @test row[1, :y_haplogroup]      == "R1b1a1b"
        @test row[1, :mtdna]             == "H1"
        @test row[1, :culture]           == "Bell Beaker"
        @test row[1, :average_age_calbp] ≈ 4200.0
    end

    @testset "missing optional fields default to empty string" begin
        # SAMPLE005 has no Y-hap, no mtDNA
        row = gdf[gdf.sample_id .== "SAMPLE005", :]
        @test row[1, :y_haplogroup] == ""
        @test row[1, :mtdna]        == ""
        @test row[1, :culture]      == "Pitted Ware"
    end

    @testset "missing age is stored as missing" begin
        # SAMPLE006 has no Mean_BP value
        row = gdf[gdf.sample_id .== "SAMPLE006", :]
        @test ismissing(row[1, :average_age_calbp])
    end

    @testset "unparseable age is stored as missing" begin
        # SAMPLE008 has Mean_BP = "not_a_date"
        row = gdf[gdf.sample_id .== "SAMPLE008", :]
        @test ismissing(row[1, :average_age_calbp])
    end

    @testset "invalid coordinate row is excluded" begin
        # SAMPLE009 has latitude 999.0
        @test nrow(gdf[gdf.sample_id .== "SAMPLE009", :]) == 0
    end

    @testset "missing coordinate row is excluded" begin
        # SAMPLE010 has no latitude
        @test nrow(gdf[gdf.sample_id .== "SAMPLE010", :]) == 0
    end

    @testset "sample_number is zero-padded and sequential" begin
        @test gdf[1, :sample_number] == "000001"
        @test gdf[2, :sample_number] == "000002"
        @test gdf[10, :sample_number] == "000010"
    end

    @testset "geometry is present and non-empty" begin
        for geom in gdf.geometry
            @test !isnothing(geom)
        end
    end

end

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

isfile(TEMP_GPKG) && rm(TEMP_GPKG)

println("All gpkg_maker integration tests passed!")
