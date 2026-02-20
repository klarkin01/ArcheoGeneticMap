using Test
using DataFrames

push!(LOAD_PATH, @__DIR__)

include("../src/gpkg_maker.jl")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""Build a DataFrame from a Dict of column_name => values pairs."""
make_df(d::Dict) = DataFrame(d)

# ---------------------------------------------------------------------------

@testset "GpkgMaker Tests" begin

    @testset "find_column" begin

        df = make_df(Dict(
            "Sample ID" => ["S1"],
            "Latitude"  => [48.0],
            "Longitude" => [16.0],
            "CULTURE"   => ["Yamnaya"]   # non-standard casing
        ))

        @test find_column(df, ["Sample ID", "Object-ID"]) == "Sample ID"
        @test find_column(df, ["Latitude"])               == "Latitude"

        # case-insensitive fallback: "Culture" resolves to "CULTURE"
        @test find_column(df, ["Culture", "Simplified_Culture"]) == "CULTURE"

        # no match
        @test find_column(df, ["NonExistentCol", "AlsoMissing"]) === nothing

        # exact match preferred over case-insensitive when both exist
        df2 = make_df(Dict("Latitude" => [1.0], "LATITUDE" => [2.0]))
        @test find_column(df2, ["Latitude"]) == "Latitude"

    end

    @testset "resolve_columns" begin

        @testset "resolves all standard columns" begin
            df = make_df(Dict(
                "Sample ID"         => ["S1"],
                "Latitude"          => [48.0],
                "Longitude"         => [16.0],
                "Y haplogroup"      => ["R1b"],
                "MtDNA"             => ["H"],
                "Culture"           => ["Yamnaya"],
                "Average age calBP" => [5000.0],
                "FTDNA-Y-Haplotree" => ["R-M207>M173>M343"]
            ))
            cols = resolve_columns(df)
            @test cols.sample_id    == "Sample ID"
            @test cols.latitude     == "Latitude"
            @test cols.longitude    == "Longitude"
            @test cols.y_haplogroup == "Y haplogroup"
            @test cols.mtdna        == "MtDNA"
            @test cols.culture      == "Culture"
            @test cols.average_age  == "Average age calBP"
            @test cols.y_haplotree  == "FTDNA-Y-Haplotree"
        end

        @testset "optional columns are nothing when absent" begin
            df = make_df(Dict(
                "Sample ID" => ["S1"],
                "Latitude"  => [48.0],
                "Longitude" => [16.0]
            ))
            cols = resolve_columns(df)
            @test cols.y_haplogroup === nothing
            @test cols.mtdna        === nothing
            @test cols.culture      === nothing
            @test cols.average_age  === nothing
            @test cols.y_haplotree  === nothing
        end

        @testset "resolves alternate column names" begin
            df = make_df(Dict(
                "Object-ID"          => ["S1"],
                "lat"                => [48.0],
                "lon"                => [16.0],
                "Simplified_Culture" => ["Bell Beaker"],
                "Mean_BP"            => [4500.0]
            ))
            cols = resolve_columns(df)
            @test cols.sample_id   == "Object-ID"
            @test cols.latitude    == "lat"
            @test cols.longitude   == "lon"
            @test cols.culture     == "Simplified_Culture"
            @test cols.average_age == "Mean_BP"
        end

        @testset "errors on each missing required column" begin
            @test_throws ErrorException resolve_columns(make_df(Dict("Latitude" => [48.0], "Longitude" => [16.0])))
            @test_throws ErrorException resolve_columns(make_df(Dict("Sample ID" => ["S1"], "Longitude" => [16.0])))
            @test_throws ErrorException resolve_columns(make_df(Dict("Sample ID" => ["S1"], "Latitude" => [48.0])))
        end

    end

    @testset "build_samples" begin

        function standard_df_and_cols()
            df = make_df(Dict(
                "Sample ID"         => ["S1",     "S2",          "S3"],
                "Latitude"          => [48.0,      51.5,          -999.0],  # S3 out of range
                "Longitude"         => [16.0,       0.1,            0.0],
                "Y haplogroup"      => ["R1b",     "I2",           "G"],
                "MtDNA"             => ["H",        "U5",           "J"],
                "Culture"           => ["Yamnaya",  "Bell Beaker",  "Corded Ware"],
                "Average age calBP" => [5000.0,    4000.0,         3000.0],
                "FTDNA-Y-Haplotree" => ["R-M207>M173>M343", "I-M258>M223", "G-M201>P15"]
            ))
            df, resolve_columns(df)
        end

        @testset "parses valid rows, skips out-of-range coordinates" begin
            df, cols = standard_df_and_cols()
            @test length(build_samples(df, cols)) == 2
        end

        @testset "field values are correctly mapped" begin
            df, cols = standard_df_and_cols()
            s = build_samples(df, cols)[1]
            @test s.sample_id         == "S1"
            @test s.latitude          == 48.0
            @test s.longitude         == 16.0
            @test s.y_haplogroup      == "R1b"
            @test s.mtdna             == "H"
            @test s.culture           == "Yamnaya"
            @test s.average_age_calbp == 5000.0
            @test s.y_haplotree       == "R-M207>M173>M343"
        end

        @testset "sample_number is zero-padded sequential string" begin
            df, cols = standard_df_and_cols()
            samples = build_samples(df, cols)
            @test samples[1].sample_number == "000001"
            @test samples[2].sample_number == "000002"
        end

        @testset "rejects bad latitude and bad longitude independently" begin
            df = make_df(Dict(
                "Sample ID" => ["BadLat", "BadLon", "Good"],
                "Latitude"  => [-999.0,    10.0,    48.0],
                "Longitude" => [0.0,       999.0,   16.0]
            ))
            samples = build_samples(df, resolve_columns(df))
            @test length(samples) == 1
            @test samples[1].sample_id == "Good"
        end

        @testset "missing optional fields default to empty string" begin
            df = make_df(Dict("Sample ID" => ["S1"], "Latitude" => [48.0], "Longitude" => [16.0]))
            samples = build_samples(df, resolve_columns(df))
            @test samples[1].y_haplogroup == ""
            @test samples[1].mtdna        == ""
            @test samples[1].culture      == ""
            @test samples[1].y_haplotree  == ""
        end

        @testset "missing optional age is stored as missing" begin
            df = make_df(Dict("Sample ID" => ["S1"], "Latitude" => [48.0], "Longitude" => [16.0]))
            samples = build_samples(df, resolve_columns(df))
            @test ismissing(samples[1].average_age_calbp)
        end

        @testset "unparseable age value falls back to missing" begin
            df = make_df(Dict(
                "Sample ID"         => ["S1"],
                "Latitude"          => [48.0],
                "Longitude"         => [16.0],
                "Average age calBP" => ["not_a_number"]
            ))
            samples = build_samples(df, resolve_columns(df))
            @test ismissing(samples[1].average_age_calbp)
        end

        @testset "returns empty vector when all rows are invalid" begin
            df = make_df(Dict(
                "Sample ID" => ["S1", "S2"],
                "Latitude"  => [-999.0, -999.0],
                "Longitude" => [0.0,    0.0]
            ))
            @test isempty(build_samples(df, resolve_columns(df)))
        end

    end

    @testset "samples_to_geodataframe" begin

        samples = [
            ArcheoSample("000001", "S1", 48.0, 16.0, "R1b", "H",  "Yamnaya",     5000.0, "R-M207>M173>M343"),
            ArcheoSample("000002", "S2", 51.5,  0.1, "I2",  "U5", "Bell Beaker", missing, "I-M258>M223")
        ]

        @testset "correct row count" begin
            @test nrow(samples_to_geodataframe(samples)) == 2
        end

        @testset "all expected columns present" begin
            gdf = samples_to_geodataframe(samples)
            for col in [:sample_number, :sample_id, :latitude, :longitude,
                        :y_haplogroup, :mtdna, :culture, :average_age_calbp, :y_haplotree, :geometry]
                @test col in propertynames(gdf)
            end
        end

        @testset "field values are correct" begin
            gdf = samples_to_geodataframe(samples)
            @test gdf[1, :sample_id]     == "S1"
            @test gdf[1, :latitude]      == 48.0
            @test gdf[1, :y_haplogroup]  == "R1b"
            @test gdf[1, :y_haplotree]   == "R-M207>M173>M343"
            @test gdf[2, :sample_id]     == "S2"
            @test ismissing(gdf[2, :average_age_calbp])
        end

        @testset "errors on empty input" begin
            @test_throws ErrorException samples_to_geodataframe(ArcheoSample[])
        end

    end

end

println("All gpkg_maker tests passed!")
