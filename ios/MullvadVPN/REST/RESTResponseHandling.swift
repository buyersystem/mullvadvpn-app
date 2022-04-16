//
//  ResponseHandling.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    enum ResponseHandling {}
}

extension REST.ResponseHandling {
    /// Parse JSON response into the given `Decodable` type.
    static func decodeSuccessResponse<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, REST.Error> {
        return Result { try REST.Coding.makeJSONDecoder().decode(type, from: data) }
        .mapError { error in
            return .decodeSuccessResponse(error)
        }
    }

    /// Parse JSON response in case of error (Any HTTP code except 2xx).
    static func decodeErrorResponse(from data: Data) -> Result<REST.ServerErrorResponse, REST.Error> {
        return Result { () -> REST.ServerErrorResponse in
            return try REST.Coding.makeJSONDecoder().decode(REST.ServerErrorResponse.self, from: data)
        }.mapError { error in
            return .decodeErrorResponse(error)
        }
    }

    static func decodeErrorResponseAndMapToServerError<T>(from data: Data) -> Result<T, REST.Error> {
        return Self.decodeErrorResponse(from: data)
            .flatMap { serverError in
                return .failure(.server(serverError))
            }
    }
}
