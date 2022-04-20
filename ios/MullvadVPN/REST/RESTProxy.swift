//
//  RESTProxy.swift
//  MullvadVPN
//
//  Created by pronebird on 20/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class Proxy<ConfigurationType: ProxyConfiguration> {
        typealias CompletionHandler<Success> = (OperationCompletion<Success, REST.Error>) -> Void

        /// Synchronization queue used by network operations.
        let dispatchQueue: DispatchQueue

        /// Operation queue used for running network operations.
        let operationQueue = OperationQueue()

        /// Proxy configuration.
        let configuration: ConfigurationType

        /// URL request factory.
        let requestFactory: REST.RequestFactory

        init(
            name: String,
            pathPrefix: String,
            configuration proxyConfiguration: ConfigurationType
        )
        {
            dispatchQueue = DispatchQueue(label: "REST.\(name).dispatchQueue")
            operationQueue.name = "REST.\(name).operationQueue"

            configuration = proxyConfiguration
            requestFactory = REST.RequestFactory(
                hostname: ApplicationConfiguration.defaultAPIHostname,
                pathPrefix: pathPrefix,
                networkTimeout: ApplicationConfiguration.defaultAPINetworkTimeout
            )
        }

        func addOperation<Success>(
            name: String,
            retryStrategy: REST.RetryStrategy,
            requestHandler: AnyRequestHandler<Success>,
            completionHandler: @escaping NetworkOperation<Success>.CompletionHandler
        ) -> Cancellable
        {
            let operation = NetworkOperation(
                name: getTaskIdentifier(name: name),
                dispatchQueue: dispatchQueue,
                configuration: configuration,
                retryStrategy: retryStrategy,
                requestHandler: requestHandler,
                completionHandler: completionHandler
            )

            operationQueue.addOperation(operation)

            return operation
        }
    }
}
