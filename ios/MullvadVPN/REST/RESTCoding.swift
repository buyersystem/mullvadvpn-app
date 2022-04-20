//
//  RESTCoding.swift
//  RESTCoding
//
//  Created by pronebird on 27/07/2021.
//  Copyright © 2021 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    enum Coding {}
}

extension REST.Coding {
    /// Returns a JSON encoder used by REST API.
    static func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    /// Returns a JSON decoder used by REST API.
    static func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }

    static func makeJSONEncoderBetaAPI() -> JSONEncoder {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = .custom({ date, encoder in
            var contaner = encoder.singleValueContainer()
            let value = dateFormatter.string(from: date)

            try contaner.encode(value)
        })

        return encoder
    }

    static func makeJSONDecoderBetaAPI() -> JSONDecoder {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = .custom({ decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = dateFormatter.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected date string to be ISO8601-formatted."
            )
        })

        return decoder
    }
}
