import Vapor

func routes(_ app: Application) throws {
    let dbManager = MySQLManager.shared
    let mailManager = SMTPManager.shared
    
    try app.register(collection: KeyVerifierController(
        cardCodeVerifier: CardCodeVerifier(db: dbManager), 
        fingerVerifier: FingerVerifier(db: dbManager))
    )
    
    try app.register(collection: AuthController(db: dbManager, mail: mailManager))
    
    try app.register(collection: OpenController(db: dbManager))
    
    try app.register(collection: ValidServerController())
    
    app.get("") { req in
        return "ok"
    }
}
