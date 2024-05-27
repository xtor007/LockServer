import Vapor
import Fluent

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
    
    try app.register(collection: InfoController(db: dbManager))
    
    try app.register(collection: CommantController(db: dbManager, mail: mailManager))
    
    app.get("") { req in
//        let employers = try await Employer.query(on: req.db)
//            .filter(\.$surname == "Khramchenko")
//            .all()
//        for employer in employers {
//            if let id = employer.id {
//                try await addFinger(id: id)
//            }
//        }
        return "ok"
    }
    
    func addCode(id: UUID) async throws {
        let newCode = Card(hash: 67, code: "E28E892A", employerID: id)
        try await newCode.create(on: app.db)
    }
    
    func addFinger(id: UUID) async throws {
        let newCode = Finger(code: 1, employerID: id)
        try await newCode.create(on: app.db)
    }
    
    func addDates(id: UUID) async throws {
        let dates = [
            createDate(day: 29, month: 4, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 29, month: 4, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 29, month: 4, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 29, month: 4, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 30, month: 4, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 30, month: 4, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 30, month: 4, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 30, month: 4, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 1, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 1, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 1, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 1, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 2, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 2, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 2, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 2, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 3, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 3, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 3, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 3, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 4, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 4, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 4, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 4, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 5, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 5, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 5, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 5, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 6, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 6, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 6, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 6, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 7, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 7, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 7, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 7, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 8, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 8, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 8, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 8, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 9, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 9, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 9, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 9, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 10, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 10, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 10, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 10, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 11, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 11, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 11, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 11, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 12, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 12, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 12, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 12, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 13, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 13, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 13, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 13, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 14, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 14, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 14, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 14, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 15, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 15, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 15, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 15, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
            
            createDate(day: 16, month: 5, year: 2024, hour: 10, minute: Int.random(in: 0...59)),
            createDate(day: 16, month: 5, year: 2024, hour: 14, minute: Int.random(in: 0...59)),
            createDate(day: 16, month: 5, year: 2024, hour: 15, minute: Int.random(in: 0...59)),
            createDate(day: 16, month: 5, year: 2024, hour: 19, minute: Int.random(in: 0...59)),
        ]
        
        var isOn = true
        for date in dates {
            let newEnter = Enter(employerID: id, time: date, isOn: isOn)
            try await newEnter.create(on: app.db)
            isOn.toggle()
        }
    }
    
    func createDate(day: Int, month: Int, year: Int, hour: Int, minute: Int) -> Date {
        var dateComponents = DateComponents()
        dateComponents.day = day
        dateComponents.month = month
        dateComponents.year = year
        dateComponents.hour = hour
        dateComponents.minute = minute
        
        let calendar = Calendar.current
        return calendar.date(from: dateComponents)!
    }
}
