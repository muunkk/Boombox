import JavaScriptCore
import Testing
@testable import Kaset

/// Tests for the WebView script that suppresses YouTube Music's Song/Video switcher.
@Suite(.serialized, .tags(.service))
@MainActor
struct AudioOnlyPlaybackScriptTests {
    @Test("Audio-only script hides video toggle and activates song")
    func audioOnlyScriptHidesVideoToggleAndActivatesSong() throws {
        let context = try #require(JSContext())
        self.evaluate(Self.domFixtureScript, in: context)
        self.evaluate(SingletonPlayerWebView.audioOnlyPlaybackScript, in: context)

        let result = context.evaluateScript("window.__boomboxApplyAudioOnlyPlayback();")?.toString()
        let songClicked = context.evaluateScript("songButton.clicked")?.toBool()
        let videoDisplay = context.evaluateScript("videoButton.style.display")?.toString()
        let popupDisplay = context.evaluateScript("popup.style.display")?.toString()
        let ariaHidden = context.evaluateScript("videoButton.attributes['aria-hidden']")?.toString()
        let installedStyle = context.evaluateScript("installedStyles[0].textContent")?.toString()

        #expect(result == "applied")
        #expect(songClicked == true)
        #expect(videoDisplay == "none")
        #expect(popupDisplay == "none")
        #expect(ariaHidden == "true")
        #expect(installedStyle?.contains("ytmusic-av-toggle") == true)
        #expect(installedStyle?.contains("[aria-label=\"Video\"]") == true)
    }

    @Test("Audio-only script does not hide the media element")
    func audioOnlyScriptDoesNotHideMediaElement() {
        let script = SingletonPlayerWebView.audioOnlyPlaybackScript

        #expect(!script.contains("video {"))
        #expect(!script.contains("querySelector('video')"))
        #expect(!script.contains("querySelectorAll('video')"))
    }

    private static let domFixtureScript = """
    var installedStyles = [];

    function Element(tagName, text, role) {
        this.tagName = tagName;
        this.textContent = text || '';
        this.innerText = text || '';
        this.parentElement = null;
        this.children = [];
        this.attributes = {};
        this.style = {};
        this.className = '';
        this.clicked = false;
        if (role) {
            this.attributes.role = role;
        }
    }

    Element.prototype.appendChild = function(child) {
        child.parentElement = this;
        this.children.push(child);
        if (child.tagName === 'style') {
            installedStyles.push(child);
        }
        return child;
    };

    Element.prototype.setAttribute = function(name, value) {
        this.attributes[name] = String(value);
    };

    Element.prototype.getAttribute = function(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name)
            ? this.attributes[name]
            : null;
    };

    Element.prototype.hasAttribute = function(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name);
    };

    Element.prototype.click = function() {
        this.clicked = true;
        this.attributes['aria-selected'] = 'true';
    };

    Element.prototype.querySelectorAll = function(selector) {
        var result = [];

        function visit(node) {
            node.children.forEach(function(child) {
                var tag = (child.tagName || '').toLowerCase();
                var role = child.attributes.role || '';

                if (
                    selector.indexOf(tag) !== -1 ||
                    selector.indexOf('[role="button"]') !== -1 && role === 'button' ||
                    selector.indexOf('[role="tab"]') !== -1 && role === 'tab'
                ) {
                    result.push(child);
                }

                visit(child);
            });
        }

        visit(this);
        return result;
    };

    var documentElement = new Element('html');
    var head = new Element('head');
    documentElement.appendChild(head);

    var popup = new Element('div', 'Song Video Close');
    var toggle = new Element('ytmusic-av-toggle', 'Song Video');
    var songButton = new Element('button', 'Song', 'button');
    var videoButton = new Element('button', 'Video', 'button');

    toggle.appendChild(songButton);
    toggle.appendChild(videoButton);
    popup.appendChild(toggle);
    documentElement.appendChild(popup);

    var document = {
        documentElement: documentElement,
        head: head,
        body: documentElement,
        getElementById: function() { return null; },
        createElement: function(tagName) { return new Element(tagName); },
        addEventListener: function() {},
        querySelectorAll: function(selector) {
            if (selector.indexOf('ytmusic-av-toggle') !== -1) {
                return [toggle];
            }

            if (selector.indexOf('button') !== -1 || selector.indexOf('[role=') !== -1) {
                return [songButton, videoButton];
            }

            return [];
        }
    };

    function MutationObserver(callback) {
        this.callback = callback;
    }
    MutationObserver.prototype.observe = function() {};

    function requestAnimationFrame(callback) {
        callback();
    }

    var window = {};
    var setTimeout = function(callback) {
        callback();
    };
    """

    private func evaluate(_ script: String, in context: JSContext) {
        context.exception = nil
        _ = context.evaluateScript(script)

        if let exception = context.exception?.toString() {
            Issue.record("JavaScript exception: \(exception)")
        }
    }
}
