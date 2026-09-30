import XCTest
import AppKit
import SwiftUI
@testable import MacMarkDownKit

/// Guards the preview renderer against putting SwiftUI `Color` values into
/// `NSAttributedString` attributes: TextKit calls `-[NSColor set]` while
/// drawing, and a SwiftUI `Color` (bridged as `__SwiftValue`) throws
/// "unrecognized selector sent to instance" at that point.
final class AttributedRendererTests: XCTestCase {

    @MainActor
    private func sampleElements() -> [MarkdownElement] {
        [
            .heading(level: 1, text: "Title"),
            .paragraph([
                .text("Hello "),
                .emphasis([.text("em")]),
                .strong([.text("bold")]),
                .code("x"),
                .link(url: "https://example.com", children: [.text("link")])
            ]),
            .blockQuote([.paragraph([.text("quoted")])]),
            .unorderedList([ListItem(children: [.paragraph([.text("item")])])]),
            .codeBlock(language: "swift", code: "let x = 1"),
            .thematicBreak
        ]
    }

    @MainActor
    func testColorAttributesAreAppKitColors() throws {
        let renderer = AttributedRenderer(theme: .clearness)
        let attributed = renderer.render(sampleElements()).attributed
        XCTAssertGreaterThan(attributed.length, 0)

        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, _, _ in
            if let foreground = attributes[.foregroundColor] {
                XCTAssertTrue(
                    foreground is NSColor,
                    "foregroundColor must be NSColor, got \(type(of: foreground))"
                )
            }
            if let background = attributes[.backgroundColor] {
                XCTAssertTrue(
                    background is NSColor,
                    "backgroundColor must be NSColor, got \(type(of: background))"
                )
            }
        }
    }

    @MainActor
    func testRenderReturnsRangePerTopLevelElement() {
        let elements = sampleElements()
        let result = AttributedRenderer(theme: .clearness).render(elements)
        XCTAssertEqual(result.ranges.count, elements.count)
        XCTAssertTrue(result.ranges.allSatisfy { $0 != nil })
    }

    /// Every anchor path (including nested list items and quote children) gets
    /// its own range, so the preview no longer collapses them onto the parent
    /// block's top.
    @MainActor
    func testRenderReturnsRangePerNestedAnchorPath() {
        let elements: [MarkdownElement] = [
            .heading(level: 1, text: "Title"),
            .unorderedList([
                ListItem(children: [.paragraph([.text("one")])]),
                ListItem(children: [.paragraph([.text("two")])]),
                ListItem(children: [.paragraph([.text("three")])])
            ]),
            .blockQuote([.paragraph([.text("quote one")]), .paragraph([.text("quote two")])])
        ]
        let result = AttributedRenderer(theme: .clearness).render(elements)

        let paths: [AnchorPath] = [
            [0], [1], [1, 0], [1, 0, 0], [1, 1], [1, 1, 0], [1, 2], [1, 2, 0],
            [2], [2, 0], [2, 1]
        ]
        let ranges = result.anchorRanges(for: paths)
        XCTAssertTrue(ranges.allSatisfy { $0 != nil }, "every anchor path must have a range")

        // List items must not all share the parent list's range.
        let itemStarts = [[1, 0], [1, 1], [1, 2]].compactMap { path -> Int? in
            result.pathRanges[path]?.location
        }
        XCTAssertEqual(itemStarts.count, 3)
        XCTAssertEqual(Set(itemStarts).count, 3, "each list item needs a distinct range")
        XCTAssertEqual(itemStarts, itemStarts.sorted(), "list item ranges must be ordered")

        // Quote children likewise.
        let quoteStarts = [[2, 0], [2, 1]].compactMap { result.pathRanges[$0]?.location }
        XCTAssertEqual(Set(quoteStarts).count, 2)
    }

    /// The Underline command wraps the raw selection, so a two-line selection
    /// becomes `_line1\nline2_`. Every character of the run, soft break
    /// included, must carry the underline attribute on the TextKit preview
    /// surface instead of falling back to `_…_` emphasis.
    @MainActor
    func testUnderlineSpansLineBreakOnTextSurface() {
        let markdown = "_深度研究一下这个问题：\n大腿为什么肌肉紧张？_"
        let elements = MarkdownParser().parse(
            markdown,
            options: MarkdownParseOptions(enableUnderline: true)
        )
        let attributed = AttributedRenderer(theme: .clearness).render(elements).attributed
        let range = (attributed.string as NSString)
            .range(of: "深度研究一下这个问题： 大腿为什么肌肉紧张？")
        XCTAssertNotEqual(range.location, NSNotFound)

        attributed.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
            XCTAssertNotNil(value, "the whole two-line run must be underlined")
        }
    }

    /// Measures the preview anchors exactly like `MarkdownPreviewSurface` does
    /// and checks they never move backwards: nested anchors must resolve to
    /// their own position in the *final* document, not to an inner string's
    /// coordinate space.
    @MainActor
    func testPreviewAnchorsAreMonotonicForNestedContent() {
        let markdown = """
        # Heading

        - alpha
        - beta
        - gamma

        > quote one
        > quote two

        ## Second

        Closing paragraph.
        """
        let parsed = MarkdownParser().parseDocument(markdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness).render(parsed.elements)
        let ranges = rendered.anchorRanges(for: parsed.anchors.map(\.path))

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        textView.setAttributedContent(rendered.attributed)
        textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

        var ys: [CGFloat] = []
        var last: CGFloat = 0
        for range in ranges {
            guard let range,
                  let textRange = textView.textContentStorage.textRange(from: range),
                  let frame = textView.textLayoutManager.typographicBounds(in: textRange)
            else { ys.append(last); continue }
            last = frame.minY + textView.textContainerOrigin.y
            ys.append(last)
        }

        XCTAssertFalse(ys.isEmpty)
        XCTAssertEqual(ys, ys.sorted(), "preview anchors must be monotonically non-decreasing")
        XCTAssertGreaterThan(ys.last ?? 0, 0)

        // The three list items must not all collapse onto the list's top.
        let itemStarts = [[1, 0], [1, 1], [1, 2]].compactMap { rendered.pathRanges[$0]?.location }
        XCTAssertEqual(itemStarts.count, 3)
        XCTAssertEqual(Set(itemStarts).count, 3)
    }

    @MainActor
    func testSettingAttributedContentLaysOut() {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let attributed = AttributedRenderer(theme: .clearness).render(sampleElements()).attributed
        textView.setAttributedContent(attributed)
        textView.performFullLayoutForTesting()
        XCTAssertEqual(textView.string, attributed.string)
    }

    /// The user-reported repro document: opening it in the editor and scrolling
    /// to the bottom left a large blank area under the preview. It is dense
    /// CJK-heavy markdown (tables, nested lists, blockquotes), so its laid-out
    /// height at a narrow wrap width is enormous — exactly the state that used
    /// to leak into the scroll sync.
    private static let reportedMarkdown = """
    # New Chat

    > Exported from Example · 2026-09-14T07:41:54Z · Model: unknown

    ## User

    深度研究一下这个问题：
    大腿为什么肌肉紧张？

    ## Assistant

    # 大腿肌肉紧张的原因：一份分层研究报告

    ## 一、核心结论（先看这里）

    大腿肌肉紧张不是一种疾病，而是**一个症状**，其背后可能同时存在多种原因。现有科普资料将其归纳为四大类可疑疾病（肌肉劳损、腰椎病变、血管疾病、神经系统问题）[1]，以及更宽的原因谱：运动过度、久坐久站、肌肉拉伤、神经压迫、代谢异常、心理压力或慢性疾病[3]。多数情况属于**功能性紧张**（运动、姿势、压力所致），可通过拉伸、热敷、调整习惯改善[6]；但若伴随麻木、放射痛、单侧肿胀或夜间痛醒，则需排查器质性疾病[1][3][6]。

    从解剖看，大腿位于髋关节与膝关节之间，又称"股"，是躯干与下肢的连接部位，主要功能是支撑身体[2]。这一"承上启下+承重"的位置，决定了它极易因姿势、代偿和负荷问题而长期处于高张力状态。

    ---

    ## 二、原因全景：八类诱因与对应机制

    | 类别 | 具体诱因 | 主要机制 | 典型线索 |
    |---|---|---|---|
    | **运动相关** | 跑步、跳跃、深蹲过量；发力不均衡（如深蹲膝盖内扣）；热身不足；运动后不拉伸 | 乳酸堆积或肌纤维微损伤；肌肉持续处于收缩状态 | 运动后酸痛、僵硬、活动受限[1][3] |
    | **生活习惯** | 久坐、久站；侧卧蜷缩或仰卧腿部受压 | 久坐使髂腰肌、股四头肌缩短紧绷；久站致下肢循环不畅；夜间持续收缩致晨起僵硬 | 久坐后加重、晨起明显[3][6] |
    | **体态代偿** | 骨盆倾斜、脊柱侧弯、核心肌群薄弱 | 大腿肌肉被迫过度发力以维持平衡，形成慢性劳损 | 慢性、反复、与运动量不成比例[6] |
    | **神经源性** | 腰椎间盘突出、椎管狭窄、梨状肌综合征、坐骨神经痛 | 神经根受压，引发大腿后侧/外侧放射性疼痛、麻木与肌肉痉挛 | 久站久坐加重，可伴腰痛、臀痛，严重时下肢无力[1][3] |
    | **血管源性** | 深静脉血栓（DVT）、动脉硬化闭塞症 | 缺血或淤血导致肌肉紧张疼痛 | 单侧肿胀、皮肤红热（DVT）；行走后酸痛、休息缓解、皮温降低（动脉病变）[1] |
    | **代谢/电解质** | 低钙、低钾、脱水；糖尿病 | 电解质失衡影响神经肌肉信号传导；糖尿病可致下肢循环障碍 | 抽筋、僵硬[3] |
    | **心理因素** | 焦虑、紧张、长期压力、睡眠不足 | 交感神经兴奋，全身肌肉（含大腿）无意识收缩，处于"备战"状态 | 可伴夜间磨牙、握拳；难以自主放松[3][6] |
    | **其他慢性疾病** | 纤维肌痛综合征、多发性硬化、周围神经炎 | 中枢脱髓鞘或周围神经损伤 | 多发性硬化可伴视力模糊、平衡障碍；神经炎可表现为刺痛、烧灼感[1][3] |

    此外，急性肌肉拉伤或慢性劳损（如股四头肌肌腱炎）会直接造成局部肿胀与紧张，可能伴随刺痛或灼热感[3]；腰椎问题严重时可出现单侧大腿麻木、脚趾活动障碍甚至大小便异常，提示马尾综合征[1]。

    ---

    ## 三、机制层面：肌肉"为什么会紧"

    把上表拆开看，紧张的产生大致通过五条通路：

    1. **微损伤与炎症**：运动导致的肌纤维轻微撕裂与修复不及时，表现为酸痛、僵硬、活动受限[1][3][6]。
    2. **代谢产物堆积与循环障碍**：乳酸堆积、下肢血液循环不畅，使肌肉难以"代谢掉"紧张状态[3][6]。
    3. **姿势性短缩**：长时间同一姿势使股四头肌、腘绳肌或髂腰肌持续缩短，形成慢性紧张[3][6]。
    4. **神经驱动异常**：神经根受压后异常放电，引起放射性疼痛与肌肉痉挛[1][3]。
    5. **电解质与神经肌肉信号传导失衡**：低钙、低钾或脱水直接影响肌肉收缩功能[3]；焦虑状态下交感兴奋则造成无意识收缩[3][6]。

    ---

    ## 四、鉴别诊断：什么时候是"普通紧张"，什么时候要就医

    ### 4.1 需要警惕的红旗信号

    | 红旗信号 | 可能指向 |
    |---|---|
    | 紧张持续超过2周且无缓解 | 需系统排查[1] |
    | 单侧大腿肿胀、皮肤发红发热、小腿压痛 | 深静脉血栓，血栓脱落可致肺栓塞，需紧急就医[1] |
    | 麻木或放射性疼痛 | 腰椎间盘突出压迫神经（如坐骨神经痛）[3][6] |
    | 剧烈疼痛或肿胀 | 肌肉拉伤、韧带撕裂[6] |
    | 皮肤温度升高或发红 | 感染或血栓风险[6] |
    | 夜间疼痛加重或影响睡眠 | 需排查器质性疾病[1][3] |
    | 脚趾活动障碍、大小便异常 | 马尾综合征，需紧急处理[1] |
    | 伴随发热、皮肤变色、不明原因体重下降 | 需就医[1] |
    | 行走后大腿酸痛、休息后缓解、下肢皮温降低 | 动脉硬化闭塞症（间歇性跛行）[1] |

    ### 4.2 常见检查路径

    若症状反复或加重，建议**优先排查腰椎和血管问题**，通过超声、肌电图明确病因[1]；长期紧张不缓解者可进行肌电图或MRI检查[3]；腰椎问题需完善腰椎MRI[1]。若自行调整后仍无缓解，建议咨询康复科或骨科医生[6]。

    ---

    ## 五、处理路径：分阶段应对

    ### 5.1 急性期（24–48小时内）

    - 冰敷，每次10–15分钟[3][6]；抬高患肢，避免剧烈活动[3]。
    - 必要时使用弹性绷带固定[1]。
    - 48小时后转为热敷，促进血液循环[1]。

    ### 5.2 恢复与放松期

    - **热敷**：约40℃、15分钟，配合轻柔按摩效果更佳[1][3][6]。
    - **针对性静态拉伸**：
      - 股四头肌：站立扶墙，手抓同侧脚踝向臀部轻拉，保持30秒，重复2–3次[6]；
      - 腘绳肌：坐地双腿伸直，双手缓慢前伸，背部挺直，维持20秒[6]；
      - 内收肌：坐姿双脚脚底相对，双膝向两侧下压，身体略前倾[6]。
      - 频率：每天3–5组，每组20–30秒[3]。
    - **工具辅助**：泡沫轴滚动大腿，在痛点处停留10–20秒，每日1–2次；筋膜球/按摩球定点按压臀部与大腿连接处（梨状肌区域）[6]。
    - **温水浴**：40℃左右泡浴放松肌肉，避免穿高跟鞋或过紧衣物[1]。

    ### 5.3 针对病因的医学处理

    - 神经痛可遵医嘱使用加巴喷丁等药物；针对原发病治疗（如控制血糖、补充维生素）[1]。
    - 神经炎若源于糖尿病、酒精中毒或维生素B缺乏，需对因干预[1]。

    ### 5.4 长期预防

    - **运动习惯**：运动前后充分热身与拉伸，尤其重视动态热身（高抬腿、侧弓步）；规律锻炼如游泳、瑜伽[1][6]。
    - **体态与核心**：加强核心肌群训练（如平板支撑），改善发力模式，减少大腿代偿[6]。
    - **日常节律**：久坐者每小时起身活动5分钟，做抬腿、踮脚；选择支撑力适中的椅子，膝盖与髋关节保持90°，双脚平放[6]。
    - **睡眠**：选择硬度适中的床垫[3]。
    - **营养**：补充镁、钙（绿叶菜、坚果等），维持水分与电解质平衡[1][3][6]。
    - **压力管理**：通过冥想、深呼吸降低肌肉紧张阈值[6]。

    ---

    ## 六、证据强度与局限说明

    本报告基于6条中文网络科普/百科类来源综合而成，需注意以下局限：

    - 来源[1][3][6]为百度健康"基于AI生成经专家审阅"的科普条目，属于二手归纳性内容，非原始临床研究或临床指南。
    - 来源[2]为百科条目，仅提供大腿的基本解剖定位与功能描述[2]；来源[4]为百科平台的通用说明页，实质内容有限；来源[5]仅提供标题（关于大腿肌肉紧绷疼痛与肌肉痉挛处理的实用指南），未提供可引用的正文细节。
    - 因此，本报告适合作为**理解症状与判断就医时机**的科普参考，不能替代面诊、影像学与实验室检查。若症状持续超过2周、出现上述红旗信号，或伴随麻木、肿胀、夜间痛醒，应及时就医[1][3][6]。

    **一句话总结**：大腿肌肉紧张是"负荷—姿势—神经—循环—代谢—心理"多条通路共同作用的结果，多数为功能性、可自行缓解；真正需要做的是识别红旗信号、分层处理，并对持续不缓解者优先排查腰椎与血管问题[1]。

    > Stats: input 2697 tokens · output 4843 tokens · total 203.73s · TTFT 21ms · 23.8 tok/s

    ## Conversation Summary

    - Turns: 1
    - Input tokens: 2697
    - Output tokens: 4843
    - Total duration: 203.73s
    - Average speed: 23.8 tok/s
    """

    /// How far a pane's viewport sits past its scrollable content. The content
    /// height comes from the text view's own measurement
    /// (`layoutContentHeight`), which includes the pane insets — the preview
    /// mirrors the editor's Vertical/Horizontal Inset, so measuring the raw
    /// fragment frames would understate the real content bottom by the insets.
    @MainActor
    private func previewOvershoot(textView: MarkdownTextView, scrollView: NSScrollView) -> CGFloat {
        let contentMax = max(0, textView.layoutContentHeight - scrollView.contentView.bounds.height)
        return scrollView.contentView.bounds.origin.y - contentMax
    }

    /// Regression for the "blank space under the preview" bug: hosting the real
    /// `DocumentView`, driving the editor to the bottom, and resizing the pane
    /// must never leave the preview scrolled past its rendered content bottom
    /// ("overshoot"). Before the width-sync/re-measure fixes the preview kept a
    /// frame measured at a placeholder width, letting it scroll far past the
    /// content — the reported blank.
    @MainActor
    func testEditorBottomNeverScrollsPreviewIntoBlankSpace() throws {
        let prefs = Preferences()
        prefs.editorBaseFontName = "SF Mono"
        prefs.editorBaseFontSize = 14
        prefs.editorVerticalInset = 16
        prefs.editorHorizontalInset = 16
        prefs.editorLineSpacing = 1.4
        prefs.editorScrollsPastEnd = false
        prefs.editorSyncScrolling = true
        prefs.editorBidirectionalScrollSync = false
        prefs.editorShowWordCount = false
        prefs.previewUsesTextSurface = true
        prefs.previewZoomRelativeToBaseFontSize = true

        let doc = MarkdownDocument(preferences: prefs)
        doc.updateText(Self.reportedMarkdown)
        doc.renderService.parseNow(text: doc.text, options: prefs.parseOptions)

        let hosting = NSHostingView(
            rootView: DocumentView(document: doc).environment(prefs)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func pump(_ turns: Int, _ interval: TimeInterval) {
            for _ in 0..<turns {
                RunLoop.main.run(until: Date().addingTimeInterval(interval))
            }
        }

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            if let sv = view as? NSScrollView { return [sv] }
            return view.subviews.flatMap { findScrollViews(in: $0) }
        }

        func textHost(_ sv: NSScrollView) -> MarkdownTextView? {
            sv.documentView as? MarkdownTextView
        }

        var editorSV: NSScrollView?
        var previewSV: NSScrollView?
        guard let root = window.contentView else { return }
        for sv in findScrollViews(in: root) {
            guard let tv = textHost(sv) else { continue }
            if tv.isEditable, editorSV == nil {
                editorSV = sv
            } else if !tv.isEditable && tv.string.count > 0, previewSV == nil {
                previewSV = sv
            }
        }
        pump(15, 0.1)
        XCTAssertNotNil(editorSV, "editor scroll view must exist")
        XCTAssertNotNil(previewSV, "preview scroll view must exist")
        guard let editorSV, let previewSV,
              let editorDoc = textHost(editorSV), let previewDoc = textHost(previewSV)
        else { return }

        XCTAssertGreaterThan(previewDoc.string.count, 1000, "preview must render the document")
        XCTAssertTrue(
            previewDoc.string.contains("Average speed: 23.8 tok/s"),
            "preview must render the document's final block"
        )

        func scrollEditorToBottom() {
            let clip = editorSV.contentView
            let maxY = max(0, editorDoc.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: maxY))
            editorSV.reflectScrolledClipView(clip)
        }

        // Drive the editor to the bottom (the user's exact gesture).
        scrollEditorToBottom()
        pump(8, 0.05)
        XCTAssertLessThanOrEqual(previewOvershoot(textView: previewDoc, scrollView: previewSV), 0.5,
            "preview must not scroll past its content bottom after the editor reaches the bottom")

        // Pane-width transitions were the transient in the runtime logs (a frame
        // measured at a stale width); re-scan after each resize.
        for width in [1000.0, 600.0, 1400.0] {
            window.setContentSize(NSSize(width: width, height: 900))
            pump(12, 0.05)
            scrollEditorToBottom()
            pump(6, 0.05)
            XCTAssertLessThanOrEqual(previewOvershoot(textView: previewDoc, scrollView: previewSV), 0.5,
                "no blank under the preview after resizing to \(Int(width)) and scrolling to the bottom")
        }
    }

    /// Regression for the root cause: a preview measured while its pane is still
    /// narrow is laid out at a tiny wrap width and over-reports its height; that
    /// inflated frame must self-heal (width sync → re-measure → clamp) once the
    /// pane delivers its real width.
    @MainActor
    func testNarrowPaneMeasurementSelfHealsAfterWidthSync() throws {
        let parsed = MarkdownParser().parseDocument(Self.reportedMarkdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render(parsed.elements)

        // Phase 1 — the pane starts narrow (placeholder sizing during window
        // assembly), so the first measurement happens at a tiny wrap width.
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 120, height: 800))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        textView.setAttributedContent(rendered.attributed)
        textView.layoutSubtreeIfNeeded()
        let placeholderHeight = textView.frame.height
        XCTAssertGreaterThan(placeholderHeight, 5000,
            "a narrow-pane measurement must over-report height (precondition)")

        // ...and park a stale over-scroll where the inflated frame let it go.
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: placeholderHeight - 200))
        scroll.reflectScrolledClipView(clip)

        // Phase 2 — the pane reaches its real width and the app runs its update
        // path: width sync, then setContent (which forces a layout). The frame
        // must shrink to the true content and the vestige scroll origin must be
        // clamped back inside the corrected document.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 748, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.contentView = scroll
        scroll.frame.size = NSSize(width: 748, height: 800)
        window.makeKeyAndOrderFront(nil)
        scroll.tile()

        let contentWidth = scroll.contentSize.width
        textView.setFrameSize(NSSize(width: contentWidth, height: textView.frame.height))
        textView.setAttributedContent(rendered.attributed)
        textView.layoutSubtreeIfNeeded()
        textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)

        let usageBounds = textView.textLayoutManager.usageBoundsForTextContainer
        XCTAssertGreaterThan(contentWidth, 400, "the window must give the pane a real width")
        XCTAssertEqual(textView.textContainer.size.width, contentWidth, accuracy: 0.5,
            "container must track the pane width after the width sync")
        XCTAssertLessThanOrEqual(textView.frame.height, usageBounds.maxY + 0.5,
            "frame must shrink to the measured content after the width sync")

        let maxY = max(0, textView.frame.height - clip.bounds.height)
        XCTAssertLessThanOrEqual(clip.bounds.origin.y, maxY + 0.5,
            "a stale over-scroll must be clamped back inside the corrected document")
    }

    /// Regression for the reported blank-at-bottom: a preview whose document
    /// view is still at a stale (narrow-width) height over-reports its
    /// scrollable range, so clicking the editor's last line drives the preview
    /// past its real content into the empty well. Scroll metrics must report
    /// the TRUE laid-out content height and ignore the stale frame.
    @MainActor
    func testPreviewSyncUsesLayoutHeightNotStaleFrame() throws {
        let parsed = MarkdownParser().parseDocument(Self.reportedMarkdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render(parsed.elements)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 748, height: 800))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.isEditable = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        textView.setAttributedContent(rendered.attributed)
        textView.setFrameSize(NSSize(width: 380, height: 100))
        textView.layoutSubtreeIfNeeded()
        textView.textLayoutManager.ensureLayout(for: textView.textLayoutManager.documentRange)
        let trueHeight = textView.layoutContentHeight
        XCTAssertGreaterThan(trueHeight, 300,
            "the fixture must have real scrollable content (precondition)")

        let coordinator = MarkdownPreviewSurface.Coordinator()
        var captured: ScrollMetrics?
        coordinator.onScroll = { captured = $0 }

        // Simulate the reported precondition: the frame is stuck one notch
        // too tall (the pane's earlier, narrower measurement residue), while
        // the text layout itself is correct for the current width.
        textView.setFrameSize(NSSize(width: textView.frame.width, height: trueHeight + 4000))
        let inflatedFrameHeight = textView.frame.height
        XCTAssertGreaterThan(inflatedFrameHeight, trueHeight + 3990,
            "the stale-tall frame must really be taller than the content (precondition)")

        coordinator.reportMetrics(scroll)
        let contentHeight = captured?.contentHeight ?? 0
        XCTAssertEqual(contentHeight, trueHeight, accuracy: 1,
            "reported content height must be the TRUE laid-out height, not the stale frame")
        XCTAssertLessThan(contentHeight, inflatedFrameHeight - 3990,
            "the stale frame must not widen the reported scrollable range")
    }

    /// Replacing the preview's content with an identical attributed string
    /// (which the representable does on every SwiftUI update, including a
    /// caret-only click in the editor) must not move the viewport: a
    /// selection-keeping scroll during the replacement used to park the
    /// preview below its content, leaving the reported blank well.
    @MainActor
    func testReplacingIdenticalPreviewContentKeepsScrollPosition() throws {
        let parsed = MarkdownParser().parseDocument(Self.reportedMarkdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render(parsed.elements)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 748, height: 820),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 748, height: 820))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 748, height: 100))
        tv.isEditable = false
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        scroll.tile()

        tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
        tv.setAttributedContent(rendered.attributed)
        tv.layoutSubtreeIfNeeded()
        tv.textLayoutManager.ensureLayout(for: tv.textLayoutManager.documentRange)

        let maxY = max(0, tv.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: maxY))
        scroll.reflectScrolledClipView(scroll.contentView)
        let before = scroll.contentView.bounds.origin.y
        XCTAssertGreaterThan(before, 100, "precondition: the preview is scrolled")

        tv.setAttributedContent(rendered.attributed)
        tv.layoutSubtreeIfNeeded()
        let after = scroll.contentView.bounds.origin.y
        XCTAssertEqual(after, before, accuracy: 1,
            "an identical re-render must not move the preview's viewport")
    }

    /// The preview representable runs on every SwiftUI update. Setting the same
    /// rendered content again must be a no-op so a caret-only click in the
    /// editor never invalidates the preview's TextKit layout.
    @MainActor
    func testSetContentSkipsIdenticalRenders() throws {
        let parsed = MarkdownParser().parseDocument(Self.reportedMarkdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render(parsed.elements)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 748, height: 820))
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 748, height: 100))
        tv.isEditable = false
        scroll.documentView = tv
        let coordinator = MarkdownPreviewSurface.Coordinator()
        coordinator.install(on: tv, scrollView: scroll, driver: PaneDriver())

        coordinator.setContent(rendered.attributed, anchorRanges: [])
        let generation = tv.textMutationGeneration
        coordinator.setContent(rendered.attributed, anchorRanges: [])
        XCTAssertEqual(tv.textMutationGeneration, generation,
            "an identical render must not replace the text storage")

        coordinator.setContent(
            NSAttributedString(string: rendered.attributed.string + "extra"),
            anchorRanges: []
        )
        XCTAssertNotEqual(tv.textMutationGeneration, generation,
            "changed content must still be applied")
    }

    /// The Font setting must reach the preview: the chosen family is used for
    /// prose, while fixed-width runs (code, tables, front matter) keep their
    /// monospaced design.
    @MainActor
    func testRendererUsesTheEditorFontForProse() throws {
        let elements: [MarkdownElement] = [
            .heading(level: 1, text: "Title"),
            .paragraph([.text("hello "), .code("let x")])
        ]
        let rendered = AttributedRenderer(theme: .clearness, fontName: "Helvetica").render(elements)

        let ns = rendered.attributed
        let paragraphStart = (ns.string as NSString).range(of: "hello").location
        let codeStart = (ns.string as NSString).range(of: "let x").location
        XCTAssertGreaterThanOrEqual(paragraphStart, 0, "fixture must contain the paragraph")
        XCTAssertGreaterThanOrEqual(codeStart, 0, "fixture must contain the inline code")

        let prose = ns.attribute(.font, at: paragraphStart, effectiveRange: nil) as? NSFont
        let heading = ns.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let code = ns.attribute(.font, at: codeStart, effectiveRange: nil) as? NSFont

        XCTAssertEqual(prose?.familyName, "Helvetica", "prose must use the chosen family")
        XCTAssertEqual(heading?.familyName, "Helvetica", "headings must use the chosen family")
        XCTAssertEqual(heading?.pointSize, 28, "headings keep their own size")
        XCTAssertEqual(code?.isFixedPitch, true, "inline code must stay monospaced")
    }

    /// A table becomes a sized placeholder plus a block the host hands to
    /// WebKit: the text reserves the space, WebKit lays the table out.
    @MainActor
    func testTableEmitsAPlaceholderAndAWebKitBlock() throws {
        let table = TableData(
            headers: ["类别", "具体诱因"],
            rows: [["运动相关", "跑步、跳跃、深蹲过量；发力不均衡"]],
            alignments: [.left, .left]
        )
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render([.table(table)])

        XCTAssertEqual(rendered.tables.count, 1, "one block per table")
        let block = try XCTUnwrap(rendered.tables.first)
        XCTAssertEqual(block.path, [0], "the block is keyed by its element path")
        XCTAssertEqual(block.table.headers, table.headers)
        XCTAssertTrue(
            rendered.attributed.string.contains("\u{FFFC}"),
            "the text reserves a placeholder for the table"
        )
        XCTAssertFalse(
            rendered.attributed.string.contains("│"),
            "the monospaced text grid must not survive into the preview"
        )
        XCTAssertEqual(block.range.length, 1, "the placeholder is one character")
        let attachment = try XCTUnwrap(
            rendered.attributed.attribute(.attachment, at: block.range.location, effectiveRange: nil)
                as? NSTextAttachment
        )
        XCTAssertTrue(attachment === block.attachment, "the block hands out the placeholder's own attachment")
        XCTAssertEqual(
            block.attachment.bounds.height,
            TablePreviewHTML.estimatedHeight(for: table, zoom: 1),
            "the first render reserves the estimate"
        )
    }

    /// A re-render reserves the height WebKit already measured, so the text after
    /// a table does not jump back to an estimate on every document change.
    @MainActor
    func testTableReservesTheHeightWebKitMeasured() throws {
        let table = TableData(headers: ["a", "b"], rows: [["1", "2"]], alignments: [.left, .left])
        let rendered = AttributedRenderer(theme: .clearness, tableHeights: [[0]: 240])
            .render([.table(table)])
        XCTAssertEqual(try XCTUnwrap(rendered.tables.first).attachment.bounds.height, 240)
    }

    // MARK: - Math

    /// A math fence becomes a sized placeholder plus a block the host hands to
    /// WebKit: MathJax typesets the formula over the reserved space.
    @MainActor
    func testMathBlockEmitsAPlaceholderAndAWebKitBlock() throws {
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1)
            .render([.codeBlock(language: "math", code: "E = mc^2")])

        XCTAssertEqual(rendered.mathBlocks.count, 1, "one block per formula")
        let block = try XCTUnwrap(rendered.mathBlocks.first)
        XCTAssertEqual(block.path, [0], "the block is keyed by its element path")
        XCTAssertEqual(block.tex, "E = mc^2")
        XCTAssertTrue(block.isDisplay, "```math fences are display math")
        XCTAssertTrue(
            rendered.attributed.string.contains("\u{FFFC}"),
            "the text reserves a placeholder for the formula"
        )
        XCTAssertEqual(block.range.length, 1, "the placeholder is one character")
        let attachment = try XCTUnwrap(
            rendered.attributed.attribute(.attachment, at: block.range.location, effectiveRange: nil)
                as? NSTextAttachment
        )
        XCTAssertTrue(attachment === block.attachment, "the block hands out the placeholder's own attachment")
        XCTAssertTrue(attachment is MathPreviewHTML.Attachment)
        XCTAssertEqual(
            block.attachment.bounds.height,
            MathPreviewHTML.estimatedHeight(isDisplay: true, zoom: 1),
            "the first render reserves the estimate"
        )
    }

    /// `$…$` and `\(…\)` spans arrive as `math-inline` fences and must be
    /// typeset inline (no display centering) with the smaller reservation.
    @MainActor
    func testInlineMathBlockUsesTheInlineReservation() throws {
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1)
            .render([.codeBlock(language: "math-inline", code: "E = mc^2")])
        let block = try XCTUnwrap(rendered.mathBlocks.first)
        XCTAssertFalse(block.isDisplay)
        XCTAssertEqual(
            block.attachment.bounds.height,
            MathPreviewHTML.estimatedHeight(isDisplay: false, zoom: 1)
        )
    }

    /// Math rendering off (the "TeX Math" preference) keeps the fence as code.
    @MainActor
    func testMathRenderingDisabledKeepsTheFenceAsCode() throws {
        let rendered = AttributedRenderer(theme: .clearness, rendersMath: false)
            .render([.codeBlock(language: "math", code: "E = mc^2")])
        XCTAssertTrue(rendered.mathBlocks.isEmpty)
        XCTAssertTrue(rendered.attributed.string.contains("E = mc^2"))
    }

    /// A re-render reserves the height MathJax already measured, so the text
    /// after a formula does not jump back to an estimate on every keystroke.
    @MainActor
    func testMathReservesTheHeightWebKitMeasured() throws {
        let rendered = AttributedRenderer(theme: .clearness, mathHeights: [[0]: 80])
            .render([.codeBlock(language: "math", code: "E = mc^2")])
        XCTAssertEqual(try XCTUnwrap(rendered.mathBlocks.first).attachment.bounds.height, 80)
    }

    /// End to end for the reported document: `\[ … \]` display math parsed from
    /// source must reach the text surface as a MathJax block, not as prose
    /// brackets.
    @MainActor
    func testDisplayMathFromSourceReachesTheTextSurface() throws {
        let markdown = """
        例如：
        \\[
        a_n=\\frac{1}{n(n+1)}
        \\]
        """
        let parsed = MarkdownParser().parseDocument(
            markdown,
            options: MarkdownParseOptions(enableMath: true)
        )
        let rendered = AttributedRenderer(theme: .clearness).render(parsed.elements)
        XCTAssertEqual(rendered.mathBlocks.count, 1)
        XCTAssertEqual(
            try XCTUnwrap(rendered.mathBlocks.first).tex,
            "a_n=\\frac{1}{n(n+1)}"
        )
    }

    /// A family that does not resolve (including the system name and the legacy
    /// `SF Mono`, which has no reachable name) keeps the preview's system-font
    /// look instead of leaving the text unstyled.
    @MainActor
    func testRendererFallsBackToTheSystemFontForUnresolvableFamilies() throws {
        XCTAssertNil(FontResolver.font(named: FontResolver.systemFontName, size: 14))
        XCTAssertNil(FontResolver.font(named: "NoSuchFont-1234", size: 14))

        for name in [FontResolver.systemFontName, "NoSuchFont-1234", "SF Mono"] {
            let rendered = AttributedRenderer(theme: .clearness, fontName: name)
                .render([.paragraph([.text("hello")])])
            let font = rendered.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            XCTAssertEqual(font, NSFont.systemFont(ofSize: 14), "\(name) must keep the system font")
        }
    }

    /// A family name (not just a PostScript name) must work, so a font typed
    /// into the settings — or one of the CJK monospaced families the settings
    /// hint recommends — renders as chosen.
    @MainActor
    func testRendererAcceptsFamilyNames() throws {
        let rendered = AttributedRenderer(theme: .clearness, fontName: "Menlo")
            .render([.paragraph([.text("hello")])])
        let font = rendered.attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.fontName, "Menlo-Regular")
    }

    // MARK: - Emphasis and CJK

    /// The reported bug: an emphasis run italicized its Latin but left its
    /// Chinese upright, because CoreText's fallback face for CJK (PingFang SC)
    /// has no italic member. The Latin must keep the family's real italic face;
    /// the fallback glyphs must get the synthetic oblique instead.
    @MainActor
    func testEmphasisUsesRealItalicForLatinAndSyntheticItalicForChinese() throws {
        let rendered = AttributedRenderer(theme: .clearness).render([
            .paragraph([.emphasis([.text("hello 中文 world")])])
        ])
        let string = rendered.attributed.string as NSString

        func font(for probe: String) throws -> NSFont {
            let index = string.range(of: probe).location
            XCTAssertGreaterThanOrEqual(index, 0, "fixture must contain \(probe)")
            return try XCTUnwrap(
                rendered.attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            )
        }

        for probe in ["hello", "world"] {
            let latin = try font(for: probe)
            XCTAssertTrue(
                latin.fontDescriptor.symbolicTraits.contains(.italic),
                "\(probe) must keep the family's real italic face"
            )
            XCTAssertEqual(
                CTFontGetMatrix(latin as CTFont).c, 0, accuracy: 0.0001,
                "a real italic face needs no synthetic shear"
            )
        }

        // The Chinese in the middle must not force the Latin after it to stay
        // on the sheared fallback face.
        let chinese = try font(for: "中")
        XCTAssertGreaterThan(
            CTFontGetMatrix(chinese as CTFont).c, 0,
            "the CJK fallback must be sheared into a synthetic italic"
        )
    }

    /// A family with no italic face at all (a CJK monospaced family, say) must
    /// have its whole emphasis run synthesized — otherwise even its Latin stays
    /// upright.
    @MainActor
    func testEmphasisSlantsFamiliesWithoutAnItalicFace() throws {
        guard FontResolver.font(named: "PingFang SC", size: 14) != nil else {
            throw XCTSkip("PingFang SC is not installed on this system")
        }
        let rendered = AttributedRenderer(theme: .clearness, fontName: "PingFang SC").render([
            .paragraph([.emphasis([.text("hello 世界")])])
        ])
        let string = rendered.attributed.string as NSString
        for probe in ["hello", "世"] {
            let index = string.range(of: probe).location
            XCTAssertGreaterThanOrEqual(index, 0, "fixture must contain \(probe)")
            let font = try XCTUnwrap(
                rendered.attributed.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            )
            XCTAssertGreaterThan(
                CTFontGetMatrix(font as CTFont).c, 0,
                "\(probe) must be synthesized when the family has no italic face"
            )
        }
    }

    /// End-to-end guard for the user-visible behavior: the text surface must
    /// actually draw emphasized Chinese differently from plain Chinese, and the
    /// slant must lean the glyph tops to the right (the same direction as the
    /// family's real italic, which the Latin beside it uses).
    @MainActor
    func testChineseEmphasisLeansRightInTheTextSurface() throws {
        let plain = try textSurfaceImage(for: [.paragraph([.text("中文")])])
        let emphasized = try textSurfaceImage(for: [.paragraph([.emphasis([.text("中文")])])])
        XCTAssertNotEqual(
            plain.tiffRepresentation,
            emphasized.tiffRepresentation,
            "emphasized Chinese must render differently from plain Chinese"
        )

        let lean = try XCTUnwrap(Self.verticalLean(of: emphasized), "the fixture must draw glyphs")
        XCTAssertGreaterThan(
            lean.top, lean.bottom,
            "Chinese emphasis must lean the glyph tops right, like the Latin italic face"
        )
    }

    /// Renders one paragraph through the real preview surface and captures the
    /// fragment view's pixels.
    @MainActor
    private func textSurfaceImage(for elements: [MarkdownElement]) throws -> NSBitmapImageRep {
        let rendered = AttributedRenderer(theme: .clearness, zoom: 2).render(elements)
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        textView.isEditable = false
        textView.setAttributedContent(rendered.attributed)
        textView.performFullLayoutForTesting()

        let fragment = try XCTUnwrap(
            textView.renderedFragmentViews.first,
            "the text surface must produce a fragment view"
        )
        let rep = try XCTUnwrap(fragment.bitmapImageRepForCachingDisplay(in: fragment.bounds))
        fragment.cacheDisplay(in: fragment.bounds, to: rep)
        return rep
    }

    /// Mean x of the drawn pixels in the top half vs the bottom half of the
    /// glyph band. A right-leaning (italic) glyph has its top shifted right.
    private static func verticalLean(of rep: NSBitmapImageRep) -> (top: Double, bottom: Double)? {
        var points: [(x: Int, y: Int)] = []
        var minY = Int.max
        var maxY = Int.min
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                points.append((x, y))
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard !points.isEmpty, maxY > minY else { return nil }
        let middle = (minY + maxY) / 2
        func meanX(topHalf: Bool) -> Double {
            let xs = points.filter { topHalf ? $0.y <= middle : $0.y > middle }.map(\.x)
            guard !xs.isEmpty else { return .nan }
            return Double(xs.reduce(0, +)) / Double(xs.count)
        }
        return (meanX(topHalf: true), meanX(topHalf: false))
    }

    /// The preview's text surface must keep the text off the pane edges exactly
    /// like the editor keeps a margin around its text. The representable applies
    /// the editor's horizontal and vertical insets to the preview's text
    /// container; without them the preview ran edge to edge while the editor was
    /// inset.
    @MainActor
    func testPreviewSurfaceAppliesInsetsToTextContainer() throws {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
        textView.isEditable = false
        textView.setAttributedContent(NSAttributedString(string: "hello preview"))

        let insets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
        MarkdownPreviewSurface.applyInsets(insets, to: textView)
        XCTAssertEqual(textView.contentInsets.left, 20, accuracy: 0.5)
        XCTAssertEqual(textView.contentInsets.right, 20, accuracy: 0.5)
        XCTAssertEqual(textView.contentInsets.top, 12, accuracy: 0.5)
        XCTAssertEqual(textView.contentInsets.bottom, 12, accuracy: 0.5)

        textView.performFullLayoutForTesting()
        XCTAssertEqual(textView.textContainer.size.width, 460, accuracy: 0.5,
            "the wrap width must shrink by the horizontal insets")
        XCTAssertEqual(textView.textContainerOrigin.x, 20, accuracy: 0.5,
            "the text must start at the inset, not at the pane edge")
        XCTAssertEqual(textView.textContainerOrigin.y, 12, accuracy: 0.5,
            "the text must start below the top inset")

        // Re-applying unchanged insets must not invalidate the layout: the
        // representable runs on every SwiftUI update, including caret-only
        // clicks in the editor.
        textView.performFullLayoutForTesting()
        XCTAssertFalse(textView.needsFullHeightMeasurement,
            "precondition: the layout is settled")
        MarkdownPreviewSurface.applyInsets(insets, to: textView)
        XCTAssertFalse(textView.needsFullHeightMeasurement,
            "unchanged insets must not request another full height measurement")

        // A vertical-only change (the Vertical Inset slider) must still land.
        MarkdownPreviewSurface.applyInsets(
            NSEdgeInsets(top: 32, left: 20, bottom: 32, right: 20),
            to: textView
        )
        XCTAssertEqual(textView.contentInsets.top, 32, accuracy: 0.5)
        XCTAssertEqual(textView.contentInsets.bottom, 32, accuracy: 0.5)
    }

    /// The document view's height must stay pinned to the true content while
    /// the viewport scrolls: `usageBoundsForTextContainer` is an expanding
    /// estimate, and a frame that grows mid-scroll would widen the scrollable
    /// range past the content, leaving a blank well under the preview.
    @MainActor
    func testFrameStaysPinnedToTrueContentWhileScrolling() throws {
        let parsed = MarkdownParser().parseDocument(Self.reportedMarkdown, options: .init())
        let rendered = AttributedRenderer(theme: .clearness, zoom: 1).render(parsed.elements)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 748, height: 820),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 748, height: 820))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = false
        let tv = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 748, height: 100))
        tv.isEditable = false
        tv.autoresizingMask = [.width]
        scroll.documentView = tv
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        scroll.tile()

        tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
        tv.setAttributedContent(rendered.attributed)
        tv.layoutSubtreeIfNeeded()
        tv.textLayoutManager.ensureLayout(for: tv.textLayoutManager.documentRange)
        let trueHeight = tv.layoutContentHeight
        XCTAssertGreaterThan(trueHeight, 1000, "precondition: the fixture scrolls")

        let maxY = max(0, trueHeight - scroll.contentView.bounds.height)
        for step in 0...10 {
            let y = maxY * CGFloat(step) / 10
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            tv.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(
                tv.frame.height, trueHeight + 2,
                "frame grew past the true content while scrolling to \(y)"
            )
        }
    }

    /// Repro for the user's exact gesture: with the editor parked at the bottom,
    /// *clicking* its last line (a selection change that re-renders the SwiftUI
    /// tree) must not drive the preview past its content into blank space.
    @MainActor
    func testClickingEditorLastLineNeverScrollsPreviewIntoBlankSpace() throws {
        let prefs = Preferences()
        prefs.editorBaseFontName = "SF Mono"
        prefs.editorBaseFontSize = 14
        prefs.editorVerticalInset = 16
        prefs.editorHorizontalInset = 16
        prefs.editorLineSpacing = 1.4
        prefs.editorScrollsPastEnd = true
        prefs.editorSyncScrolling = true
        prefs.editorBidirectionalScrollSync = false
        prefs.editorShowWordCount = false
        prefs.previewUsesTextSurface = true
        prefs.previewZoomRelativeToBaseFontSize = true

        let doc = MarkdownDocument(preferences: prefs)
        doc.updateText(Self.reportedMarkdown)
        doc.renderService.parseNow(text: doc.text, options: prefs.parseOptions)

        let hosting = NSHostingView(
            rootView: DocumentView(document: doc).environment(prefs)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func pump(_ turns: Int, _ interval: TimeInterval) {
            for _ in 0..<turns {
                RunLoop.main.run(until: Date().addingTimeInterval(interval))
            }
        }

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            if let sv = view as? NSScrollView { return [sv] }
            return view.subviews.flatMap { findScrollViews(in: $0) }
        }

        var editorSV: NSScrollView?
        var previewSV: NSScrollView?
        guard let root = window.contentView else { return }
        for sv in findScrollViews(in: root) {
            guard let tv = sv.documentView as? MarkdownTextView else { continue }
            if tv.isEditable, editorSV == nil {
                editorSV = sv
            } else if !tv.isEditable && tv.string.count > 0, previewSV == nil {
                previewSV = sv
            }
        }
        pump(15, 0.1)
        guard let editorSV, let previewSV,
              let editorDoc = editorSV.documentView as? MarkdownTextView,
              let previewDoc = previewSV.documentView as? MarkdownTextView
        else { return }

        // Park the editor at the bottom the way a wheel/trackpad gesture does
        // (live-scroll notifications), then click its last visible line.
        let editorClip = editorSV.contentView
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification, object: editorSV
        )
        editorClip.scroll(to: NSPoint(x: 0, y: max(0, editorDoc.frame.height - editorClip.bounds.height)))
        editorSV.reflectScrolledClipView(editorClip)
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveScrollNotification, object: editorSV
        )
        pump(8, 0.05)

        let clickPoint = NSPoint(x: 120, y: editorClip.bounds.maxY - 6)
        let windowPoint = editorSV.convert(clickPoint, to: nil)
        if let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ) {
            editorDoc.mouseDown(with: event)
        }
        pump(12, 0.05)
        XCTAssertLessThanOrEqual(previewOvershoot(textView: previewDoc, scrollView: previewSV), 0.5,
            "clicking the editor's last line must not leave blank space under the preview")
    }

    /// End-to-end pointer selection through the real SwiftUI document stack:
    /// a drag inside the editor must produce a non-empty selection and the
    /// selection must be copyable.
    @MainActor
    func testEditorPointerSelectionThroughDocumentView() throws {
        let defaults = UserDefaults(suiteName: "MacMarkDownPointerSelectionProbe")!
        defaults.removePersistentDomain(forName: "MacMarkDownPointerSelectionProbe")
        let prefs = Preferences(defaults: defaults)
        prefs.editorBaseFontName = "SF Mono"
        prefs.editorBaseFontSize = 14
        prefs.editorVerticalInset = 16
        prefs.editorHorizontalInset = 16
        prefs.editorLineSpacing = 1.4
        prefs.previewUsesTextSurface = true

        let doc = MarkdownDocument(preferences: prefs)
        doc.updateText(Self.reportedMarkdown)
        doc.renderService.parseNow(text: doc.text, options: prefs.parseOptions)

        let hosting = NSHostingView(rootView: DocumentView(document: doc).environment(prefs))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        func pump(_ turns: Int, _ interval: TimeInterval) {
            for _ in 0..<turns {
                RunLoop.main.run(until: Date().addingTimeInterval(interval))
            }
        }

        func findScrollViews(in view: NSView) -> [NSScrollView] {
            if let sv = view as? NSScrollView { return [sv] }
            return view.subviews.flatMap { findScrollViews(in: $0) }
        }

        var editorSV: NSScrollView?
        guard let root = window.contentView else { return }
        for sv in findScrollViews(in: root) {
            guard let tv = sv.documentView as? MarkdownTextView else { continue }
            if tv.isEditable, editorSV == nil { editorSV = sv }
        }
        pump(15, 0.1)
        guard let editorSV, let host = editorSV.documentView as? MarkdownTextView else {
            XCTFail("no editor text view found")
            return
        }
        host.performFullLayoutForTesting()

        func contentPoint(of offset: Int) -> NSPoint {
            var frame: CGRect = .zero
            if let range = host.textContentStorage.textRange(from: NSRange(location: offset, length: 1)) {
                host.textLayoutManager.enumerateTextSegments(in: range, type: .standard) { _, segmentFrame, _, _ in
                    frame = segmentFrame
                    return true
                }
            }
            return NSPoint(x: frame.midX, y: frame.midY)
        }

        func send(_ type: NSEvent.EventType, at contentPoint: NSPoint) {
            let viewPoint = NSPoint(
                x: contentPoint.x + host.textContainerOrigin.x,
                y: contentPoint.y + host.textContainerOrigin.y
            )
            let windowPoint = host.convert(viewPoint, to: nil)
            guard let event = NSEvent.mouseEvent(
                with: type, location: windowPoint, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 1
            ) else { return }
            let hitView = host.hitTest(viewPoint) ?? host
            switch type {
            case .leftMouseDown: hitView.mouseDown(with: event)
            case .leftMouseDragged: hitView.mouseDragged(with: event)
            case .leftMouseUp: hitView.mouseUp(with: event)
            default: break
            }
        }

        let start = contentPoint(of: 0)
        let end = contentPoint(of: 6)
        send(.leftMouseDown, at: start)
        send(.leftMouseDragged, at: end)
        send(.leftMouseUp, at: end)
        pump(10, 0.05)

        XCTAssertGreaterThan(host.selectedRange().length, 0, "drag must select text")
        XCTAssertEqual(host.selectedRange().location, 0)

        NSPasteboard.general.clearContents()
        host.copy(nil)
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            (host.string as NSString).substring(with: NSRange(location: 0, length: 6))
        )
    }
}
