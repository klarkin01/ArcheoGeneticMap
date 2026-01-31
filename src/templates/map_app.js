/**
 * ArcheoGeneticMap - Archaeological Sample Visualization
 * 
 * Frontend application using Alpine.js for state management
 * and Leaflet for map rendering.
 * 
 * Expects window.ArcheoGeneticMap_CONFIG to be set with:
 *   - center: [lat, lon]
 *   - zoom: initial zoom level
 *   - dateRange: { min, max } in cal BP
 *   - style: { pointColor, pointRadius, tileUrl, tileAttribution }
 */

// =============================================================================
// Map Layer Management (Leaflet)
// =============================================================================

let map = null;
let dataLayer = null;

/**
 * Initialize the Leaflet map with configuration from ARCHEOMAP_CONFIG
 */
function initMap() {
    const config = window.ArcheoGeneticMap.config;
    
    console.log('Initializing map...', config);
    
    try {
        map = L.map('map').setView(config.center, config.zoom);
        
        L.tileLayer(config.style.tileUrl, {
            attribution: config.style.tileAttribution
        }).addTo(map);
        
        console.log('Map initialized successfully');
        
        // Force a resize after a short delay to handle any layout issues
        setTimeout(() => {
            map.invalidateSize();
            console.log('Map size invalidated');
        }, 100);
        
    } catch (e) {
        console.error('Error initializing map:', e);
    }
}

/**
 * Update the map layer with filtered features
 * @param {Array} features - GeoJSON features to display
 */
function updateMapLayer(features) {
    const config = window.ArcheoGeneticMap.config;
    const pointColor = config.style.pointColor;
    const pointRadius = config.style.pointRadius;
    
    // Remove existing layer
    if (dataLayer) {
        map.removeLayer(dataLayer);
    }
    
    // Create new layer with filtered data
    const geojson = {
        type: 'FeatureCollection',
        features: features
    };
    
    dataLayer = L.geoJSON(geojson, {
        pointToLayer: function(feature, latlng) {
            return L.circleMarker(latlng, {
                radius: pointRadius,
                fillColor: pointColor,
                color: pointColor,
                weight: 1,
                opacity: 1,
                fillOpacity: 0.7
            });
        },
        onEachFeature: function(feature, layer) {
            layer.bindPopup(buildPopupContent(feature.properties));
        }
    }).addTo(map);
}

/**
 * Build HTML popup content from feature properties
 * @param {Object} props - Feature properties
 * @returns {string} HTML string for popup
 */
function buildPopupContent(props) {
    let content = '<b>Sample ID:</b> ' + props.sample_id;
    
    if (props.average_age_calbp) {
        content += '<br><b>Age:</b> ' + props.average_age_calbp + ' cal BP';
    }
    if (props.culture) {
        content += '<br><b>Culture:</b> ' + props.culture;
    }
    if (props.y_haplogroup) {
        content += '<br><b>Y Haplogroup:</b> ' + props.y_haplogroup;
    }
    if (props.mtdna) {
        content += '<br><b>mtDNA:</b> ' + props.mtdna;
    }
    
    return content;
}

// =============================================================================
// Alpine.js Filter Controller
// =============================================================================

/**
 * Alpine.js component for filter management and data state
 */
function filterController() {
    const config = window.ArcheoGeneticMap.config;
    
    return {
        // ---------------------------------------------------------------------
        // UI State
        // ---------------------------------------------------------------------
        sidebarOpen: true,
        sections: {
            dateRange: true,
            culture: false,
            yHaplogroup: false,
            mtdna: false
        },
        
        // ---------------------------------------------------------------------
        // Data State
        // ---------------------------------------------------------------------
        allFeatures: [],
        filteredFeatures: [],
        
        // Data range (will be recalculated from actual data)
        dataRange: {
            min: config.dateRange.min,
            max: config.dateRange.max
        },
        
        // ---------------------------------------------------------------------
        // Filter State
        // ---------------------------------------------------------------------
        filters: {
            // Note: dateMin is the MORE RECENT date (smaller BP number)
            // dateMax is the OLDER date (larger BP number)
            dateMin: config.dateRange.max,
            dateMax: config.dateRange.min,
            includeUndated: true
        },
        
        // ---------------------------------------------------------------------
        // Computed Properties
        // ---------------------------------------------------------------------
        get totalCount() {
            return this.allFeatures.length;
        },
        
        get filteredCount() {
            return this.filteredFeatures.length;
        },
        
        // ---------------------------------------------------------------------
        // Lifecycle
        // ---------------------------------------------------------------------
        async init() {
            console.log('Alpine init() starting...');
            
            try {
                // Initialize the Leaflet map
                initMap();
                
                // Fetch sample data from API
                console.log('Fetching data from /api/samples...');
                const response = await fetch('/api/samples');
                const data = await response.json();
                this.allFeatures = data.features;
                console.log('Loaded ' + this.allFeatures.length + ' features');
                
                // Recalculate date range from actual loaded data
                this.recalculateDateRange();
                
                // Apply initial filters
                this.applyFilters();
                console.log('Alpine init() complete');
                
            } catch (e) {
                console.error('Error in Alpine init():', e);
            }
        },
        
        // ---------------------------------------------------------------------
        // Date Range Methods
        // ---------------------------------------------------------------------
        
        /**
         * Recalculate the date range from loaded features
         */
        recalculateDateRange() {
            const ages = this.allFeatures
                .map(f => f.properties.average_age_calbp)
                .filter(a => a !== null && a !== undefined);
            
            if (ages.length > 0) {
                this.dataRange.min = Math.min(...ages);
                this.dataRange.max = Math.max(...ages);
                this.filters.dateMin = this.dataRange.max;
                this.filters.dateMax = this.dataRange.min;
                console.log('Date range: ' + this.dataRange.min + ' to ' + this.dataRange.max);
            }
        },
        
        /**
         * Handle date filter input changes
         * Ensures dateMin >= dateMax (in BP terms, more recent <= older)
         */
        onDateChange() {
            // Ensure proper ordering (dateMax should be <= dateMin in terms of BP values)
            if (this.filters.dateMin < this.filters.dateMax) {
                const temp = this.filters.dateMin;
                this.filters.dateMin = this.filters.dateMax;
                this.filters.dateMax = temp;
            }
            
            this.applyFilters();
        },
        
        /**
         * Calculate CSS style for the slider range highlight
         * @returns {Object} CSS style object with left and width percentages
         */
        sliderRangeStyle() {
            const range = this.dataRange.max - this.dataRange.min;
            if (range === 0) return { left: '0%', width: '100%' };
            
            const leftPercent = ((this.filters.dateMax - this.dataRange.min) / range) * 100;
            const rightPercent = ((this.filters.dateMin - this.dataRange.min) / range) * 100;
            
            return {
                left: leftPercent + '%',
                width: (rightPercent - leftPercent) + '%'
            };
        },
        
        // ---------------------------------------------------------------------
        // Filter Logic
        // ---------------------------------------------------------------------
        
        /**
         * Apply all active filters and update the map
         */
        applyFilters() {
            this.filteredFeatures = this.allFeatures.filter(feature => {
                return this.passesDateFilter(feature);
                // Future filters will be added here:
                // && this.passesCultureFilter(feature)
                // && this.passesYHaplogroupFilter(feature)
                // && this.passesMtdnaFilter(feature)
            });
            
            // Update the map display
            updateMapLayer(this.filteredFeatures);
        },
        
        /**
         * Check if a feature passes the date filter
         * @param {Object} feature - GeoJSON feature
         * @returns {boolean} True if feature passes the filter
         */
        passesDateFilter(feature) {
            const age = feature.properties.average_age_calbp;
            
            // Handle undated samples
            if (age === null || age === undefined) {
                return this.filters.includeUndated;
            }
            
            // Check if within range
            // Remember: dateMax is the OLDER date (larger BP), dateMin is MORE RECENT (smaller BP)
            return age >= this.filters.dateMax && age <= this.filters.dateMin;
        }
        
        // Future filter methods will be added here:
        // passesCultureFilter(feature) { ... }
        // passesYHaplogroupFilter(feature) { ... }
        // passesMtdnaFilter(feature) { ... }
    };
}
