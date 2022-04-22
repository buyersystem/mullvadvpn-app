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
                configuration: configuration,
                requestFactory: RequestFactory.withDefaultAPICredentials(
                    pathPrefix: "/accounts/v1-beta1",
                    bodyEncoder: Coding.makeJSONEncoder(type: .beta)
                ),
                responseDecoder: ResponseDecoder(
                    decoder: Coding.makeJSONDecoder(type: .beta)
                )
            )
        }

        func getDevices(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<[Device]>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, completion in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "/devices"
                    )

                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { tokenCompletion in
                            let requestCompletion = tokenCompletion.map { tokenData -> URLRequest in
                                requestBuilder.setAuthorization(.accessToken(tokenData.accessToken))
                                return requestBuilder.getURLRequest()
                            }
                            
                            completion(requestCompletion)
                        }
                },
                handleURLResponse: { response, data -> Result<[Device], REST.Error> in
                    if HTTPStatus.isSuccess(response.statusCode) {
                        return self.responseDecoder.decodeSuccessResponse([Device].self, from: data)
                    } else {
                        return self.responseDecoder.decodeErrorResponseAndMapToServerError(from: data)
                    }
                }
            )

            return addOperation(
                name: "get-devices",
                retryStrategy: retryStrategy,
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
