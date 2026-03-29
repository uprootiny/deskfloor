import Foundation

/// Imports harvested prompts from the NLP engine harvest JSON into PromptStore format.
enum PromptImporter {
    struct HarvestedPrompt: Codable {
        let category: String
        let content: String
        let keywords: [String]
        let language: String?
        let length: Int?
        let source: String?
    }

    /// Import harvested prompts, skipping those too short or already present.
    static func importHarvested(from url: URL, into store: PromptStore, minLength: Int = 40) throws -> Int {
        let data = try Data(contentsOf: url)
        let harvested = try JSONDecoder().decode([HarvestedPrompt].self, from: data)

        let existingContents = Set(store.prompts.map { $0.content.prefix(80).lowercased() })
        var imported = 0

        for item in harvested {
            // Skip short/trivial prompts
            guard item.content.count >= minLength else { continue }

            // Skip duplicates
            let key = item.content.prefix(80).lowercased()
            guard !existingContents.contains(key) else { continue }

            // Generate a title from first line or keywords
            let title = Self.generateTitle(from: item)

            store.addPrompt(
                title: title,
                content: item.content,
                tags: item.keywords.prefix(5).map(String.init)
            )
            imported += 1
        }

        return imported
    }

    private static func generateTitle(from item: HarvestedPrompt) -> String {
        // Use first sentence, capped at 60 chars
        let firstLine = item.content.components(separatedBy: .newlines).first ?? item.content
        let firstSentence = firstLine.components(separatedBy: ". ").first ?? firstLine
        if firstSentence.count <= 60 {
            return String(firstSentence)
        }
        return String(firstSentence.prefix(57)) + "..."
    }
}
