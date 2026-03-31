import Foundation
import Darwin
import VPNCore

// MARK: - Socket path (must match IPCServer.socketPath exactly)

let socketPath: String = {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("AWSVPNClient/daemon.sock")
        .path
}()

// MARK: - Argument parsing (D-11, D-12)

let args = Array(CommandLine.arguments.dropFirst())

let cmd: String
let name: String?

switch (args.first, args.count) {
case ("status", 1):
    cmd = "status"
    name = nil
case ("--disconnect", 2):
    cmd = "disconnect"
    name = args[1]
case (let n?, 1) where !n.hasPrefix("-"):
    cmd = "connect"
    name = n
default:
    fputs("Usage: aws-connect <name> | --disconnect <name> | status\n", stderr)
    exit(1)
}

// MARK: - POSIX socket connect

func openSocket(path: String) -> Int32? {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

    var sunPath = addr.sun_path
    withUnsafeMutablePointer(to: &sunPath) { sunPathPtr in
        path.withCString { cstr in
            _ = Darwin.strncpy(
                UnsafeMutableRawPointer(sunPathPtr).assumingMemoryBound(to: CChar.self),
                cstr,
                MemoryLayout.size(ofValue: addr.sun_path) - 1
            )
        }
    }
    addr.sun_path = sunPath

    let result = withUnsafePointer(to: &addr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }

    if result != 0 {
        Darwin.close(fd)
        return nil
    }

    return fd
}

// MARK: - Read newline-terminated response

func readLine(fd: Int32) -> Data? {
    var result = Data()
    var byte = UInt8(0)
    while Darwin.read(fd, &byte, 1) == 1 {
        if byte == UInt8(ascii: "\n") { return result }
        result.append(byte)
    }
    return result.isEmpty ? nil : result
}

// MARK: - Main flow

guard let fd = openSocket(path: socketPath) else {
    fputs("Start the AWSVPNClient menu bar app first\n", stderr)
    exit(1)
}

let request = IPCRequest(cmd: cmd, name: name)
guard let requestData = try? JSONEncoder().encode(request) else {
    fputs("error: failed to encode request\n", stderr)
    exit(1)
}

var line = requestData
line.append(UInt8(ascii: "\n"))
line.withUnsafeBytes { bytes in
    _ = Darwin.write(fd, bytes.baseAddress!, bytes.count)
}

guard let responseData = readLine(fd: fd) else {
    fputs("error: no response from app\n", stderr)
    Darwin.close(fd)
    exit(1)
}

Darwin.close(fd)

guard let response = try? JSONDecoder().decode(IPCResponse.self, from: responseData) else {
    fputs("error: invalid response\n", stderr)
    exit(1)
}

// MARK: - Handle response (D-04, D-05)

if !response.ok {
    fputs("error: \(response.error ?? "unknown error")\n", stderr)
    exit(1)
}

if cmd == "status", let configs = response.configs {
    let table = formatStatusTable(configs)
    if !table.isEmpty {
        print(table)
    }
}

// connect/disconnect success: exit 0 silently (D-04)
