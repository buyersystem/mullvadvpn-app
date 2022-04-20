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
        let dispatchQueue: DispatchQueue
        let operationQueue = OperationQueue()
        let configuration: ConfigurationType

        init(name: String, configuration: ConfigurationType) {
            self.dispatchQueue = DispatchQueue(label: "REST.\(name)Proxy.dispatchQueue")
            self.configuration = configuration
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
