/**
 * ArcheoGeneticMap - Archaeological Sample Visualization
 * 
 * Frontend application using Alpine.js for state management
 * and Leaflet for map rendering.
 * 
 * This is a "thin client" that delegates filtering and color assignment
 * to the backend via /api/query. The frontend handles:
 *   - UI state (sidebar, dropdowns, sections)
 *   - Slider position tracking and conversion
 *   - Map rendering with server-provided colors
 *   - Debounced server requests
 * 
 * Dependencies (loaded before this file):
 *   - PiecewiseScale: Slider-to-value conversion with outlier compression
 *   - PopupBuilder: HTML popup generation for map markers
 */

// =============================================================================
// Utilities
// =============================================================================

let mapInitialized = false;

/**
 * Simple debounce function
 */
function debounce(func, wait) {
    let timeout;
    return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
    };
}

// =============================================================================
// Map Layer Management (Leaflet)
// =============================================================================

let map = null;
let dataLayer = null;

/**
 * Initialize the Leaflet map
 */
function initMap(config) {
    
    if (mapInitialized) {
        console.log('Map already initialized, skipping...');
        return;
    }
    
    console.log('Initializing map...', config);
    
    try {
        map = L.map('map').setView(config.map.center, config.map.zoom);
        
        L.tileLayer(config.map.tileUrl, {
            attribution: config.map.tileAttribution
        }).addTo(map);
        
        mapInitialized = true;
        console.log('Map initialized successfully');
        
        // Force a resize after a short delay to handle any layout issues
        setTimeout(() => {
            map.invalidateSize();
        }, 100);
        
    } catch (e) {
        console.error('Error initializing map:', e);
    }
}

/**
 * Update the map layer with features from server
 * Colors are already assigned by the server in feature.properties._color
 */
function updateMapLayer(features, defaultColor, pointRadius) {
    // Remove existing layer
    if (dataLayer) {
        map.removeLayer(dataLayer);
    }
    
    // Create new layer
    const geojson = {
        type: 'FeatureCollection',
        features: features
    };
    
    dataLayer = L.geoJSON(geojson, {
        pointToLayer: function(feature, latlng) {
            // Use server-assigned color, fall back to default
            const color = feature.properties._color || defaultColor;
            
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
 * Alpine.js component for filter management
 */
function filterController() {
    return {
        // ---------------------------------------------------------------------
        // UI State
        // ---------------------------------------------------------------------
        sidebarOpen: true,
        cultureDropdownOpen: false,
        loading: false,
        sections: {
            dateRange: false,
            culture: false,
            yHaplogroup: false,
            mtdna: false
        },
        
        // ---------------------------------------------------------------------
        // Server-provided Configuration
        // ---------------------------------------------------------------------
        config: null,
        
        // ---------------------------------------------------------------------
        // Server-provided Metadata (updated with each query)
        // ---------------------------------------------------------------------
        meta: {
            totalCount: 0,
            filteredCount: 0,
            availableCultures: [],
            availableDateRange: { min: 0, max: 50000 },
            dateStatistics: { min: 0, max: 50000, p2: 0, p98: 50000 },
            cultureLegend: []
        },
        
        // ---------------------------------------------------------------------
        // Filter State (sent to server)
        // ---------------------------------------------------------------------
        filters: {
            dateMin: null,
            dateMax: null,
            includeUndated: true,
            includeNoCulture: true
        },
        
        // Culture filter state - just track selected cultures
        selectedCultures: [],
        
        // Color settings
        colorBy: null,  // null, 'age', 'culture'
        colorRamp: 'viridis',
        
        // Slider positions (0-1000 scale, UI concern only)
        sliderPositions: { min: 0, max: 1000 },
        
        // Piecewise scale instance
        dateScale: null,
        
        // Current features (from server)
        features: [],
        
        // ---------------------------------------------------------------------
        // Computed Properties
        // ---------------------------------------------------------------------
        get totalCount() {
            return this.meta.totalCount;
        },
        
        get filteredCount() {
            return this.meta.filteredCount;
        },
        
        get availableCultures() {
            return this.meta.availableCultures;
        },
        
        get allCulturesSelected() {
            return this.selectedCultures.length === this.availableCultures.length;
        },
        
        get availableColorRamps() {
            if (!this.config) return [];
            return Object.entries(this.config.colorRamps).map(([value, ramp]) => ({
                value,
                label: ramp.label
            }));
        },
        
        // ---------------------------------------------------------------------
        // Lifecycle
        // ---------------------------------------------------------------------
        async init() {
            console.log('Alpine init() starting...');
            
            try {
                // Fetch configuration from server
                console.log('Fetching config from /api/config...');
                const configResponse = await fetch('/api/config');
                this.config = await configResponse.json();
                console.log('Config loaded:', this.config);
                
                // Initialize the Leaflet map
                initMap(this.config);
                
                // Set up date scale from server-provided statistics
                const stats = this.config.dateStatistics;
                this.dateScale = PiecewiseScale.create(
                    stats.min,
                    stats.max,
                    stats.p2,
                    stats.p98
                );
                
                // Set initial filter range (p2 to p98 for better default view)
                this.filters.dateMin = stats.p2;
                this.filters.dateMax = stats.p98;
                
                // Set initial slider positions
                this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
                this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
                
                // Initialize culture selection to all
                this.selectedCultures = [...this.config.allCultures];
                
                // Set defaults
                this.filters.includeUndated = this.config.defaults.includeUndated;
                this.filters.includeNoCulture = this.config.defaults.includeNoCulture;
                this.colorRamp = this.config.defaults.colorRamp;
                
                // Fetch initial data
                await this.applyFilters();
                
                console.log('Alpine init() complete');
                
            } catch (e) {
                console.error('Error in Alpine init():', e);
            }
        },
        
        // ---------------------------------------------------------------------
        // Server Communication
        // ---------------------------------------------------------------------
        
        /**
         * Build the request payload for /api/query
         */
        buildQueryPayload() {
            return {
                dateMin: this.filters.dateMin,
                dateMax: this.filters.dateMax,
                includeUndated: this.filters.includeUndated,
                selectedCultures: this.selectedCultures,
                includeNoCulture: this.filters.includeNoCulture,
                colorBy: this.colorBy,
                colorRamp: this.colorRamp
            };
        },
        
        /**
         * Send query to server and update state
         */
        async applyFilters() {
            if (!this.config) return;
            
            this.loading = true;
            
            try {
                const payload = this.buildQueryPayload();
                console.log('Sending query:', payload);
                
                const response = await fetch('/api/query', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload)
                });
                
                const data = await response.json();
                
                if (data.error) {
                    console.error('Query error:', data.message);
                    return;
                }
                
                // Update state from response
                this.features = data.features;
                this.meta = data.meta;
                
                // Update map
                updateMapLayer(
                    this.features,
                    this.config.defaults.pointColor,
                    this.config.defaults.pointRadius
                );
                
                console.log('Query complete:', this.meta.filteredCount, 'features');
                
            } catch (e) {
                console.error('Error in applyFilters:', e);
            } finally {
                this.loading = false;
            }
        },
        
        /**
         * Debounced version for slider input
         */
        applyFiltersDebounced: debounce(function() {
            this.applyFilters();
        }, 200),
        
        // ---------------------------------------------------------------------
        // Date Range Methods
        // ---------------------------------------------------------------------
        
        /**
         * Handle slider input changes
         */
        onSliderInput(which) {
            if (!this.dateScale) return;
            
            if (which === 'min') {
                // Left slider controls the older (higher BP) values
                this.filters.dateMax = Math.round(this.dateScale.toValue(1000-this.sliderPositions.min));
            } else {
                // Right slider controls the younger (lower BP) values
                this.filters.dateMin = Math.round(this.dateScale.toValue(1000-this.sliderPositions.max));
            }
            
            // Use debounced version for slider dragging
            this.applyFiltersDebounced();
        },
        
        /**
         * Handle direct date input changes
         */
        onDateChange() {
            if (!this.dateScale) return;
            
            // Clamp to data range
            this.filters.dateMin = this.dateScale.clamp(this.filters.dateMin);
            this.filters.dateMax = this.dateScale.clamp(this.filters.dateMax);
            
            // Update slider positions
            this.sliderPositions.min = 1000 - this.dateScale.toSlider(this.filters.dateMax);
            this.sliderPositions.max = 1000 - this.dateScale.toSlider(this.filters.dateMin);
            
            this.applyFilters();
        },
        
        /**
         * Calculate CSS style for the slider range highlight
         */
        sliderRangeStyle() {
            if (!this.dateScale) {
                return { left: '0%', width: '100%' };
            }
            return this.dateScale.rangeStyle(this.sliderPositions.min, this.sliderPositions.max);
        },
        
        // ---------------------------------------------------------------------
        // Color Methods
        // ---------------------------------------------------------------------
        
        /**
         * Handle color by age toggle
         */
        onColorByAgeChange() {
            if (this.colorBy === 'age') {
                this.colorBy = null;
            } else {
                this.colorBy = 'age';
            }
            this.applyFilters();
        },
        
        /**
         * Handle color ramp selection change
         */
        onColorRampChange() {
            if (this.colorBy === 'age') {
                this.applyFilters();
            }
        },
        
        /**
         * Handle color by culture toggle
         */
        onColorByCultureChange() {
            if (this.colorBy === 'culture') {
                this.colorBy = null;
            } else {
                this.colorBy = 'culture';
            }
            this.applyFilters();
        },
        
        // ---------------------------------------------------------------------
        // Culture Filter Methods
        // ---------------------------------------------------------------------

        /**
         * Get summary text for the multi-select toggle button
         */
        selectedCulturesSummary() {
            const count = this.selectedCultures.length;
            const total = this.availableCultures.length;
            
            if (count === 0) {
                return 'None selected';
            }
            if (count === total) {
                return 'All cultures';
            }
            if (count === 1) {
                return this.selectedCultures[0];
            }
            return count + ' cultures selected';
        },

        /**
         * Toggle a single culture selection
         */
        toggleCulture(culture) {
            const index = this.selectedCultures.indexOf(culture);
            if (index === -1) {
                // Add culture
                this.selectedCultures.push(culture);
            } else {
                // Remove culture
                this.selectedCultures.splice(index, 1);
            }
            this.applyFilters();
        },

        /**
         * Toggle all cultures on/off
         */
        toggleAllCultures() {
            if (this.allCulturesSelected) {
                // Deselect all
                this.selectedCultures = [];
            } else {
                // Select all
                this.selectedCultures = [...this.availableCultures];
            }
            this.applyFilters();
        },
        
        /**
         * Check if a culture is currently selected
         */
        isCultureSelected(culture) {
            return this.selectedCultures.includes(culture);
        },

        /**
         * Get cultures to show in legend (from server-provided legend)
         */
        cultureLegendItems() {
            return this.meta.cultureLegend || [];
        },
        
        /**
         * Generate a preview gradient for the selected color ramp
         */
        colorRampGradient() {
            if (!this.config || !this.config.colorRamps[this.colorRamp]) {
                return 'transparent';
            }
            const colors = this.config.colorRamps[this.colorRamp].colors;
            return 'linear-gradient(to right, ' + colors.join(', ') + ')';
        }
    };
}
