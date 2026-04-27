import XCTest
import OpenLessCore
@testable import OpenLessPolish

final class DictionaryPromptTests: XCTestCase {
    func test_dictionaryPromptTellsModelNotToMechanicallyReplace() {
        let entry = DictionaryEntry(
            phrase: "Claude",
            category: .aiTool,
            notes: "AI 产品名"
        )

        let prompt = PolishPrompts.userPrompt(
            for: "请帮我优化一下 Cloud 的提示词",
            dictionaryEntries: [entry]
        )

        XCTAssertTrue(prompt.contains("用户词典"))
        XCTAssertTrue(prompt.contains("<user_dictionary_terms>"))
        XCTAssertTrue(prompt.contains("正确词：Claude"))
        XCTAssertFalse(prompt.contains("可能误识别为"))
        XCTAssertFalse(prompt.contains("适用上下文"))
        XCTAssertTrue(prompt.contains("不是机械替换表"))
        XCTAssertTrue(prompt.contains("请根据原始转写的整句语义上下文自动判断"))
        XCTAssertTrue(prompt.contains("如果语义不明确，保留原始转写里的词，不要猜"))
    }
}
