//
//  RESTProxyFactory.swift
//  MullvadVPN
//
//  Created by pronebird on 19/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    class ProxyFactory {
        let configuration: AuthProxyConfiguration

        static let shared: ProxyFactory = {
            let basicConfiguration = ProxyConfiguration(
                session: REST.sharedURLSession,
                addressCacheStore: AddressCache.Store.shared
            )

            let authenticationProxy = REST.AuthenticationProxy(
                configuration: basicConfiguration
            )
            let accessTokenManager = AccessTokenManager(
                authenticationProxy: authenticationProxy
            )

            let authConfiguration = AuthProxyConfiguration(
                proxyConfiguration: basicConfiguration,
                accessTokenManager: accessTokenManager
            )
            return ProxyFactory(configuration: authConfiguration)
        }()

        init(configuration: AuthProxyConfiguration) {
            self.configuration = configuration
        }

        func createAPIProxy() -> REST.APIProxy {
            return REST.APIProxy(configuration: configuration)
        }

        func createAccountsProxy() -> REST.AccountsProxy {
            return REST.AccountsProxy(configuration: configuration)
        }
    }

    class ProxyConfiguration {
        let session: URLSession
        let addressCacheStore: AddressCache.Store

        init(session: URLSession, addressCacheStore: AddressCache.Store) {
            self.session = session
            self.addressCacheStore = addressCacheStore
        }
    }

    class AuthProxyConfiguration: ProxyConfiguration {
        let accessTokenManager: AccessTokenManager

        init(proxyConfiguration: ProxyConfiguration, accessTokenManager: AccessTokenManager) {
            self.accessTokenManager = accessTokenManager

            super.init(
                session: proxyConfiguration.session,
                addressCacheStore: proxyConfiguration.addressCacheStore
            )
        }
    }
}
