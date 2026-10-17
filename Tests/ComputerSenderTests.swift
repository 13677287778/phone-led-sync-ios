import XCTest
import Network

final class ComputerSenderTests: XCTestCase {
    func testActualTCPSenderFramingAndReconnect() throws {
        let queue = DispatchQueue(label: "test.pc.receiver")
        let listener = try NWListener(using: .tcp,on: .any)
        let first = expectation(description: "First C1 RGB packet")
        let reconnected = expectation(description: "Reconnect sends latest RGB")
        let sender = ColorSender()
        var connections: [NWConnection] = []
        var accepted = 0
        var firstDone = false, reconnectDone = false
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port {
                var config = LEDSettings(); config.target = .computer
                config.pcHost = "127.0.0.1"; config.pcPort = Int(port.rawValue)
                sender.configure(config,keepStaticColor: true)
                sender.offer(RGB(r: 10,g: 20,b: 30),brightness: 0)
            }
        }
        listener.newConnectionHandler = { connection in
            connections.append(connection); accepted += 1
            let number = accepted
            var buffer = Data()
            func read() {
                connection.receive(minimumIncompleteLength: 1,maximumLength: 1024) { data,_,complete,error in
                    if let data = data { buffer.append(data) }
                    while let end = buffer.firstIndex(of: 10) {
                        let line = String(decoding: buffer.prefix(upTo: end),as: UTF8.self)
                        buffer.removeSubrange(...end)
                        let fields = line.split(separator: ",")
                        XCTAssertEqual(fields.count,6); XCTAssertEqual(fields.first,"C1")
                        guard fields.count == 6 else { return }
                        XCTAssertNotNil(UInt64(fields[1])); XCTAssertNotNil(UInt64(fields[2]))
                        if number == 1 && Array(fields.suffix(3)) == ["10","20","30"] && !firstDone {
                            firstDone = true; first.fulfill()
                            connection.cancel()
                            sender.offer(RGB(r: 90,g: 80,b: 70),brightness: 96)
                            return
                        }
                        if number >= 2 && Array(fields.suffix(3)) == ["90","80","70"] && !reconnectDone {
                            reconnectDone = true; reconnected.fulfill()
                        }
                    }
                    if !complete && error == nil { read() }
                }
            }
            connection.start(queue: queue); read()
        }
        listener.start(queue: queue)
        wait(for: [first,reconnected],timeout: 12)
        sender.stop(); listener.cancel()
        queue.sync { connections.forEach { $0.cancel() } }
    }
}
