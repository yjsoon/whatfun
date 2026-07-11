import Testing
@testable import WhatFun

@Suite("WhatFun smoke tests")
struct SmokeTests {
    @Test("The test target loads the app module")
    func moduleLoads() {
        #expect(Config.applicationName == "WhatFun")
    }
}

