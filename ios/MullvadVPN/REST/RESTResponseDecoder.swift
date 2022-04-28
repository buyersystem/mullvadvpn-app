//
//  RESTResponseDecoder.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    struct ResponseDecoder {
        let decoder: JSONDecoder

        init(decoder: JSONDecoder) {
            self.decoder = decoder
        }

        // Parse JSON response into the given `Decodable` type.
        func decodeSuccessResponse<T: Decodable>(_ type: T.Type, from data: Data) -> Result<T, REST.Error> {
            return Result { try decoder.decode(type, from: data) }
                .mapError { error in
                    return .decodeSuccessResponse(error)
                }
        }

        /// Parse JSON response in case of error (Any HTTP code except 2xx).
        func decodeErrorResponse(from data: Data, response: HTTPURLResponse) -> Result<REST.ServerErrorResponse, REST.Error> {
            return Result { () -> REST.ServerErrorResponse in
                return try decoder.decode(REST.ServerErrorResponse.self, from: data)
            }
            .mapError { error in
                return .decodeErrorResponse(error, response.statusCode)
            }
        }

        func decodeErrorResponseAndMapToServerError<T>(from data: Data, response: HTTPURLResponse) -> Result<T, REST.Error> {
            return decodeErrorResponse(from: data, response: response)
                .flatMap { serverError in
                    return .failure(.server(serverError))
                }
        }
    }
}
