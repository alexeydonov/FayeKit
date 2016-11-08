//
//  WebsocketTransport.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation
import Starscream

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
    
    func websocketDidConnect(socket: WebSocket) {
        delegate?.didConnect()
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        if error == nil {
            delegate?.didDisconnect(error: .lostConnection)
        }
        else {
            delegate?.didFailConnection(error: error)
        }
    }
    
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        delegate?.didReceiveMessage(text: text)
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: Data) {
        
    }
    
    func websocketDidReceivePong(socket: WebSocket, data: Data?) {
        delegate?.didReceivePong()
    }
    
}
