import Testing
@testable import WhatFun

@Suite("Credential store")
struct CredentialStoreTests {
    @Test("Private feed credentials can be replaced and removed")
    func credentialLifecycle() async {
        let store = InMemoryCredentialStore()

        await store.set("https://first.example/feed", for: "feed")
        await store.set("https://second.example/feed", for: "feed")
        #expect(await store.value(for: "feed") == "https://second.example/feed")

        await store.removeValue(for: "feed")
        #expect(await store.value(for: "feed") == nil)
    }
}
