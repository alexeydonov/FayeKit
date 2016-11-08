//
//  Bayeux.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation

public enum BayeuxConnection: String {
    case longPolling = "long-polling"
    case callback = "callback-polling"
    case iframe = "iframe"
    case webSocket = "websocket"
}

public enum BayeuxChannel: String {
    case handshake = "/meta/handshake"
    case connect = "/meta/connect"
    case disconnect = "/meta/disconnect"
    case subscribe = "/meta/subscribe"
    case unsubscribe = "/meta/unsubscribe"
}

public enum Bayeux: String {
    case channel = "channel"
    case version = "version"
    case clientID = "clientId"
    case connectionType = "connectionType"
    case data = "data"
    case subscription = "subscription"
    case id = "id"
    case minimumVersion = "minimumVersion"
    case supportedConnectionTypes = "supportedConnectionTypes"
    case successful = "successful"
    case error = "error"
    case advice = "advice"
}
