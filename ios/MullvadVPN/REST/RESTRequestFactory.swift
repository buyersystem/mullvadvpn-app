//
//  RESTRequestFactory.swift
//  MullvadVPN
//
//  Created by pronebird on 16/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class RequestFactory {
        let hostname: String
        let pathPrefix: String
        let networkTimeout: TimeInterval

        init(hostname: String, pathPrefix: String, networkTimeout: TimeInterval) {
            self.hostname = hostname
            self.pathPrefix = pathPrefix
            self.networkTimeout = networkTimeout
        }

        func createURLRequest(endpoint: AnyIPEndpoint, method: HTTPMethod, path: String) -> URLRequest {
            var urlComponents = URLComponents()
            urlComponents.scheme = "https"
            urlComponents.path = pathPrefix
            urlComponents.host = "\(endpoint.ip)"
            urlComponents.port = Int(endpoint.port)

            let requestURL = urlComponents.url!.appendingPathComponent(path)

            var request = URLRequest(
                url: requestURL,
                cachePolicy: .useProtocolCachePolicy,
                timeoutInterval: networkTimeout
            )
            request.httpShouldHandleCookies = false
            request.addValue(hostname, forHTTPHeaderField: HTTPHeader.host)
            request.addValue("application/json", forHTTPHeaderField: HTTPHeader.contentType)
            request.httpMethod = method.rawValue
            return request
        }

        func createURLRequestBuilder(
            endpoint: AnyIPEndpoint,
            method: HTTPMethod,
            path: String
        ) -> RequestBuilder {
            let request = createURLRequest(
                endpoint: endpoint,
                method: method,
                path: path
            )

            return RequestBuilder(request: request)
        }
    }

    struct RequestBuilder {
        private var request: URLRequest

        init(request: URLRequest) {
            self.request = request
        }

        mutating func setHTTPBody<T: Encodable>(value: T) throws {
            request.httpBody = try REST.Coding.makeJSONEncoder().encode(value)
        }

        mutating func setETagHeader(etag: String) {
            var etag = etag
            // Enforce weak validator to account for some backend caching quirks.
            if etag.starts(with: "\"") {
                etag.insert(contentsOf: "W/", at: etag.startIndex)
            }
            request.setValue(etag, forHTTPHeaderField: HTTPHeader.ifNoneMatch)
        }

        mutating func setAuthorization(_ authorization: REST.Authorization) {
            let value: String
            switch authorization {
            case .accountNumber(let accountNumber):
                value = "Token \(accountNumber)"

            case .accessToken(let accessToken):
                value = "Bearer \(accessToken)"
            }

            request.addValue(value, forHTTPHeaderField: HTTPHeader.authorization)
        }

        func getURLRequest() -> URLRequest {
            return request
        }
    }
}
