//
//  RESTURLSession.swift
//  MullvadVPN
//
//  Created by pronebird on 18/04/2022.
//  Copyright © 2022 Mullvad VPN AB. All rights reserved.
//

import Foundation

extension REST {
    /// URL session delegate.
    static let sharedURLSessionDelegate: SSLPinningURLSessionDelegate = {
        let certificatePath = Bundle.main.path(forResource: "le_root_cert", ofType: "cer")!
        let data = FileManager.default.contents(atPath: certificatePath)!
        let secCertificate = SecCertificateCreateWithData(nil, data as CFData)!

        return SSLPinningURLSessionDelegate(
            sslHostname: ApplicationConfiguration.defaultAPIHostname,
            trustedRootCertificates: [secCertificate]
        )
    }()

    /// URL session.
    static let sharedURLSession = URLSession(
        configuration: .ephemeral,
        delegate: sharedURLSessionDelegate,
        delegateQueue: nil
    )
}
