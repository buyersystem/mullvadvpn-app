//
//  RESTDevicesProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation
import class WireGuardKitTypes.PublicKey
import struct WireGuardKitTypes.IPAddressRange

extension REST {
    class DevicesProxy: Proxy<AuthProxyConfiguration> {
        init(configuration: AuthProxyConfiguration) {
            super.init(
                name: "DevicesProxy",
                configuration: configuration,
                requestFactory: RequestFactory.withDefaultAPICredentials(
                    pathPrefix: "/accounts/v1-beta1",
                    bodyEncoder: Coding.makeJSONEncoder()
                ),
                responseDecoder: ResponseDecoder(
                    decoder: Coding.makeJSONDecoder()
                )
            )
        }

        /// Fetch device by identifier.
        /// The completion handler receives `nil` if device is not found.
        func getDevice(
            accountNumber: String,
            identifier: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<Device?>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "device/\(urlEncodedIdentifier)"

                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: path
                    )

                    requestBuilder.setAuthorization(authorization)

                    return requestBuilder.getURLRequest()
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = AnyResponseHandler { response, data -> Result<Device?, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .some(device)
                        }
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(nil)
                } else {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    return .failure(.unhandledResponse(response.statusCode, serverResponse))
                }
            }

            return addOperation(
                name: "get-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Fetch the list of created devices.
        func getDevices(
            accountNumber: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<[Device]>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .get,
                        path: "devices"
                    )

                    requestBuilder.setAuthorization(authorization)

                    return requestBuilder.getURLRequest()
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = REST.defaultResponseHandler(
                decoding: [Device].self,
                with: responseDecoder
            )

            return addOperation(
                name: "get-devices",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Create new device.
        /// The completion handler will receive a `CreateDeviceResponse.created(Device)` on success.
        /// Other `CreateDeviceResponse` variants describe errors.
        func createDevice(
            accountNumber: String,
            request: CreateDeviceRequest,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<CreateDeviceResult>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    var requestBuilder = self.requestFactory.createURLRequestBuilder(
                        endpoint: endpoint,
                        method: .post,
                        path: "devices"
                    )
                    requestBuilder.setAuthorization(authorization)

                    try requestBuilder.setHTTPBody(value: request)

                    return requestBuilder.getURLRequest()
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = AnyResponseHandler { response, data -> Result<CreateDeviceResult, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .succeeded(device)
                        }
                } else if response.statusCode == HTTPStatus.badRequest {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    switch serverResponse?.code {
                    case ServerResponseCode.publicKeyInUse:
                        return .success(.publicKeyInUse)

                    case ServerResponseCode.maxDevicesReached:
                        return .success(.maxDevicesReached)

                    default:
                        return .failure(.unhandledResponse(response.statusCode, serverResponse))
                    }
                } else {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    return .failure(.unhandledResponse(response.statusCode, serverResponse))
                }
            }

            return addOperation(
                name: "create-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Delete device by identifier.
        /// The completion handler will receive `true` if device is successfully removed,
        /// otherwise `false` if device is not found or already removed.
        func deleteDivice(
            accountNumber: String,
            identifier: String,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<Bool>
        ) -> Cancellable
        {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "devices/".appending(urlEncodedIdentifier)

                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .delete,
                            path: path
                        )

                    requestBuilder.setAuthorization(authorization)

                    return requestBuilder.getURLRequest()
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = AnyResponseHandler { response, data -> Result<Bool, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return .success(true)
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(false)
                } else {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )

                    return .failure(.unhandledResponse(response.statusCode, serverResponse))
                }
            }

            return addOperation(
                name: "delete-device",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

        /// Rotate device key
        func rotateDeviceKey(
            accountNumber: String,
            identifier: String,
            publicKey: PublicKey,
            retryStrategy: REST.RetryStrategy,
            completion: @escaping CompletionHandler<RotateDeviceKeyResult>
        ) -> Cancellable {
            let requestHandler = AnyRequestHandler(
                createURLRequest: { endpoint, authorization in
                    let urlEncodedIdentifier = identifier
                        .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
                    let path = "devices/\(urlEncodedIdentifier)/pubkey"

                    var requestBuilder = self.requestFactory
                        .createURLRequestBuilder(
                            endpoint: endpoint,
                            method: .put,
                            path: path
                        )

                    requestBuilder.setAuthorization(authorization)

                    let request = RotateDeviceKeyRequest(
                        pubkey: publicKey.base64Key
                    )
                    try requestBuilder.setHTTPBody(value: request)

                    return requestBuilder.getURLRequest()
                },
                requestAuthorization: { completion in
                    return self.configuration.accessTokenManager
                        .getAccessToken(
                            accountNumber: accountNumber,
                            retryStrategy: retryStrategy
                        ) { operationCompletion in
                            completion(operationCompletion.map { tokenData in
                                return .accessToken(tokenData.accessToken)
                            })
                        }
                }
            )

            let responseHandler = AnyResponseHandler { response, data -> Result<RotateDeviceKeyResult, REST.Error> in
                if HTTPStatus.isSuccess(response.statusCode) {
                    return self.responseDecoder.decodeSuccessResponse(Device.self, from: data)
                        .map { device in
                            return .succeeded(device)
                        }
                } else if response.statusCode == HTTPStatus.badRequest {
                    let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                        from: data,
                        errorLogger: self.logger
                    )
                    
                    if serverResponse?.code == ServerResponseCode.publicKeyInUse {
                        return .success(.publicKeyInUse)
                    } else {
                        return .failure(.unhandledResponse(response.statusCode, serverResponse))
                    }
                } else if response.statusCode == HTTPStatus.notFound {
                    return .success(.deviceNotFound)
                }

                let serverResponse = self.responseDecoder.decoderBetaErrorResponse(
                    from: data,
                    errorLogger: self.logger
                )

                return .failure(.unhandledResponse(response.statusCode, serverResponse))
            }

            return addOperation(
                name: "rotate-device-key",
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                responseHandler: responseHandler,
                completionHandler: completion
            )
        }

    }

    struct CreateDeviceRequest: Encodable {
        let pubkey: String
        let hijackDNS: Bool

        private enum CodingKeys: String, CodingKey {
            case hijackDNS = "hijackDns"
            case pubkey
        }
    }

    enum CreateDeviceResult {
        case succeeded(Device)
        case publicKeyInUse
        case maxDevicesReached
    }

    enum RotateDeviceKeyResult {
        case succeeded(Device)
        case deviceNotFound
        case publicKeyInUse
    }

    fileprivate struct RotateDeviceKeyRequest: Encodable {
        let pubkey: String
    }

    struct Device: Decodable {
        let id: String
        let name: String
        let pubkey: Data
        let hijackDNS: Bool
        let created: Date
        let ipv4Address: IPAddressRange
        let ipv6Address: IPAddressRange
        let ports: [Port]

        private enum CodingKeys: String, CodingKey {
            case hijackDNS = "hijackDns"
            case id, name, pubkey, created, ipv4Address, ipv6Address, ports
        }
    }

    struct Port: Decodable {
        let id: String
    }

}
