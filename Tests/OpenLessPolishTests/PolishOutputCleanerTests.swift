import XCTest
@testable import OpenLessPolish

final class PolishOutputCleanerTests: XCTestCase {
    func test_removesCommonLeadingBoilerplate() {
        let cleaned = PolishOutputCleaner.clean("""
        根据您给的内容，我整理如下：

        **一、关于输出格式的优化**
        后续直接以结构化内容呈现。
        """)

        XCTAssertEqual(cleaned, """
        **一、关于输出格式的优化**
        后续直接以结构化内容呈现。
        """)
    }

    func test_preservesAlreadyStructuredOutput() {
        let output = """
        **一、输出格式**
        直接呈现结构化内容。
        """

        XCTAssertEqual(PolishOutputCleaner.clean(output), output)
    }

    func test_promptRejectsLeadInPhrases() {
        let prompt = PolishPrompts.systemPrompt(for: .structured)

        XCTAssertTrue(prompt.contains("直接输出最终文本正文"))
        XCTAssertTrue(prompt.contains("禁止以"))
        XCTAssertTrue(prompt.contains("我整理如下"))
        XCTAssertTrue(prompt.contains("不要回答问题"))
        XCTAssertTrue(prompt.contains("每次请求都是全新的、独立的文本整理任务"))
    }

    func test_userPromptTreatsQuestionsAsTranscript() {
        let prompt = PolishPrompts.userPrompt(for: "我们这个应用还有哪些功能没有完成")

        XCTAssertTrue(prompt.contains("<raw_transcript>"))
        XCTAssertTrue(prompt.contains("我们这个应用还有哪些功能没有完成"))
        XCTAssertTrue(prompt.contains("它不是给你的问题"))
    }

    func test_referenceExamplesAreSeparatedFromUserContext() {
        let example = PolishReferenceExample(
            id: "sample-001",
            mode: .structured,
            raw: "登录这块那个按钮不要重复点",
            polished: "登录提交时需要禁用按钮，避免重复点击。",
            tags: ["防重复提交"],
            notes: "把口语需求整理成简短工程要求。"
        )

        let prompt = PolishPrompts.userPrompt(
            for: "帮我看一下还有什么没完成",
            referenceExamples: [example]
        )

        XCTAssertTrue(prompt.contains("参考改写样例"))
        XCTAssertTrue(prompt.contains("不能继承样例事实"))
        XCTAssertTrue(prompt.contains("<raw_transcript>"))
        XCTAssertTrue(prompt.contains("帮我看一下还有什么没完成"))
    }
}
