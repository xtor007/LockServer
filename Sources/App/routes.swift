import Vapor

func routes(_ app: Application) throws {
    try app.register(collection: KeyVerifierController())
    
    app.get("") { req in
        "ok"
    }
}
