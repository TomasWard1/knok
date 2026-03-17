import Foundation
import MCP
import KnokCore

// Build the alert tool schema
let alertInputSchema: Value = .object([
    "type": .string("object"),
    "properties": .object([
        "level": .object([
            "type": .string("string"),
            "enum": .array([.string("whisper"), .string("nudge"), .string("knock"), .string("break")]),
            "description": .string("Urgency level"),
        ]),
        "title": .object([
            "type": .string("string"),
            "description": .string("Alert title"),
        ]),
        "message": .object([
            "type": .string("string"),
            "description": .string("Alert body text"),
        ]),
        "tts": .object([
            "type": .string("boolean"),
            "description": .string("Speak the message aloud via text-to-speech"),
            "default": .bool(false),
        ]),
        "actions": .object([
            "type": .string("array"),
            "description": .string("Buttons for the human to respond with"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "label": .object(["type": .string("string")]),
                    "id": .object(["type": .string("string")]),
                ]),
            ]),
        ]),
        "ttl": .object([
            "type": .string("integer"),
            "description": .string("Auto-dismiss after N seconds (0 = never)"),
            "default": .int(0),
        ]),
    ]),
    "required": .array([.string("level"), .string("title")]),
])

// Create MCP server
let server = Server(
    name: "knok",
    version: KnokConstants.version,
    capabilities: .init(tools: .init())
)

// Register tool list handler
await server.withMethodHandler(ListTools.self) { _ in
    ListTools.Result(tools: [
        Tool(
            name: "alert",
            description: "Send an alert to the human via Knok. Urgency levels: whisper (menu bar flash), nudge (floating banner), knock (overlay), break (full-screen takeover). Returns the human's response.",
            inputSchema: alertInputSchema
        )
    ])
}

// Register tool call handler
await server.withMethodHandler(CallTool.self) { params in
    guard params.name == "alert" else {
        return CallTool.Result(
            content: [.text("Unknown tool: \(params.name)")],
            isError: true
        )
    }

    let args = params.arguments ?? [:]

    // Parse level
    guard let levelStr = args["level"]?.stringValue,
          let level = AlertLevel(rawValue: levelStr) else {
        return CallTool.Result(
            content: [.text("Missing or invalid 'level' parameter. Must be one of: whisper, nudge, knock, break")],
            isError: true
        )
    }

    // Parse title
    guard let title = args["title"]?.stringValue else {
        return CallTool.Result(
            content: [.text("Missing required 'title' parameter")],
            isError: true
        )
    }

    // Parse optional fields
    let message = args["message"]?.stringValue
    let tts = args["tts"]?.boolValue ?? false
    let ttl = args["ttl"]?.intValue ?? 0

    // Parse actions
    var actions: [AlertAction] = []
    if case .array(let actionValues) = args["actions"] {
        for actionValue in actionValues {
            if case .object(let obj) = actionValue,
               let label = obj["label"]?.stringValue,
               let id = obj["id"]?.stringValue {
                actions.append(AlertAction(label: label, id: id))
            }
        }
    }

    // Build payload and send to Knok app
    let payload = AlertPayload(
        level: level,
        title: title,
        message: message,
        tts: tts,
        actions: actions,
        ttl: ttl
    )

    let client = SocketClient()
    do {
        let response = try client.send(payload)
        let responseJSON = try JSONEncoder().encode(response)
        let responseString = String(data: responseJSON, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(responseString)])
    } catch {
        return CallTool.Result(
            content: [.text("Failed to send alert: \(error.localizedDescription)")],
            isError: true
        )
    }
}

// Start server with stdio transport
let transport = StdioTransport()
try await server.start(transport: transport)
await server.waitUntilCompleted()
