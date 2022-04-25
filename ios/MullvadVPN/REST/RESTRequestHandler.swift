//
//  RESTRequestHandler.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

protocol RESTRequestHandler {
    typealias AuthorizationCompletion = (OperationCompletion<REST.Authorization, REST.Error>) -> Void

    func createURLRequest(endpoint: AnyIPEndpoint, authorization: REST.Authorization?) -> Result<URLRequest, REST.Error>
    func requestAuthorization(completion: @escaping AuthorizationCompletion) -> REST.AuthorizationResult
}

extension REST {

    enum AuthorizationResult {
        /// There is no requirement for authorizing this request.
        case noRequirement

        /// Authorizatiton request is initiated.
        /// Associated value contains a handle that can be used to cancel
        /// the request.
        case pending(Cancellable)
    }

    class AnyRequestHandler: RESTRequestHandler {
        typealias CreateURLRequestBlock = (AnyIPEndpoint, REST.Authorization?) -> Result<URLRequest, REST.Error>
        typealias RequestAuthorizationBlock = (@escaping AuthorizationCompletion) -> AuthorizationResult

        private let _createURLRequest: CreateURLRequestBlock
        private let _requestAuthorization: RequestAuthorizationBlock?

        init(
            createURLRequest: @escaping CreateURLRequestBlock
        ) {
            _createURLRequest = createURLRequest
            _requestAuthorization = nil
        }

        init(
            createURLRequest: @escaping CreateURLRequestBlock,
            requestAuthorization: @escaping RequestAuthorizationBlock
        ) {
            _createURLRequest = createURLRequest
            _requestAuthorization = requestAuthorization
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
            return _requestAuthorization?(completion) ?? .noRequirement
        }
    }

}
