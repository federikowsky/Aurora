/+ dub.sdl:
name "autobahn_server"
dependency "aurora" path=".."
+/
/**
 * Autobahn Test Server - Using Aurora WebSocket Integration
 *
 * This server implements an echo WebSocket server for testing against
 * the Autobahn|Testsuite (wstest).
 *
 * Run with: dub run --single examples/autobahn_server.d
 * Then start wstest against ws://localhost:9002
 *
 * The server echoes:
 * - Text messages back as text
 * - Binary messages back as binary
 * - Responds to ping with pong (automatic via autoReplyPing)
 * - Handles close frames properly
 */
module examples.autobahn_server;

import std.stdio : writeln, writefln;
import aurora;
import aurora.web.websocket;

void main() {
    writeln("===========================================");
    writeln("   Autobahn Test Server - Aurora WebSocket");
    writeln("===========================================");
    writeln();
    
    auto app = new App();
    
    // WebSocket echo endpoint
    app.get("/", (ref ctx) {
        // Configure for Autobahn large frame/message tests
        WebSocketConfig config;
        config.maxFrameSize = 16 * 1024 * 1024;    // 16MB for large frame tests
        config.maxMessageSize = 64 * 1024 * 1024;  // 64MB for fragmentation tests
        config.autoReplyPing = true;
        
        auto ws = upgradeWebSocket(ctx, config);
        if (ws is null) {
            // Not a WebSocket request - return simple info page
            ctx.status(200).send("Aurora WebSocket Autobahn Test Server\n\nConnect via WebSocket to this URL.");
            return;
        }
        scope(exit) ws.close();
        
        // Echo loop
        while (ws.connected) {
            auto msg = ws.receive();
            if (msg.isNull) break;
            
            final switch (msg.get.type) {
                case MessageType.Text:
                    ws.send(msg.get.text);
                    break;
                case MessageType.Binary:
                    ws.sendBinary(msg.get.data);
                    break;
                case MessageType.Close:
                    return;
                case MessageType.Ping:
                case MessageType.Pong:
                    // Handled automatically by autoReplyPing
                    break;
            }
        }
    });
    
    enum PORT = 9003;
    writefln("Listening on ws://localhost:%d", PORT);
    writeln();
    writeln("Run Autobahn tests with:");
    writeln("  docker run -it --rm \\");
    writeln("    -v $(pwd)/tests/autobahn:/config \\");
    writeln("    -v $(pwd)/tests/autobahn/reports:/reports \\");
    writeln("    --network=host \\");
    writeln("    crossbario/autobahn-testsuite \\");
    writeln("    wstest -m fuzzingclient -s /config/fuzzingclient.json");
    writeln();
    writeln("Press Ctrl+C to stop.");
    writeln();
    
    app.listen(PORT);
}
