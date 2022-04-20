//
//  RESTDevicesProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import class WireGuardKitTypes.PublicKey
import struct Network.IPv4Address
import struct Network.IPv6Address

extension REST {
    class DevicesProxy: Proxy<AuthProxyConfiguration> {
        init(configuration: AuthProxyConfiguration) {
            super.init(
                name: "DevicesProxy",
                pathPrefix: "/accounts/v1-beta1",
                configuration: configuration
            )
        }

        func getDevices(accountNumber: String, completion: @escaping CompletionHandler<[Device]>) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint in
                    let request = self.requestFactory.createURLRequest(
                        endpoint: endpoint,
                        method: .get,
                        path: "/devices"
                    )
                    return .success(request)
                },
                handleURLResponse: { response, data -> Result<[Device], REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return REST.ResponseHandling.decodeSuccessResponse([Device].self, from: data)
                    } else {
                        return REST.ResponseHandling.decodeErrorResponseAndMapToServerError(from: data)
                    }
                },
                getAuthorizationProvider: {
                    return AccessTokenAuthorizationProvider(
                        accountNumber: accountNumber,
                        accessTokenManager: self.configuration.accessTokenManager
                    )
                }
            )

            return addOperation(
                name: "get-devices",
                retryStrategy: .default,
                requestHandler: requestHandler,
                completionHandler: completion
            )
        }

    }

    struct Device: Decodable {
        let id: String
        let name: String
        let pubkey: Data
        let hijackDNS: Bool
        let created: Date
        let ipv4Address: IPv4Address
        let ipv6Address: IPv6Address
        let ports: [Port]
    }

    struct Port: Decodable {
        let id: String
    }

}
