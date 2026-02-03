/**
 * ArcheoGeneticMap - Archaeological Sample Visualization
 * 
 * Frontend application using Alpine.js for state management
 * and Leaflet for map rendering.
 * 
 * Dependencies (loaded before this file via templates.jl):
 *   - ColorRamps: Color ramp definitions and interpolation
 *   - PiecewiseScale: Slider-to-value conversion with outlier compression
 *   - PopupBuilder: HTML popup generation for map markers
 * 
 * Expects window.ArcheoGeneticMap.config to be set with:
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
 * Initialize the Leaflet map with configuration from ArcheoGeneticMap.config
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
 * Get color for a feature based on its age and current filter settings
 * @param {number|null} age - Age value in cal BP (larger = older, smaller = younger)
 * @param {Object} colorSettings - Object with colorRampEnabled, selectedColorRamp, dateMin, dateMax
 * @param {string} defaultColor - Default color when ramp is disabled
 * @returns {string} Hex color string
 */
function getFeatureColor(feature, colorSettings, defaultColor) {
    const age = feature.properties.average_age_calbp;
    const culture = feature.properties.culture;
    
    // Culture coloring takes precedence if enabled
    if (colorSettings.colorByCultureEnabled) {
        if (culture) {
            return colorSettings.getCultureColor(culture);
        }
        return defaultColor;
    }
    
    // Age-based coloring
    if (!colorSettings.colorRampEnabled) {
        return defaultColor;
    }
    
    // Data convention: cal BP (Before Present)
    // Larger numbers = OLDER (more ancient), smaller numbers = YOUNGER (more recent)
    // dateMin = smaller number = younger bound
    // dateMax = larger number = older bound
    
    const youngerBound = colorSettings.dateMin;  // smaller numeric value = more recent
    const olderBound = colorSettings.dateMax;    // larger numeric value = older
    const range = olderBound - youngerBound;
    
    if (range === 0) {
        return ColorRamps.interpolate(colorSettings.selectedColorRamp, 0.5);
    }
    
    // Normalize: t=0 for oldest samples (large BP), t=1 for youngest samples (small BP)
    const t = (olderBound - age) / range;
    
    return ColorRamps.interpolate(colorSettings.selectedColorRamp, t);
}

/**
 * Update the map layer with filtered features
 * @param {Array} features - GeoJSON features to display
 * @param {Object} colorSettings - Color ramp settings
 */
function updateMapLayer(features, colorSettings = null) {
    const config = window.ArcheoGeneticMap.config;
    const defaultColor = config.style.pointColor;
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
            const color = colorSettings 
                ? getFeatureColor(feature, colorSettings, defaultColor)
                : defaultColor;
            
            return L.circleMarker(latlng, {
                radius: pointRadius,
                fillColor: color,
                color: color,
                weight: 1,
                opacity: 1,
                fillOpacity: 0.7
            });
        },
        onEachFeature: function(feature, layer) {
            layer.bindPopup(PopupBuilder.build(feature.properties));
        }
    }).addTo(map);
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
        cultureDropdownOpen: false,
        sections: {
            dateRange: false,
            culture: false,
            yHaplogroup: false,
            mtdna: false
        },
        
        // ---------------------------------------------------------------------
        // Data State
        // ---------------------------------------------------------------------
        allFeatures: [],
        filteredFeatures: [],
        
        // Full data range and percentiles (from server)
        dataRange: {
            min: config.dateRange.min,
            max: config.dateRange.max
        },
        
        // Percentile bounds for piecewise scaling (from server)
        percentiles: {
            p2: config.dateRange.p2,
            p98: config.dateRange.p98
        },
        
        // Piecewise scale instance (created on init with server-provided values)
        dateScale: null,

        // Culture data (from server)
        availableCultures: window.ArcheoGeneticMap.config.cultureStats?.cultureNames || [],
        
        // ---------------------------------------------------------------------
        // Filter State
        // ---------------------------------------------------------------------
        filters: {
            // Actual date values for filtering (cal BP: larger = older)
            dateMin: config.dateRange.min,  // younger bound (smaller BP value)
            dateMax: config.dateRange.max,  // older bound (larger BP value)
            includeUndated: Config.defaults.includeUndated,
            includeNoCulture: Config.defaults.includeNoCulture
        },
        
        selectedCultures: [],

        // Slider positions (0-1000 scale)
        sliderPositions: {
            min: PiecewiseScale.SLIDER_MIN,  // right side = younger (small BP values)
            max: PiecewiseScale.SLIDER_MAX   // left side = older (large BP values)
        },
        
        // ---------------------------------------------------------------------
        // Color Ramp State
        // ---------------------------------------------------------------------
        colorRampEnabled: Config.defaults.colorRampEnabled,
        selectedColorRamp: Config.defaults.colorRamp,
        availableColorRamps: ColorRamps.options(),
        colorByCultureEnabled: false,
        
        // ---------------------------------------------------------------------
        // Computed Properties
        // ---------------------------------------------------------------------
        get totalCount() {
            return this.allFeatures.length;
        },
        
        get filteredCount() {
            return this.filteredFeatures.length;
        },
        
        /**
         * Get current color settings for map rendering
         */
        get colorSettings() {
            return {
                colorRampEnabled: this.colorRampEnabled,
                selectedColorRamp: this.selectedColorRamp,
                dateMin: this.filters.dateMin,
                dateMax: this.filters.dateMax,
                // Culture coloring
                colorByCultureEnabled: this.colorByCultureEnabled,
                availableCultures: this.availableCultures,
                getCultureColor: (culture) => this.getCultureColor(culture)
            };
        },
        get allCulturesSelected() {
            return this.selectedCultures.length === this.availableCultures.length;
        },
        
        // ---------------------------------------------------------------------
        // Lifecycle
        // ---------------------------------------------------------------------
        async init() {
            console.log('Alpine init() starting...');
            
            try {
                // Initialize the Leaflet map
                initMap();
                
                // Create the piecewise scale using server-provided statistics
                this.dateScale = PiecewiseScale.create(
                    this.dataRange.min,
                    this.dataRange.max,
                    this.percentiles.p2,
                    this.percentiles.p98
                );
                
                // Set initial filter range (p2 to p98 for better default view)
                this.filters.dateMin = this.percentiles.p2;
                this.filters.dateMax = this.percentiles.p98;
                
                // Set initial slider positions to match
                this.sliderPositions.min = this.dateScale.toSlider(this.filters.dateMin);
                this.sliderPositions.max = this.dateScale.toSlider(this.filters.dateMax);
                
                console.log('Date range:', this.dataRange);
                console.log('Percentiles:', this.percentiles);
                
                // Fetch sample data from API
                console.log('Fetching data from /api/samples...');
                const response = await fetch('/api/samples');
                const data = await response.json();
                this.allFeatures = data.features;
                console.log('Loaded ' + this.allFeatures.length + ' features');
                
                // Initialize with all cultures selected
                this.selectedCultures = [...this.availableCultures];

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
         * Handle slider input changes
         * Converts slider position to date value and updates filters
         * Cal BP: slider left (0) = youngest, slider right (1000) = oldest
         */
        onSliderInput(which) {
            if (!this.dateScale) return;
            
            if (which === 'min') {
                // "min" slider controls the younger/left bound (smaller BP values)
                this.filters.dateMin = Math.round(this.dateScale.toValue(this.sliderPositions.min));
            } else {
                // "max" slider controls the older/right bound (larger BP values)
                this.filters.dateMax = Math.round(this.dateScale.toValue(this.sliderPositions.max));
            }
            
            // Ensure proper ordering: dateMin should be <= dateMax (younger <= older in BP)
            if (this.filters.dateMin > this.filters.dateMax) {
                const temp = this.filters.dateMin;
                this.filters.dateMin = this.filters.dateMax;
                this.filters.dateMax = temp;
                // Also swap slider positions
                const tempSlider = this.sliderPositions.min;
                this.sliderPositions.min = this.sliderPositions.max;
                this.sliderPositions.max = tempSlider;
            }
            
            this.applyFilters();
        },
        
        /**
         * Handle direct date input changes (from number inputs)
         * Updates slider positions to match
         * Cal BP: dateMin = younger (smaller), dateMax = older (larger)
         */
        onDateChange() {
            if (!this.dateScale) return;
            
            // Ensure proper ordering: dateMin <= dateMax (younger <= older in BP)
            if (this.filters.dateMin > this.filters.dateMax) {
                const temp = this.filters.dateMin;
                this.filters.dateMin = this.filters.dateMax;
                this.filters.dateMax = temp;
            }
            
            // Clamp to data range
            this.filters.dateMin = this.dateScale.clamp(this.filters.dateMin);
            this.filters.dateMax = this.dateScale.clamp(this.filters.dateMax);
            
            // Update slider positions
            this.sliderPositions.min = this.dateScale.toSlider(this.filters.dateMin);
            this.sliderPositions.max = this.dateScale.toSlider(this.filters.dateMax);
            
            this.applyFilters();
        },
        
        /**
         * Handle color ramp toggle or selection change
         */
        onColorRampChange() {
            // Re-render the map with current features and new color settings
            updateMapLayer(this.filteredFeatures, this.colorSettings);
        },
        
        /**
         * Calculate CSS style for the slider range highlight
         * Uses slider positions directly (already in 0-1000 scale)
         * Cal BP: sliderPositions.min = left/younger, sliderPositions.max = right/older
         */
        sliderRangeStyle() {
            if (!this.dateScale) {
                return { left: '0%', width: '100%' };
            }
            return this.dateScale.rangeStyle(this.sliderPositions.min, this.sliderPositions.max);
        },
        
        /**
         * Generate a preview gradient for the selected color ramp
         * @returns {string} CSS linear-gradient string
         */
        colorRampGradient() {
            return ColorRamps.gradient(this.selectedColorRamp);
        },

        // ---------------------------------------------------------------------
        // Culture Filter Methods
        // ---------------------------------------------------------------------

        /**
         * Get summary text for the multi-select toggle button
         */
        selectedCulturesSummary() {
            if (this.selectedCultures.length === 0) {
                return 'None selected';
            }
            if (this.selectedCultures.length === this.availableCultures.length) {
                return 'All cultures';
            }
            if (this.selectedCultures.length === 1) {
                return this.selectedCultures[0];
            }
            return this.selectedCultures.length + ' cultures selected';
        },

        /**
         * Toggle a single culture selection
         */
        toggleCulture(culture) {
            const index = this.selectedCultures.indexOf(culture);
            if (index === -1) {
                this.selectedCultures.push(culture);
            } else {
                this.selectedCultures.splice(index, 1);
            }
            this.applyFilters();
        },

        /**
         * Toggle all cultures on/off
         */
        toggleAllCultures() {
            if (this.allCulturesSelected) {
                this.selectedCultures = [];
            } else {
                this.selectedCultures = [...this.availableCultures];
            }
            this.applyFilters();
        },

        /**
         * Check if a feature passes the culture filter
         */
        passesCultureFilter(feature) {
            const culture = feature.properties.culture;
            
            // Handle samples with no culture
            if (culture === null || culture === undefined || culture === '') {
                return this.filters.includeNoCulture;
            }
            
            // Check if culture is in selected list
            return this.selectedCultures.includes(culture);
        },

        /**
         * Get cultures to show in legend (limits to selected cultures)
         */
        selectedCulturesForLegend() {
            // Show selected cultures, or all if none selected
            return this.selectedCultures.length > 0 
                ? this.selectedCultures.slice(0, 20)  // Limit legend items
                : this.availableCultures.slice(0, 20);
        },

        /**
         * Get color for a culture (categorical coloring)
         */
        getCultureColor(culture) {
            // Uses a categorical palette - you'll want to add this to config.js
            const palette = Config.culturePalette || [
                '#e41a1c', '#377eb8', '#4daf4a', '#984ea3', '#ff7f00',
                '#ffff33', '#a65628', '#f781bf', '#999999', '#66c2a5',
                '#fc8d62', '#8da0cb', '#e78ac3', '#a6d854', '#ffd92f'
            ];
            const index = this.availableCultures.indexOf(culture);
            return palette[index % palette.length];
        },

        /**
         * Handle color by culture toggle
         */
        onColorByCultureChange() {
            // Disable color by age if enabling color by culture
            if (this.colorByCultureEnabled) {
                this.colorRampEnabled = false;
            }
            updateMapLayer(this.filteredFeatures, this.colorSettings);
        },

        // ---------------------------------------------------------------------
        // Filter Logic
        // ---------------------------------------------------------------------
        
        /**
         * Apply all active filters and update the map
         */
        applyFilters() {
            this.filteredFeatures = this.allFeatures.filter(feature => {
                return this.passesDateFilter(feature) 
                    && this.passesCultureFilter(feature);
                // Future filters will be added here:
                // && this.passesYHaplogroupFilter(feature)
                // && this.passesMtdnaFilter(feature)
            });
            
            // Update the map display with color settings
            updateMapLayer(this.filteredFeatures, this.colorSettings);
        },
        
        /**
         * Check if a feature passes the date filter
         * @param {Object} feature - GeoJSON feature
         * @returns {boolean} True if feature passes the filter
         * Cal BP: dateMin = younger/smaller value, dateMax = older/larger value
         */
        passesDateFilter(feature) {
            const age = feature.properties.average_age_calbp;
            
            // Handle undated samples
            if (age === null || age === undefined) {
                return this.filters.includeUndated;
            }
            
            // Check if within range
            // dateMin is the younger/smaller BP value, dateMax is the older/larger BP value
            return age >= this.filters.dateMin && age <= this.filters.dateMax;
        }
        
        // Future filter methods will be added here:
        // passesCultureFilter(feature) { ... }
        // passesYHaplogroupFilter(feature) { ... }
        // passesMtdnaFilter(feature) { ... }
    };
}
