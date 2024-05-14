//
//  RefreshTokenPayload.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor
import JWT

struct RefreshTokenPayload: JWTPayload {
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    
    init(login: String) {
        expiration = .init(value: .distantFuture)
        subject = .init(value: "\(RefreshTokenPayloadConstants.coder)\(login)")
    }
    
    var login: String {
        subject.value.replacingOccurrences(of: RefreshTokenPayloadConstants.coder, with: "")
    }
    
    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}

enum RefreshTokenPayloadConstants {
    static let coder = "refresh-"
}
