import CoreGraphics
import Foundation
import Testing
@testable import Kaset

// MARK: - RomanizerUTF16OffsetTests

/// Regression tests for the Chinese/Bengali/Hindi romanizers, which previously
/// indexed a Swift `String` with `CFStringTokenizer` UTF-16 offsets via
/// `index(_:offsetBy:)` (grapheme-based). When the preceding text contained
/// graphemes wider than one UTF-16 unit (Devanagari/Bengali conjuncts, CJK
/// supplementary-plane ideographs, emoji), the computed index walked past
/// `endIndex` and trapped with "String index is out of bounds", or silently
/// extracted the wrong substring. Each test below exercises the tokenizer
/// else-branch (embedded Latin / digits / punctuation / emoji) so a regression
/// would crash the test run rather than fail an assertion.
struct RomanizerUTF16OffsetTests {
    // MARK: Chinese

    @Test("Chinese romanizer produces pinyin for pure Han text")
    func chinesePureText() throws {
        let result = try #require(ChineseRomanizer.romanize("你好世界"))
        #expect(!result.isEmpty)
        // Pinyin is Latin-only output.
        #expect(ScriptDetector.isLatinOnly(result) == true)
    }

    @Test("Chinese romanizer does not crash on Han + Latin + digits + emoji")
    func chineseMixedNoCrash() throws {
        // Emoji (U+1F3B5, 2 UTF-16 units) and Latin/digit tokens drive the
        // else-branch at high UTF-16 offsets — the previous crash repro.
        let result = try #require(ChineseRomanizer.romanize("你好 abc 123 🎵 world"))
        #expect(result.contains("abc"))
        #expect(result.contains("123"))
        #expect(result.contains("world"))
    }

    @Test("Chinese romanizer does not crash on supplementary-plane ideograph")
    func chineseAstralNoCrash() {
        // U+20000 (𠀀) is a single grapheme of 2 UTF-16 units.
        let result = ChineseRomanizer.romanize("你好𠀀🎶 end")
        #expect(result?.contains("end") == true)
    }

    // MARK: Bengali

    @Test("Bengali romanizer produces non-empty output for pure Bengali text")
    func bengaliPureText() throws {
        let result = try #require(BengaliRomanizer.romanize("নমস্কার"))
        #expect(!result.isEmpty)
    }

    @Test("Bengali romanizer does not crash on conjuncts + Latin + emoji")
    func bengaliMixedNoCrash() throws {
        // Bengali conjuncts (স্ক) are multi-UTF-16 single graphemes; followed by
        // an emoji and Latin/digit else-branch tokens.
        let result = try #require(BengaliRomanizer.romanize("নমস্কার hello 🎶 99"))
        #expect(result.contains("hello"))
        #expect(result.contains("99"))
    }

    // MARK: Hindi

    @Test("Hindi romanizer produces non-empty output for pure Devanagari text")
    func hindiPureText() throws {
        let result = try #require(HindiRomanizer.romanize("नमस्ते"))
        #expect(!result.isEmpty)
    }

    @Test("Hindi romanizer does not crash on conjuncts + Latin + digits + emoji")
    func hindiMixedNoCrash() throws {
        // Devanagari conjunct (स्त) + emoji + Latin/digit else-branch tokens at
        // UTF-16 offsets beyond the grapheme count.
        let result = try #require(HindiRomanizer.romanize("नमस्ते world 🎵 12"))
        #expect(result.contains("world"))
        #expect(result.contains("12"))
    }

    @Test("Romanizers return nil for empty input")
    func emptyInput() {
        #expect(ChineseRomanizer.romanize("") == nil)
        #expect(BengaliRomanizer.romanize("") == nil)
        #expect(HindiRomanizer.romanize("") == nil)
    }
}

// MARK: - ImageCacheKeyTests

/// The memory cache stores images downsampled to a per-request `targetSize`, so
/// the cache key must include the size — otherwise a request at one size is
/// served an image rendered for a different size (e.g. a 160×160 thumbnail
/// upscaled to a 320×320 display, appearing blurry).
struct ImageCacheKeyTests {
    private let url = URL(string: "https://example.com/art.jpg")!
    private let other = URL(string: "https://example.com/other.jpg")!

    @Test("Different target sizes produce different keys for the same URL")
    func sizeAffectsKey() {
        let small = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 160, height: 160))
        let large = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 320, height: 320))
        #expect(small != large)
    }

    @Test("Same URL and size produce identical keys")
    func sameInputsSameKey() {
        let a = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 80, height: 80))
        let b = ImageCache.memoryCacheKey(for: self.url, targetSize: CGSize(width: 80, height: 80))
        #expect(a == b)
    }

    @Test("Nil target size keys by URL only")
    func nilSizeKeysByURL() {
        let key = ImageCache.memoryCacheKey(for: self.url, targetSize: nil)
        #expect(key == self.url.absoluteString as NSString)
    }

    @Test("Different URLs produce different keys at the same size")
    func urlAffectsKey() {
        let size = CGSize(width: 320, height: 320)
        #expect(ImageCache.memoryCacheKey(for: self.url, targetSize: size)
            != ImageCache.memoryCacheKey(for: self.other, targetSize: size))
    }
}
