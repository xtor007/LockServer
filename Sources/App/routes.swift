import Vapor

func routes(_ app: Application) throws {
    let dbManager = MySQLManager.shared
    
    try app.register(collection: KeyVerifierController(
        cardCodeVerifier: CardCodeVerifier(db: dbManager), 
        fingerVerifier: FingerVerifier(db: dbManager))
    )
    
    app.get("") { req in
        return "ok"
    }
}
