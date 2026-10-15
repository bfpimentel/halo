import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let host = Host()
host.start()

app.run()
