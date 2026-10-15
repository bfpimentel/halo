import Foundation
import Testing
@testable import IPC

@Suite struct ProtocolTests {
    @Test func triggerParsesPayloadSplittingOnTheFirstEquals() throws {
        let command = try IPC.parse(arguments: ["trigger", "aerospace.workspace", "focused=2", "query=a=b", "empty="])
        #expect(command == .send(.trigger(name: "aerospace.workspace", payload: ["focused": "2", "query": "a=b", "empty": ""])))
    }

    @Test func triggerWithoutPayloadIsValid() throws {
        #expect(try IPC.parse(arguments: ["trigger", "ping"]) == .send(.trigger(name: "ping", payload: [:])))
    }

    @Test func malformedTriggersAreRejected() {
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["trigger"]) }
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["trigger", "focused=2"]) }
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["trigger", "ws", "focused"]) }
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["trigger", "ws", "=2"]) }
    }

    @Test func startTakesAnOptionalConfigDirectory() throws {
        #expect(try IPC.parse(arguments: ["start"]) == .start(config: nil))
        #expect(try IPC.parse(arguments: ["start", "--config", "examples/demo"]) == .start(config: "examples/demo"))
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["start", "examples/demo"]) }
    }

    @Test func visibilityCommandsTakeNamesOrAll() throws {
        #expect(try IPC.parse(arguments: ["toggle", "launcher"]) == .send(.visibility(.toggle, .names(["launcher"]))))
        #expect(try IPC.parse(arguments: ["hide", "bar", "clock"]) == .send(.visibility(.hide, .names(["bar", "clock"]))))
        #expect(try IPC.parse(arguments: ["show", "--all"]) == .send(.visibility(.show, .all)))
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["hide"]) }
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["hide", "--all", "bar"]) }
    }

    @Test func simpleCommandsRejectExtraArguments() throws {
        #expect(try IPC.parse(arguments: ["reload"]) == .send(.reload))
        #expect(try IPC.parse(arguments: ["inspect"]) == .send(.inspect))
        #expect(try IPC.parse(arguments: ["init"]) == .initialize(directory: nil))
        #expect(try IPC.parse(arguments: ["init", "~/widgets"]) == .initialize(directory: "~/widgets"))
        #expect(try IPC.parse(arguments: []) == .help)
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["quit", "now"]) }
        #expect(throws: UsageError.self) { try IPC.parse(arguments: ["restart"]) }
    }

    @Test func requestsRoundTripAsSingleLines() throws {
        let request = Request.trigger(name: "media", payload: ["title": "Line\nbreak"])
        let encoded = try IPC.encode(request)
        #expect(encoded.last == UInt8(ascii: "\n"))
        #expect(encoded.dropLast().contains(UInt8(ascii: "\n")) == false)
        #expect(try IPC.decode(Request.self, from: encoded.dropLast()) == request)
    }
}
