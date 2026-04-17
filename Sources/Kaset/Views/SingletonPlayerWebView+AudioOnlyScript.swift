// MARK: - SingletonPlayerWebView Audio-Only Script Extension

extension SingletonPlayerWebView {
    /// Script that keeps YouTube Music's in-page Song/Video switcher in audio mode.
    static var audioOnlyPlaybackScript: String {
        """
        (function() {
            'use strict';

            if (window.__ytmPrivateAudioOnlyInstalled) {
                return;
            }
            window.__ytmPrivateAudioOnlyInstalled = true;

            const STYLE_ID = 'ytm-private-audio-only-style';
            const CONTROL_SELECTOR = [
                'button',
                '[role="button"]',
                '[role="tab"]',
                'paper-tab',
                'tp-yt-paper-tab',
                'yt-button-renderer',
                'ytmusic-toggle-button-renderer'
            ].join(',');
            const CONTAINER_SELECTOR = [
                'ytmusic-av-toggle',
                'ytmusic-av-toggle-renderer',
                'ytmusic-player-page [role="tablist"]',
                'ytmusic-player-bar [role="tablist"]',
                'tp-yt-paper-dialog',
                'iron-dropdown',
                'ytmusic-popup-container'
            ].join(',');
            const ACTIONABLE_TAGS = {
                'button': true,
                'paper-tab': true,
                'tp-yt-paper-tab': true,
                'yt-button-renderer': true,
                'ytmusic-toggle-button-renderer': true
            };

            function installAudioOnlyStyle() {
                if (document.getElementById && document.getElementById(STYLE_ID)) {
                    return;
                }

                const style = document.createElement('style');
                style.id = STYLE_ID;
                style.textContent = `
                    ytmusic-av-toggle,
                    ytmusic-av-toggle-renderer,
                    ytmusic-player-page ytmusic-av-toggle,
                    ytmusic-player-page ytmusic-av-toggle-renderer {
                        display: none !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                    }

                    ytmusic-player-page [aria-label="Video"],
                    ytmusic-player-page [title="Video"],
                    ytmusic-player-bar [aria-label="Video"],
                    ytmusic-player-bar [title="Video"] {
                        display: none !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                    }

                    tp-yt-paper-dialog:has([aria-label="Song"]):has([aria-label="Video"]),
                    tp-yt-paper-dialog:has([title="Song"]):has([title="Video"]),
                    iron-dropdown:has([aria-label="Song"]):has([aria-label="Video"]),
                    iron-dropdown:has([title="Song"]):has([title="Video"]),
                    ytmusic-popup-container:has([aria-label="Song"]):has([aria-label="Video"]),
                    ytmusic-popup-container:has([title="Song"]):has([title="Video"]) {
                        display: none !important;
                        visibility: hidden !important;
                        pointer-events: none !important;
                    }
                `;

                const host = document.head || document.documentElement || document.body;
                if (host && host.appendChild) {
                    host.appendChild(style);
                } else {
                    setTimeout(installAudioOnlyStyle, 0);
                }
            }

            function attributeValue(element, name) {
                if (!element || typeof element.getAttribute !== 'function') {
                    return '';
                }
                return element.getAttribute(name) || '';
            }

            function normalizedLabel(element) {
                if (!element) {
                    return '';
                }

                const pieces = [
                    attributeValue(element, 'aria-label'),
                    attributeValue(element, 'title'),
                    typeof element.innerText === 'string' ? element.innerText : '',
                    typeof element.textContent === 'string' ? element.textContent : ''
                ];

                return pieces.join(' ')
                    .replace(/\\s+/g, ' ')
                    .trim()
                    .toLowerCase();
            }

            function hasWord(label, word) {
                return new RegExp('(^|[^a-z])' + word + '([^a-z]|$)').test(label);
            }

            function isSongControl(element) {
                const label = normalizedLabel(element);
                return label === 'song' || label === 'songs' || (label.length <= 30 && hasWord(label, 'song'));
            }

            function isVideoControl(element) {
                const label = normalizedLabel(element);
                return label === 'video' || label === 'videos' || (label.length <= 30 && hasWord(label, 'video'));
            }

            function uniqueElements(elements) {
                const seen = new Set();
                const result = [];

                elements.forEach((element) => {
                    if (!element || seen.has(element)) {
                        return;
                    }
                    seen.add(element);
                    result.push(element);
                });

                return result;
            }

            function actionableElement(element) {
                let current = element;

                for (let depth = 0; current && depth < 5; depth += 1) {
                    const tagName = (current.tagName || '').toLowerCase();
                    const role = attributeValue(current, 'role');

                    if (ACTIONABLE_TAGS[tagName] || role === 'button' || role === 'tab') {
                        return current;
                    }

                    current = current.parentElement;
                }

                return element;
            }

            function isSelected(element) {
                if (!element) {
                    return false;
                }

                const className = typeof element.className === 'string' ? element.className : '';
                const selectedAttribute = typeof element.getAttribute === 'function'
                    ? element.getAttribute('selected')
                    : null;
                const hasSelectedAttribute = typeof element.hasAttribute === 'function'
                    ? element.hasAttribute('selected')
                    : selectedAttribute !== null;

                return attributeValue(element, 'aria-selected') === 'true' ||
                    attributeValue(element, 'aria-pressed') === 'true' ||
                    (hasSelectedAttribute && (selectedAttribute === '' || selectedAttribute === 'true')) ||
                    /\\b(iron-selected|selected|active|style-default-active)\\b/.test(className);
            }

            function hideElement(element) {
                if (!element || element.__ytmPrivateAudioOnlyHidden) {
                    return;
                }

                element.__ytmPrivateAudioOnlyHidden = true;

                if (typeof element.setAttribute === 'function') {
                    element.setAttribute('aria-hidden', 'true');
                    element.setAttribute('tabindex', '-1');
                }

                if (element.style) {
                    element.style.display = 'none';
                    element.style.visibility = 'hidden';
                    element.style.pointerEvents = 'none';
                }
            }

            function controlsIn(container) {
                if (!container || typeof container.querySelectorAll !== 'function') {
                    return [];
                }

                const controls = Array.from(container.querySelectorAll(CONTROL_SELECTOR))
                    .map(actionableElement);

                const containerAsControl = actionableElement(container);
                if (isSongControl(containerAsControl) || isVideoControl(containerAsControl)) {
                    controls.push(containerAsControl);
                }

                return uniqueElements(controls);
            }

            function smallSongVideoContainerFor(control) {
                let current = control ? control.parentElement : null;
                let match = null;

                for (let depth = 0; current && depth < 5; depth += 1) {
                    const label = normalizedLabel(current).replace(/\\bclose\\b/g, '').trim();
                    if (label.length <= 120 && hasWord(label, 'song') && hasWord(label, 'video')) {
                        match = current;
                    }
                    current = current.parentElement;
                }

                return match;
            }

            function candidateContainers() {
                const containers = [];

                if (typeof document.querySelectorAll === 'function') {
                    containers.push(...Array.from(document.querySelectorAll(CONTAINER_SELECTOR)));

                    Array.from(document.querySelectorAll(CONTROL_SELECTOR))
                        .map(actionableElement)
                        .filter((control) => isSongControl(control) || isVideoControl(control))
                        .forEach((control) => {
                            const container = smallSongVideoContainerFor(control);
                            if (container) {
                                containers.push(container);
                            }
                        });
                }

                return uniqueElements(containers);
            }

            function forceAudioOnlyIn(container) {
                const controls = controlsIn(container);
                const songControl = controls.find(isSongControl);
                const videoControls = controls.filter(isVideoControl);

                if (!songControl || videoControls.length === 0) {
                    return false;
                }

                if (!isSelected(songControl) && typeof songControl.click === 'function') {
                    songControl.click();
                }

                videoControls.forEach(hideElement);

                const tagName = (container.tagName || '').toLowerCase();
                if (tagName === 'ytmusic-av-toggle' || tagName === 'ytmusic-av-toggle-renderer') {
                    hideElement(container);
                }

                const popup = smallSongVideoContainerFor(videoControls[0]) || smallSongVideoContainerFor(container);
                if (popup) {
                    hideElement(popup);
                }

                return true;
            }

            function applyAudioOnlyPlayback() {
                installAudioOnlyStyle();

                const didApply = candidateContainers()
                    .map(forceAudioOnlyIn)
                    .some((result) => result);

                return didApply ? 'applied' : 'no-toggle';
            }

            let scheduled = false;
            function scheduleApply() {
                applyAudioOnlyPlayback();

                if (scheduled) {
                    return;
                }

                scheduled = true;
                setTimeout(function() {
                    scheduled = false;
                    applyAudioOnlyPlayback();
                }, 50);
            }

            window.__ytmPrivateApplyAudioOnlyPlayback = applyAudioOnlyPlayback;
            applyAudioOnlyPlayback();

            if (document.addEventListener) {
                document.addEventListener('DOMContentLoaded', scheduleApply, true);
                document.addEventListener('yt-navigate-finish', scheduleApply, true);
                document.addEventListener('yt-page-data-updated', scheduleApply, true);
            }

            if (typeof MutationObserver === 'function') {
                const target = document.documentElement || document.body;
                if (target) {
                    new MutationObserver(scheduleApply).observe(target, {
                        childList: true,
                        subtree: true
                    });
                }
            }
        })();
        """
    }
}
