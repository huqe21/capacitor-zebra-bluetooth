import Foundation
import Capacitor
import ExternalAccessory

/**
 * Capacitor plugin for Zebra printer communication via Classic Bluetooth
 * Uses iOS External Accessory framework directly
 */
@objc(CapacitorZebraBluetoothPlugin)
public class CapacitorZebraBluetoothPlugin: CAPPlugin, StreamDelegate {

    private var session: EASession?
    private var accessory: EAAccessory?
    private let protocolString = "com.zebra.rawport"

    // Stream delegate pattern for reliable writing
    private var writeBuffer: Data?
    private var writeOffset: Int = 0
    private var writeCompletion: ((Bool, String?) -> Void)?

    @objc func discoverPrinters(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            // Get list of connected External Accessory devices
            let accessories = EAAccessoryManager.shared().connectedAccessories

            var printers: [[String: Any]] = []

            for acc in accessories {
                // Check if this accessory supports Zebra protocol
                if acc.protocolStrings.contains(self.protocolString) {
                    let printer: [String: Any] = [
                        "friendlyName": acc.name,
                        "manufacturer": acc.manufacturer,
                        "modelName": acc.modelNumber ?? "",
                        "serialNumber": acc.serialNumber ?? "",
                        "connected": acc.isConnected
                    ]
                    printers.append(printer)
                }
            }

            call.resolve([
                "printers": printers
            ])
        }
    }

    @objc func connectToPrinter(_ call: CAPPluginCall) {
        guard let friendlyName = call.getString("friendlyName") else {
            call.reject("Must provide friendlyName parameter")
            return
        }

        DispatchQueue.main.async {
            // Disconnect from any existing session
            self.disconnectInternal()

            // Find the accessory by friendly name
            let accessories = EAAccessoryManager.shared().connectedAccessories
            guard let acc = accessories.first(where: { $0.name == friendlyName }) else {
                call.reject("Printer '\(friendlyName)' not found. Make sure it's paired in iOS Bluetooth settings.")
                return
            }

            // Check if accessory supports our protocol
            guard acc.protocolStrings.contains(self.protocolString) else {
                call.reject("Printer does not support Zebra protocol (com.zebra.rawport)")
                return
            }

            // Create session
            guard let newSession = EASession(accessory: acc, forProtocol: self.protocolString) else {
                call.reject("Failed to create session with printer")
                return
            }

            self.session = newSession
            self.accessory = acc

            // Open the streams with delegate
            if let inputStream = newSession.inputStream {
                inputStream.delegate = self
                inputStream.schedule(in: .main, forMode: .default)
                inputStream.open()
            }

            if let outputStream = newSession.outputStream {
                outputStream.delegate = self
                outputStream.schedule(in: .main, forMode: .default)
                outputStream.open()
            }

            // Wait a moment for streams to open
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                call.resolve([
                    "success": true,
                    "message": "Connected to \(friendlyName)"
                ])
            }
        }
    }

    @objc func disconnect(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            self.disconnectInternal()
            call.resolve([
                "success": true
            ])
        }
    }

    @objc func isConnected(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            let connected = self.session != nil && self.accessory?.isConnected == true
            call.resolve([
                "connected": connected
            ])
        }
    }

    @objc func getConnectedPrinter(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            if let acc = self.accessory, acc.isConnected {
                let printer: [String: Any] = [
                    "friendlyName": acc.name,
                    "manufacturer": acc.manufacturer,
                    "modelName": acc.modelNumber ?? "",
                    "serialNumber": acc.serialNumber ?? "",
                    "connected": true
                ]
                call.resolve([
                    "printer": printer
                ])
            } else {
                call.resolve([
                    "printer": NSNull()
                ])
            }
        }
    }

    @objc func sendZPL(_ call: CAPPluginCall) {
        guard let zpl = call.getString("zpl") else {
            call.reject("Must provide zpl parameter")
            return
        }

        guard let session = self.session,
              session.outputStream != nil,
              self.accessory?.isConnected == true else {
            call.reject("No printer connected")
            return
        }

        // Convert ZPL string to data
        guard let data = zpl.data(using: .utf8) else {
            call.reject("Failed to encode ZPL string")
            return
        }

        DispatchQueue.main.async {
            guard let outputStream = session.outputStream else {
                call.reject("Output stream not available")
                return
            }

            // Check stream status
            let streamStatus = outputStream.streamStatus
            if streamStatus != .open {
                call.reject("Output stream is not open (status: \(streamStatus.rawValue))")
                return
            }

            // Set up the write buffer and completion handler
            self.writeBuffer = data
            self.writeOffset = 0
            self.writeCompletion = { success, message in
                if success {
                    call.resolve([
                        "success": true,
                        "message": message ?? "ZPL sent successfully"
                    ])
                } else {
                    call.reject(message ?? "Failed to send ZPL")
                }
            }

            // Start writing process - this will trigger stream events
            self.writeData()
        }
    }

    // MARK: - Stream Delegate Writing

    private func writeData() {
        guard let outputStream = self.session?.outputStream,
              let buffer = self.writeBuffer,
              writeOffset < buffer.count else {
            // Writing complete
            if let completion = self.writeCompletion {
                let totalBytes = self.writeBuffer?.count ?? 0
                completion(true, "ZPL sent successfully (\(totalBytes) bytes)")
                self.cleanupWrite()
            }
            return
        }

        // Only write if stream has space available
        if outputStream.hasSpaceAvailable {
            let remainingBytes = buffer.count - writeOffset
            let chunkSize = min(1024, remainingBytes) // Larger chunks since we're event-driven

            buffer.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                let baseAddress = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
                let bytesWritten = outputStream.write(baseAddress.advanced(by: writeOffset), maxLength: chunkSize)

                if bytesWritten > 0 {
                    writeOffset += bytesWritten
                    // Continue writing if there's more data
                    if writeOffset < buffer.count {
                        // Let the stream event trigger the next write
                        // or try again immediately if space is still available
                        DispatchQueue.main.async {
                            self.writeData()
                        }
                    } else {
                        // All data written
                        if let completion = self.writeCompletion {
                            completion(true, "ZPL sent successfully (\(buffer.count) bytes)")
                            self.cleanupWrite()
                        }
                    }
                } else if bytesWritten < 0 {
                    // Error occurred
                    if let completion = self.writeCompletion {
                        completion(false, "Stream write error at offset \(writeOffset)")
                        self.cleanupWrite()
                    }
                }
                // bytesWritten == 0 means buffer is full, wait for next space available event
            }
        }
        // If no space available, wait for NSStreamEventHasSpaceAvailable event
    }

    private func cleanupWrite() {
        self.writeBuffer = nil
        self.writeOffset = 0
        self.writeCompletion = nil
    }

    @objc func getPrinterStatus(_ call: CAPPluginCall) {
        guard let session = self.session,
              self.accessory?.isConnected == true else {
            call.resolve([
                "status": [
                    "connected": false,
                    "ready": false,
                    "printing": false,
                    "paperOut": false,
                    "headOpen": false,
                    "message": "No printer connected"
                ]
            ])
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            // Send ZPL status request command
            let statusCommand = "~HS\n" // Host Status request
            guard let commandData = statusCommand.data(using: .utf8) else {
                call.resolve([
                    "status": [
                        "connected": true,
                        "ready": false,
                        "printing": false,
                        "paperOut": false,
                        "headOpen": false,
                        "message": "Failed to create status command"
                    ]
                ])
                return
            }

            guard let outputStream = session.outputStream,
                  let inputStream = session.inputStream else {
                call.resolve([
                    "status": [
                        "connected": true,
                        "ready": false,
                        "printing": false,
                        "paperOut": false,
                        "headOpen": false,
                        "message": "No streams available"
                    ]
                ])
                return
            }

            // Send status request
            let bytes = [UInt8](commandData)
            let written = outputStream.write(bytes, maxLength: bytes.count)

            if written <= 0 {
                call.resolve([
                    "status": [
                        "connected": true,
                        "ready": false,
                        "printing": false,
                        "paperOut": false,
                        "headOpen": false,
                        "message": "Failed to send status request"
                    ]
                ])
                return
            }

            // Wait a bit for response
            Thread.sleep(forTimeInterval: 0.5)

            // Try to read response
            var buffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = inputStream.read(&buffer, maxLength: buffer.count)

            if bytesRead > 0 {
                let responseData = Data(buffer[0..<bytesRead])
                let responseString = String(data: responseData, encoding: .utf8) ?? ""

                call.resolve([
                    "status": [
                        "connected": true,
                        "ready": true, // If we got a response, printer is ready
                        "printing": false,
                        "paperOut": false,
                        "headOpen": false,
                        "message": "Status: \(responseString)"
                    ]
                ])
            } else {
                // No response, but connected
                call.resolve([
                    "status": [
                        "connected": true,
                        "ready": true, // Assume ready if connected
                        "printing": false,
                        "paperOut": false,
                        "headOpen": false,
                        "message": "Connected, status unknown"
                    ]
                ])
            }
        }
    }

    // MARK: - Stream Delegate

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasSpaceAvailable:
            // Stream has space available - continue writing if we have pending data
            if aStream == self.session?.outputStream, self.writeBuffer != nil {
                self.writeData()
            }

        case .errorOccurred:
            print("Stream error occurred: \(aStream.streamError?.localizedDescription ?? "unknown")")
            if let completion = self.writeCompletion {
                completion(false, "Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
                self.cleanupWrite()
            }

        case .endEncountered:
            print("Stream end encountered")
            if let completion = self.writeCompletion {
                completion(false, "Stream ended unexpectedly")
                self.cleanupWrite()
            }

        case .openCompleted:
            print("Stream opened successfully")

        case .hasBytesAvailable:
            // Input stream has data available (for status responses, etc.)
            break

        default:
            break
        }
    }

    // MARK: - Private Helpers

    private func disconnectInternal() {
        // Clean up any pending write operations
        if let completion = self.writeCompletion {
            completion(false, "Disconnected")
        }
        self.cleanupWrite()

        if let session = self.session {
            if let inputStream = session.inputStream {
                inputStream.close()
                inputStream.remove(from: .main, forMode: .default)
            }
            if let outputStream = session.outputStream {
                outputStream.close()
                outputStream.remove(from: .main, forMode: .default)
            }
            self.session = nil
        }
        self.accessory = nil
    }

    // Clean up on plugin deinit
    deinit {
        disconnectInternal()
    }
}
