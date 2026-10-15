import XCTest

final class LongShotUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testHomeAndDemoEditor() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["selectPhotos"].waitForExistence(timeout: 10))
        attach("首页")
        app.swipeUp()
        app.buttons["loadDemo"].tap()
        XCTAssertTrue(app.navigationBars["拼接工作台"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["已按连续内容调整顺序"].waitForExistence(timeout: 10))
        attach("长图预览")
        app.segmentedControls.buttons["拼接点"].tap()
        XCTAssertTrue(app.buttons["seam-0"].exists)
        app.buttons["下张顶部去重增加一个像素"].tap()
        app.buttons["seam-1"].tap()
        XCTAssertTrue(app.staticTexts["拼接点 2"].exists)
        attach("拼接点微调")
        app.segmentedControls.buttons["顺序与裁剪"].tap()
        XCTAssertTrue(app.buttons["重新识别拼接点"].exists)
        attach("裁剪与排序")
        app.buttons["关闭编辑"].tap()
        app.buttons["结束编辑"].tap()
        XCTAssertTrue(app.buttons["selectPhotos"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testRecordingPaywallAndLegal() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["录屏"].tap()
        XCTAssertTrue(app.buttons["unlockRecording"].waitForExistence(timeout: 5))
        attach("录屏使用说明")
        app.buttons["unlockRecording"].tap()
        XCTAssertTrue(app.buttons["annualPlan"].waitForExistence(timeout: 10))
        app.swipeUp()
        XCTAssertTrue(app.buttons["restorePurchases"].exists)
        attach("订阅选项")
        app.buttons["隐私政策"].tap()
        XCTAssertTrue(app.navigationBars["隐私政策"].waitForExistence(timeout: 5))
        app.navigationBars["隐私政策"].buttons["完成"].tap()
        app.navigationBars["长卷 Pro"].buttons["完成"].tap()
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.buttons["使用指南"].exists)
    }

    @MainActor
    func testPhotoPickerCanCancel() throws {
        let app = XCUIApplication()
        app.launch()
        app.buttons["selectPhotos"].tap()
        let cancel = app.buttons["Cancel"].exists ? app.buttons["Cancel"] : app.buttons["取消"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.buttons["selectPhotos"].exists)
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
