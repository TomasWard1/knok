import ArgumentParser
import Foundation
import KnokCore

@main
struct KnokCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "knok",
        abstract: "Send alerts to the human via Knok",
        version: KnokConstants.version,
        subcommands: [Whisper.self, Nudge.self, Knock.self, Break.self]
    )
}

// MARK: - Shared Options

struct AlertOptions: ParsableArguments {
    @Argument(help: "Alert message")
    var message: String

    @Option(name: .long, help: "Alert title (defaults to message)")
    var title: String?

    @Flag(name: .long, help: "Speak the message via text-to-speech")
    var tts = false

    @Option(name: .long, parsing: .upToNextOption, help: "Action buttons as label:id pairs")
    var action: [String] = []

    @Option(name: .long, help: "Auto-dismiss after N seconds (0 = never)")
    var ttl: Int = 0

    @Option(name: .long, help: "SF Symbol name for the alert icon (e.g. 'bolt.fill')")
    var icon: String?

    @Option(name: .long, help: "Hex accent color (e.g. '#A855F7')")
    var color: String?

    func parseActions() -> [AlertAction] {
        action.compactMap { str in
            let parts = str.split(separator: ":", maxSplits: 2)
            guard parts.count >= 2 else { return nil }
            let url = parts.count >= 3 ? String(parts[2]) : nil
            return AlertAction(label: String(parts[0]), id: String(parts[1]), url: url)
        }
    }
}

// MARK: - Subcommands

struct Whisper: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a whisper-level alert (menu bar flash)"
    )

    @OptionGroup var options: AlertOptions

    func run() throws {
        try sendAlert(level: .whisper, options: options)
    }
}

struct Nudge: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a nudge-level alert (floating banner)"
    )

    @OptionGroup var options: AlertOptions

    func run() throws {
        try sendAlert(level: .nudge, options: options)
    }
}

struct Knock: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a knock-level alert (overlay)"
    )

    @OptionGroup var options: AlertOptions

    func run() throws {
        try sendAlert(level: .knock, options: options)
    }
}

struct Break: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a break-level alert (full-screen takeover)"
    )

    @OptionGroup var options: AlertOptions

    func run() throws {
        try sendAlert(level: .break, options: options)
    }
}

// MARK: - Send

func sendAlert(level: AlertLevel, options: AlertOptions) throws {
    let payload = AlertPayload(
        level: level,
        title: options.title ?? options.message,
        message: options.title != nil ? options.message : nil,
        tts: options.tts,
        actions: options.parseActions(),
        ttl: options.ttl,
        icon: options.icon,
        color: options.color
    )

    let client = SocketClient()
    do {
        let response = try client.send(payload)
        print(response.action)

        // Exit code: 0 = action taken, 1 = dismissed, 2 = timeout
        switch response.action {
        case "dismissed":
            throw ExitCode(1)
        case "timeout":
            throw ExitCode(2)
        default:
            break // exit 0
        }
    } catch let error as KnokError {
        fputs("Error: \(error.localizedDescription)\n", stderr)
        throw ExitCode.failure
    }
}
