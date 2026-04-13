import Foundation
import Embassy

/// Temporary HTTP server on port 8234 that catches the Strava OAuth callback.
/// Listens for a single GET /callback?code=... request, extracts the code,
/// returns a success page, then shuts down.
class StravaOAuthServer {
    private var loop: SelectorEventLoop?
    private var server: DefaultHTTPServer?
    private var thread: Thread?
    private var onCode: ((String) -> Void)?

    func start(onCode: @escaping (String) -> Void) {
        self.onCode = onCode

        thread = Thread {
            do {
                let loop = try SelectorEventLoop(selector: try KqueueSelector())
                self.loop = loop

                let server = DefaultHTTPServer(eventLoop: loop, port: 8234) {
                    (environ, startResponse, sendBody) in

                    let path = environ["PATH_INFO"] as? String ?? ""
                    let query = environ["QUERY_STRING"] as? String ?? ""

                    if path == "/callback" {
                        // Extract code from query string
                        let params = query.split(separator: "&").reduce(into: [String: String]()) { result, pair in
                            let parts = pair.split(separator: "=", maxSplits: 1)
                            if parts.count == 2 {
                                result[String(parts[0])] = String(parts[1])
                            }
                        }

                        let html = """
                        <html><body style="font-family: -apple-system; text-align: center; padding: 60px;">
                        <h2>Connected to Strava</h2>
                        <p>You can close this tab and return to WalkingPad.</p>
                        </body></html>
                        """

                        startResponse("200 OK", [("Content-Type", "text/html")])
                        sendBody(Data(html.utf8))
                        sendBody(Data())

                        if let code = params["code"] {
                            DispatchQueue.main.async {
                                self.onCode?(code)
                                self.stop()
                            }
                        }
                    } else {
                        startResponse("404 Not Found", [])
                        sendBody(Data())
                    }
                }

                self.server = server
                try server.start()
                appLog("Strava OAuth server listening on port 8234")
                loop.runForever()
            } catch {
                appLog("Strava OAuth server error: \(error)")
            }
        }
        thread?.name = "StravaOAuthServer"
        thread?.start()
    }

    func stop() {
        server?.stopAndWait()
        loop?.stop()
        thread?.cancel()
        thread = nil
        server = nil
        loop = nil
        appLog("Strava OAuth server stopped")
    }
}
