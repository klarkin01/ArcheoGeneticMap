/**
 * Spiderifier Module
 *
 * Detects overlapping map markers and spiderifies them:
 *
 *   HOVER  → reveals spokes (or summary popup for large clusters)
 *            dismissed on mouseout if not locked
 *   CLICK  → locks the spider open; mouseout no longer dismisses it
 *   CLICK ORIGIN AGAIN → dismisses that specific locked spider
 *
 * Multiple clusters can be locked simultaneously and are fully independent.
 *
 * Overlap detection:
 *   - Exact lat/lon match: always grouped
 *   - Pixel proximity at current zoom: grouped when within pixelRadius px
 *
 * Usage:
 *   Spiderifier.attach(map, dataLayer, options);
 *   Spiderifier.detach();   // call before removing/replacing dataLayer
 *
 * Dependencies: Leaflet (L), PopupBuilder
 */

const Spiderifier = (function () {

    // =========================================================================
    // Module State
    // =========================================================================

    let _map       = null;
    let _dataLayer = null;
    let _options   = {};

    // layer → feature lookup, rebuilt on each attach
    let _layerFeatureMap = new Map();

    // Groups: Array of { latlng, layers[] }
    // Each layer also gets layer._spiderGroup = group reference
    let _groups = [];

    // Active spiders: Map from group → SpiderState
    // SpiderState = { spokesLayerGroup, summaryPopup, locked, dismissTimer }
    let _spiders = new Map();

    // Bound map-level handlers
    let _onZoomEnd = null;

    // =========================================================================
    // Default Options
    // =========================================================================

    const DEFAULTS = {
        pixelRadius      : 8,
        clusterThreshold : 12,
        spokeLength      : { min: 44, max: 72 },
        spokeLine        : {
            color     : '#888888',
            weight    : 1.2,
            opacity   : 0.7,
            dashArray : '3,3'
        },
        dismissDelay : 150,
        markerRadius : 5
    };

    // =========================================================================
    // Public API
    // =========================================================================

    function attach(map, dataLayer, options) {
        detach();

        _map       = map;
        _dataLayer = dataLayer;
        _options   = Object.assign({}, DEFAULTS, options, {
            spokeLength: Object.assign({}, DEFAULTS.spokeLength,
                options && options.spokeLength)
        });

        _buildLayerFeatureMap();
        _rebuildGroups();
        _bindSoloPopups();

        _dataLayer.eachLayer(function (layer) {
            layer.on('mouseover', _onMarkerMouseover);
            layer.on('mouseout',  _onMarkerMouseout);
            layer.on('click',     _onMarkerClick);
        });

        _onZoomEnd = function () {
            // Dismiss all unlocked spiders; keep locked ones in place
            _spiders.forEach(function (state, group) {
                if (!state.locked) _dismissGroup(group);
            });
            _rebuildGroups();
            _bindSoloPopups();  // re-evaluate which markers are solo at new zoom
        };
        _map.on('zoomend', _onZoomEnd);
    }

    function detach() {
        _spiders.forEach(function (state, group) {
            _dismissGroup(group);
        });
        _spiders.clear();

        if (_dataLayer) {
            _dataLayer.eachLayer(function (layer) {
                layer.off('mouseover', _onMarkerMouseover);
                layer.off('mouseout',  _onMarkerMouseout);
                layer.off('click',     _onMarkerClick);
            });
        }

        if (_map && _onZoomEnd) {
            _map.off('zoomend', _onZoomEnd);
        }

        _map             = null;
        _dataLayer       = null;
        _layerFeatureMap = new Map();
        _groups          = [];
        _onZoomEnd       = null;
    }

    // =========================================================================
    // Group Detection
    // =========================================================================

    function _buildLayerFeatureMap() {
        _layerFeatureMap = new Map();
        _dataLayer.eachLayer(function (layer) {
            if (layer.feature) _layerFeatureMap.set(layer, layer.feature);
        });
    }

    /**
     * Bind popups to solo markers (not part of any cluster).
     * Cluster origin markers intentionally get no popup — click only locks spokes.
     * Called after _rebuildGroups so _spiderGroup is set on every layer.
     */
    function _bindSoloPopups() {
        _dataLayer.eachLayer(function (layer) {
            // Remove any previously bound popup first (handles zoom-triggered rebind)
            layer.unbindPopup();

            if (!layer._spiderGroup) {
                // Solo marker — bind normal popup
                const feature = _layerFeatureMap.get(layer);
                if (feature) {
                    layer.bindPopup(PopupBuilder.build(feature.properties));
                }
            }
            // Cluster origins: no popup bound — click is handled by _onMarkerClick
        });
    }

    function _rebuildGroups() {
        const allLayers = [];
        _dataLayer.eachLayer(function (l) { allLayers.push(l); });

        // Union-Find
        const parent = allLayers.map((_, i) => i);
        function find(i) {
            while (parent[i] !== i) { parent[i] = parent[parent[i]]; i = parent[i]; }
            return i;
        }
        function union(i, j) { parent[find(i)] = find(j); }

        const pts = allLayers.map(l => _map.latLngToLayerPoint(l.getLatLng()));
        const r   = _options.pixelRadius;

        for (let i = 0; i < allLayers.length; i++) {
            for (let j = i + 1; j < allLayers.length; j++) {
                const dx = pts[i].x - pts[j].x;
                const dy = pts[i].y - pts[j].y;
                if (dx * dx + dy * dy <= r * r) union(i, j);
            }
        }

        const groupMap = new Map();
        allLayers.forEach(function (layer, i) {
            const root = find(i);
            if (!groupMap.has(root)) groupMap.set(root, []);
            groupMap.get(root).push(layer);
        });

        _groups = [];
        groupMap.forEach(function (layers) {
            if (layers.length >= 2) {
                const group = { latlng: layers[0].getLatLng(), layers };
                _groups.push(group);
                layers.forEach(l => { l._spiderGroup = group; });
            } else {
                layers[0]._spiderGroup = null;
            }
        });
    }

    // =========================================================================
    // Marker Event Handlers
    // =========================================================================

    function _onMarkerMouseover(e) {
        const group = e.target._spiderGroup;
        if (!group) return;

        const state = _spiders.get(group);
        if (state) {
            // Already showing — cancel any pending dismiss
            if (state.dismissTimer) {
                clearTimeout(state.dismissTimer);
                state.dismissTimer = null;
            }
            return;
        }

        // Show in unlocked (hover) mode
        _showGroup(group, false);
    }

    function _onMarkerMouseout(e) {
        const group = e.target._spiderGroup;
        if (!group) return;

        const state = _spiders.get(group);
        if (!state || state.locked) return;  // locked → mouseout does nothing

        state.dismissTimer = setTimeout(function () {
            const s = _spiders.get(group);
            if (s && !s.locked) _dismissGroup(group);
        }, _options.dismissDelay);
    }

    function _onMarkerClick(e) {
        L.DomEvent.stopPropagation(e);

        const group = e.target._spiderGroup;
        if (!group) return;

        const state = _spiders.get(group);

        if (state && state.locked) {
            // Already locked → toggle off (dismiss)
            _dismissGroup(group);
            return;
        }

        if (state) {
            // Showing but unlocked → lock it in place
            if (state.dismissTimer) {
                clearTimeout(state.dismissTimer);
                state.dismissTimer = null;
            }
            state.locked = true;
        } else {
            // Not visible yet → show and immediately lock
            _showGroup(group, true);
        }
    }

    // =========================================================================
    // Show / Dismiss
    // =========================================================================

    function _showGroup(group, locked) {
        const count = group.layers.length;
        if (count >= _options.clusterThreshold) {
            _showSummaryPopup(group, locked);
        } else {
            _showSpokes(group, locked);
        }
    }

    function _dismissGroup(group) {
        const state = _spiders.get(group);
        if (!state) return;

        if (state.dismissTimer) clearTimeout(state.dismissTimer);

        if (state.spokesLayerGroup) {
            _map.removeLayer(state.spokesLayerGroup);
        }
        if (state.summaryPopup) {
            _map.closePopup(state.summaryPopup);
        }

        _spiders.delete(group);
    }

    // =========================================================================
    // Spoke Rendering
    // =========================================================================

    function _showSpokes(group, locked) {
        const layers   = group.layers;
        const n        = layers.length;
        const originLL = group.latlng;
        const originPx = _map.latLngToLayerPoint(originLL);

        const t        = Math.min(1, (n - 2) / (_options.clusterThreshold - 2));
        const spokeLen = _options.spokeLength.min
                       + t * (_options.spokeLength.max - _options.spokeLength.min);

        const angleStep   = (2 * Math.PI) / n;
        const spokeLayers = [];

        layers.forEach(function (markerLayer, i) {
            const angle = i * angleStep - Math.PI / 2;
            const tipPx = L.point(
                originPx.x + spokeLen * Math.cos(angle),
                originPx.y + spokeLen * Math.sin(angle)
            );
            const tipLL = _map.layerPointToLatLng(tipPx);

            // Spoke line
            const line = L.polyline([originLL, tipLL], _options.spokeLine);

            // Tip marker — keeps original server-assigned color
            const feature = _layerFeatureMap.get(markerLayer);
            const color   = (feature && feature.properties && feature.properties._color)
                           || '#e41a1c';

            const tip = L.circleMarker(tipLL, {
                radius      : _options.markerRadius,
                fillColor   : color,
                color       : color,
                weight      : 1,
                opacity     : 1,
                fillOpacity : 0.7,
                zIndexOffset: 1000
            });

            if (feature) {
                tip.bindPopup(PopupBuilder.build(feature.properties));
            }

            // Hover over spokes/tips keeps the spider alive (when unlocked)
            line.on('mouseover', function () { _onSpokeMouseover(group); });
            line.on('mouseout',  function () { _onSpokeMouseout(group); });
            tip.on('mouseover',  function () { _onSpokeMouseover(group); });
            tip.on('mouseout',   function () { _onSpokeMouseout(group); });

            // Clicking a tip opens its popup without dismissing the spider
            tip.on('click', function (e) {
                L.DomEvent.stopPropagation(e);
                tip.openPopup();
            });

            spokeLayers.push(line, tip);
        });

        const spokesLayerGroup = L.layerGroup(spokeLayers).addTo(_map);

        _spiders.set(group, {
            spokesLayerGroup,
            summaryPopup : null,
            locked,
            dismissTimer : null
        });
    }

    function _onSpokeMouseover(group) {
        const state = _spiders.get(group);
        if (!state || state.locked) return;
        if (state.dismissTimer) {
            clearTimeout(state.dismissTimer);
            state.dismissTimer = null;
        }
    }

    function _onSpokeMouseout(group) {
        const state = _spiders.get(group);
        if (!state || state.locked) return;
        state.dismissTimer = setTimeout(function () {
            const s = _spiders.get(group);
            if (s && !s.locked) _dismissGroup(group);
        }, _options.dismissDelay);
    }

    // =========================================================================
    // Summary Popup (large clusters >= clusterThreshold)
    // =========================================================================

    function _showSummaryPopup(group, locked) {
        const layers = group.layers;
        const n      = layers.length;

        let rows = '';
        layers.forEach(function (markerLayer, i) {
            const feature  = _layerFeatureMap.get(markerLayer);
            const props    = (feature && feature.properties) || {};
            const sampleId = props.sample_id
                           || props['Object-ID']
                           || ('Sample ' + (i + 1));
            const color    = props._color || '#e41a1c';
            const dot      = '<span class="spider-popup-dot" '
                           + 'style="background:' + _escapeHtml(color) + '"></span>';
            rows += '<tr class="spider-popup-row" data-idx="' + i + '">'
                  + '<td class="spider-popup-dot-cell">' + dot + '</td>'
                  + '<td><a href="#" class="spider-popup-link">'
                  + _escapeHtml(String(sampleId))
                  + '</a></td>'
                  + '</tr>';
        });

        const html = '<div class="spider-popup">'
                   + '<div class="spider-popup-header">' + n + ' samples at this location</div>'
                   + '<div class="spider-popup-scroll">'
                   + '<table class="spider-popup-table"><tbody>' + rows + '</tbody></table>'
                   + '</div></div>';

        const popup = L.popup({
            maxWidth    : 260,
            className   : 'spider-summary-popup',
            autoClose   : false,    // don't close when another popup opens
            closeOnClick: false     // don't close on map background click
        })
            .setLatLng(group.latlng)
            .setContent(html)
            .openOn(_map);

        // Hover over the popup keeps it alive when unlocked
        popup.on('mouseover', function () { _onSpokeMouseover(group); });
        popup.on('mouseout',  function () { _onSpokeMouseout(group); });

        _spiders.set(group, {
            spokesLayerGroup : null,
            summaryPopup     : popup,
            locked,
            dismissTimer     : null
        });

        // Wire up row click handlers once the popup DOM is ready
        setTimeout(function () {
            // Query within the specific popup element
            const contentEl = popup.getElement
                ? popup.getElement()
                : document.querySelector('.spider-summary-popup');
            if (!contentEl) return;

            contentEl.querySelectorAll('.spider-popup-row').forEach(function (row) {
                row.addEventListener('click', function (e) {
                    e.preventDefault();
                    e.stopPropagation();

                    const idx         = parseInt(row.getAttribute('data-idx'), 10);
                    const targetLayer = layers[idx];
                    if (!targetLayer) return;

                    const feature = _layerFeatureMap.get(targetLayer);
                    if (feature) {
                        // Open individual popup at that sample's location
                        // Summary popup stays open (autoClose: false)
                        L.popup()
                            .setLatLng(targetLayer.getLatLng())
                            .setContent(PopupBuilder.build(feature.properties))
                            .openOn(_map);
                    }
                });
            });
        }, 50);
    }

    // =========================================================================
    // Utilities
    // =========================================================================

    function _escapeHtml(text) {
        return text
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');
    }

    // =========================================================================
    // Export
    // =========================================================================

    return { attach, detach };

})();
