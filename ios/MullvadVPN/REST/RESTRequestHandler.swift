//
//  RESTRequestHandler.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol RESTRequestHandler {
    associatedtype Success

    typealias AuthorizationCompletion = (OperationCompletion<REST.Authorization, REST.Error>) -> Void

    func createURLRequest(endpoint: AnyIPEndpoint, authorization: REST.Authorization?) -> Result<URLRequest, REST.Error>
    func requestAuthorization(completion: @escaping AuthorizationCompletion) -> REST.AuthorizationResult
    func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error>
}

extension REST {

    enum AuthorizationResult {
        /// Authorizatiton is not required.
        case notRequired

        /// Authorizatiton request is initiated.
        /// Associated value contains a handle that can be used to cancel
        /// the request.
        case pending(Cancellable)
    }

    class AnyRequestHandler<Success>: RESTRequestHandler {
        typealias CreateURLRequestBlock = (AnyIPEndpoint, REST.Authorization?) -> Result<URLRequest, REST.Error>
        typealias RequestAuthorizationBlock = (@escaping AuthorizationCompletion) -> AuthorizationResult
        typealias HandleURLResponseBlock = (HTTPURLResponse, Data) -> Result<Success, REST.Error>

        private let _createURLRequest: CreateURLRequestBlock
        private let _requestAuthorization: RequestAuthorizationBlock?
        private let _handleURLResponse: HandleURLResponseBlock

        init<T>(_ handler: T) where T: RESTRequestHandler, T.Success == Success {
            _createURLRequest = handler.createURLRequest
            _requestAuthorization = handler.requestAuthorization
            _handleURLResponse = handler.handleURLResponse
        }

        init(
            createURLRequest: @escaping CreateURLRequestBlock,
            handleURLResponse: @escaping HandleURLResponseBlock
        ) {
            _createURLRequest = createURLRequest
            _requestAuthorization = nil
            _handleURLResponse = handleURLResponse
        }

        init(
            createURLRequest: @escaping CreateURLRequestBlock,
            requestAuthorization: @escaping RequestAuthorizationBlock,
            handleURLResponse: @escaping HandleURLResponseBlock
        ) {
            _createURLRequest = createURLRequest
            _requestAuthorization = requestAuthorization
            _handleURLResponse = handleURLResponse
        }

        func createURLRequest(
            endpoint: AnyIPEndpoint,
            authorization: REST.Authorization?
        ) -> Result<URLRequest, REST.Error> {
            return _createURLRequest(endpoint, authorization)
        }

        func requestAuthorization(
            completion: @escaping (OperationCompletion<REST.Authorization, REST.Error>) -> Void
        ) -> REST.AuthorizationResult {
            return _requestAuthorization?(completion) ?? .notRequired
        }

        func handleURLResponse(_ response: HTTPURLResponse, data: Data) -> Result<Success, REST.Error> {
            return _handleURLResponse(response, data)
        }
    }

}
