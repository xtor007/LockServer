//
//  AuthTokenPayload.swift
//
//
//  Created by Anatoliy Khramchenko on 14.05.2024.
//

import Vapor
import JWT

struct AuthTokenPayload: JWTPayload {
    
    var subject: SubjectClaim
    var expiration: ExpirationClaim
    
    func verify(using signer: JWTSigner) throws {
        try self.expiration.verifyNotExpired()
    }
}
