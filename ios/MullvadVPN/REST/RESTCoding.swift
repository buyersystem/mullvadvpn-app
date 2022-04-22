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

    enum CoderType {
        case classic
        case beta

        fileprivate var dateEncodingStrategy: JSONEncoder.DateEncodingStrategy {
            switch self {
            case .classic:
                return .iso8601

            case .beta:
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                return .custom({ date, encoder in
                    var contaner = encoder.singleValueContainer()
                    let value = dateFormatter.string(from: date)

                    try contaner.encode(value)
                })
            }
        }

        fileprivate var dateDecodingStrategy: JSONDecoder.DateDecodingStrategy {
            switch self {
            case .classic:
                return .iso8601

            case .beta:
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                return .custom({ decoder in
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
            }
        }
    }

    /// Returns a JSON encoder used by REST API.
    static func makeJSONEncoder(type: CoderType) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dataEncodingStrategy = .base64
        encoder.dateEncodingStrategy = type.dateEncodingStrategy
        return encoder
    }

    /// Returns a JSON decoder used by REST API.
    static func makeJSONDecoder(type: CoderType) -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dataDecodingStrategy = .base64
        decoder.dateDecodingStrategy = type.dateDecodingStrategy
        return decoder
    }
}
