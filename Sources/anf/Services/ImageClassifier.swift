import Foundation
import Vision

/// On-device image classification via the system Vision framework
/// (`VNClassifyImageRequest`) — ~1300 categories (dog, food, beach, document…),
/// no model bundled, no network. This is what lets ⌘K find "강아지 사진" even
/// when the image has no text and no tag. Far cheaper than OCR (one CNN pass,
/// tens of ms), so it runs on every image in the search walk.
enum ImageClassifier {

    /// Confident category labels for an image (underscores normalized to spaces),
    /// or [] when nothing is confident. Uses Vision's precision-calibrated filter
    /// (raw confidence isn't comparable across categories), with a confidence
    /// fallback so we don't return empty on borderline images.
    nonisolated static func labels(for url: URL) -> [String] {
        // Classification needs no resolution; small input keeps it fast.
        guard let cg = OCRService.loadCGImage(url, maxPixel: 1024) else { return [] }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        do { try handler.perform([request]) } catch { return [] }
        let obs = request.results ?? []

        var picked = obs.filter { $0.hasMinimumRecall(0.05, forPrecision: 0.7) }
        if picked.isEmpty { picked = obs.filter { $0.confidence > 0.2 } }
        return picked
            .sorted { $0.confidence > $1.confidence }
            .prefix(20)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ").lowercased() }
    }

    /// Does `query` describe any of these classification labels? English queries
    /// match label substrings directly; common Korean terms map to the English
    /// Vision taxonomy (개→dog 등). Substring match so "dog" hits
    /// "labrador retriever"/"domestic dog" too.
    nonisolated static func matches(query: String, labels: [String]) -> Bool {
        guard !labels.isEmpty else { return false }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return false }
        var needles = [q]
        if let mapped = koreanAliases[q] { needles += mapped }
        return labels.contains { label in needles.contains { label.contains($0) } }
    }

    /// Korean search term → English Vision category substrings. Curated for the
    /// common cases; extend freely. (English queries don't need this — they hit
    /// the labels directly.)
    nonisolated static let koreanAliases: [String: [String]] = [
        "강아지": ["dog", "puppy", "canine"], "개": ["dog", "canine"], "멍멍이": ["dog"],
        "고양이": ["cat", "kitten", "feline"], "냥이": ["cat"],
        "동물": ["animal", "dog", "cat", "bird", "wildlife"],
        "새": ["bird"], "물고기": ["fish"], "꽃": ["flower", "blossom"],
        "나무": ["tree"], "식물": ["plant", "tree", "flower"],
        "음식": ["food", "meal", "dish", "cuisine"], "먹을것": ["food"],
        "음료": ["beverage", "drink", "coffee"], "커피": ["coffee", "beverage"],
        "케이크": ["cake", "dessert"], "디저트": ["dessert"],
        "사람": ["person", "people", "face"], "인물": ["person", "people", "portrait"],
        "아기": ["baby", "infant"], "얼굴": ["face"],
        "바다": ["beach", "ocean", "sea", "coast"], "해변": ["beach", "coast"],
        "산": ["mountain"], "하늘": ["sky", "cloud"], "구름": ["cloud"],
        "눈": ["snow"], "물": ["water"], "강": ["river"], "호수": ["lake"],
        "풍경": ["landscape", "scenery", "outdoor", "nature"],
        "자동차": ["car", "vehicle", "automobile"], "차": ["car", "vehicle"],
        "비행기": ["airplane", "aircraft"], "배": ["boat", "ship"],
        "건물": ["building", "architecture"], "집": ["house", "home", "building"],
        "도시": ["city", "urban", "cityscape"],
        "문서": ["document", "text", "paper", "menu"], "글자": ["text", "document"],
        "스크린샷": ["screenshot", "screen", "interface"],
        "차트": ["chart", "graph", "diagram", "plot"], "그래프": ["graph", "chart"],
        "지도": ["map"], "로고": ["logo"], "아이콘": ["icon"],
    ]
}
