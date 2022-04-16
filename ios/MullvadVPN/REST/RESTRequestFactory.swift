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
    }
}
