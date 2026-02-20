"""
    maker_config.jl

Configuration for the GeoPackage maker pipeline.
Defines the column name candidates used when mapping source CSV files
to the canonical ArcheoSample fields.

To support a new CSV format, add a new ColumnConfig entry to DEFAULT_CONFIGS.
Entries are tried in order; the first one that resolves all three required
columns (sample_id, latitude, longitude) is used.
"""

# =============================================================================
# Column Mapping Configuration
# =============================================================================

"""
Defines candidate column names for each ArcheoSample field.
Multiple candidates are listed in order of preference.
"""
struct ColumnConfig
    sample_id_cols::Vector{String}
    latitude_cols::Vector{String}
    longitude_cols::Vector{String}
    y_haplogroup_cols::Vector{String}
    mtdna_cols::Vector{String}
    culture_cols::Vector{String}
    average_age_cols::Vector{String}
    y_haplotree_cols::Vector{String}
end

"""
Column name candidates to try when reading a CSV, in order of preference.
The first ColumnConfig whose required fields (sample_id, latitude, longitude)
are all resolved against the CSV will be used.
"""
const DEFAULT_CONFIGS = [
    ColumnConfig(
        ["Sample ID", "Object-ID"],
        ["Latitude", "latitude", "lat", "Lat", "LAT"],
        ["Longitude", "longitude", "lon", "Lon", "lng", "long", "LON"],
        ["Y haplogroup", "Y-chr haplogroup", "Y-Haplotree-Public"],
        ["MtDNA", "MT haplogroup", "mtDNA-Haplotree"],
        ["Culture", "Simplified_Culture"],
        ["Average age calBP", "Age, BP cal midpoint rescorr", "Mean_BP"],
        ["FTDNA-Y-Haplotree", "Y-FTDNA", "FTDNA Y Haplotree"]
    )
]
