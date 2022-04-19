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
        let session: URLSession
        let addressCacheStore: AddressCache.Store
        let accessTokenManager: AccessTokenManager

        static let shared = ProxyFactory(
            session: REST.sharedURLSession,
            addressCacheStore: AddressCache.Store.shared
        )

        init(session: URLSession, addressCacheStore: AddressCache.Store) {
            self.session = session
            self.addressCacheStore = addressCacheStore

            let authenticationProxy = AuthenticationProxy(
                session: session,
                addressCacheStore: addressCacheStore
            )

            self.accessTokenManager = AccessTokenManager(
                authenticationProxy: authenticationProxy
            )
        }

        func createAPIProxy() -> REST.Client {
            return REST.Client(
                session: session,
                addressCacheStore: addressCacheStore
            )
        }

        func createAccountsProxy() -> AccountsProxy {
            return AccountsProxy(
                session: session,
                addressCacheStore: addressCacheStore,
                accessTokenManager: accessTokenManager
            )
        }
    }
}
