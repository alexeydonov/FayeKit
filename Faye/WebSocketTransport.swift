//
//  WebsocketTransport.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation
import Starscream

public enum WebSocketError: Error {
    case lostConnection
    case transportWire
}

class WebSocketTransport: Transport, WebSocketDelegate, WebSocketPongDelegate {
    var urlString: String?
    var webSocket: WebSocket?
    
    weak var delegate: TransportDelegate?
    
    init(urlString: String) {
        self.urlString = urlString
    }
    
    // MARK: Transport
    
    func write(string: String) {
        webSocket?.write(string: string)
    }
    
    func send(ping: Data, completion: (() -> Void)? = nil) {
        webSocket?.write(ping: ping, completion: completion)
    }
    
    func openConnection() {
        closeConnection()
        self.webSocket = WebSocket(url: URL(string: urlString!)!)
        
        if let webSocket = self.webSocket {
            webSocket.delegate = self
            webSocket.pongDelegate = self
            webSocket.connect()
        }
    }
    
    func closeConnection() {
        if let webSocket = self.webSocket {
            webSocket.delegate = nil
            webSocket.disconnect(forceTimeout: 0, closeCode: 0)
            self.webSocket = nil
        }
    }
    
    var isConnected: Bool {
        return webSocket?.isConnected ?? false
    }
    
    // MARK: WebSocketDelegate
    
    func websocketDidConnect(socket: WebSocketClient) {
        delegate?.didConnect()
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        if error == nil {
            delegate?.didDisconnect(error: WebSocketError.lostConnection)
        }
        else {
            delegate?.didFailConnection(error: error)
        }
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        delegate?.didReceiveMessage(text: text)
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        
    }
    
    func websocketDidReceivePong(socket: WebSocketClient, data: Data?) {
        delegate?.didReceivePong()
    }
    
}
