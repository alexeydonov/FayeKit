//
//  FayeClient.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation
import SwiftyJSON

public protocol ClientDelegate: NSObjectProtocol {
    func client(_ client: Client, received dictionary: NSDictionary, in channel: String)
    func clientReceivedPong(_ client: Client)
    func clientConnectedToServer(_ client: Client)
    func clientDisconnectedFromServer(_ client: Client)
    func clientConnectionFailed(_ client: Client)
    func client(_ client: Client, subscribedTo channel: String)
    func client(_ client: Client, unsubscribedFrom channel: String)
    func client(_ client: Client, failedWithError: Error)
}

public extension ClientDelegate {
    
}

public typealias ChannelSubscriptionBlock = (NSDictionary) -> Void

public class Client: TransportDelegate {
    
    public weak var delegate: ClientDelegate?
    
    public var clientID: String?
    
    public var urlString: String {
        didSet {
            if let transport = self.transport {
                transport.urlString = urlString
            }
        }
    }
    
    var transport: WebSocketTransport?
    
    public internal(set) var connected = false {
        didSet {
            if !connected {
                unsubscribeAllSubscriptions()
            }
        }
    }
    
    var connectionInitiated: Bool?
    
    var messageNumber: UInt32 = 0
    
    var queuedSubscriptions = [Subscription]()
    var pendingSubscriptions = [Subscription]()
    var openSubscriptions = [Subscription]()
    
    var channelSubscriptionBlocks = [String:ChannelSubscriptionBlock]()
    
    lazy var pendingSubscriptionSchedule: Timer = {
        return Timer(timeInterval: 45, target: self, selector: #selector(pendingSubscriptionsAction(_:)), userInfo: nil, repeats: true)
    }()
    
    let timeout: Int
    
    let readOperationQueue = DispatchQueue(label: "com.alexeydonov.faye.read")
    let writeOperationQueue = DispatchQueue(label: "com.alexeydonov.faye.write", attributes: DispatchQueue.Attributes.concurrent)
    
    public init(urlString: String, channel: String?, timeoutAdvice: Int = 10000) {
        self.urlString = urlString
        self.connected = false
        self.timeout = timeoutAdvice
        self.transport = WebSocketTransport(urlString: urlString)
        self.transport!.delegate = self
        
        if let channel = channel {
            self.queuedSubscriptions.append(Subscription(subscription: channel, clientID: clientID))
        }
    }
    
    // MARK: Implementation
    
    @objc private func pendingSubscriptionsAction(_ timer: Timer) {
        guard connected else {
            return
        }
        
        resubscribeToPendingSubscriptions()
    }
    
    private func handshake() {
        writeOperationQueue.sync { [unowned self] in
            let connectionTypes: [String] = [BayeuxConnection.longPolling.rawValue, BayeuxConnection.callback.rawValue, BayeuxConnection.iframe.rawValue, BayeuxConnection.webSocket.rawValue]
            
            let payload: [String:Any] = [
                Bayeux.channel.rawValue:BayeuxChannel.handshake.rawValue,
                Bayeux.version.rawValue:"1.0",
                Bayeux.minimumVersion.rawValue:"1.0beta",
                Bayeux.supportedConnectionTypes.rawValue:connectionTypes
            ]
            
            if let s = JSON(payload).rawString() {
                self.transport?.write(string: s)
            }
        }
    }
    
    private func connect() {
        writeOperationQueue.sync { [unowned self] in
            let payload: [String:Any] = [
                Bayeux.channel.rawValue:BayeuxChannel.connect.rawValue,
                Bayeux.clientID.rawValue:self.clientID!,
                Bayeux.connectionType.rawValue:BayeuxConnection.webSocket.rawValue,
                Bayeux.advice.rawValue:["timeout":self.timeout]
            ]
            
            if let s = JSON(payload).rawString() {
                self.transport?.write(string: s)
            }
        }
    }
    
    private func disconnect() {
        writeOperationQueue.sync { [unowned self] in
            let payload: [String:Any] = [
                Bayeux.channel.rawValue:BayeuxChannel.disconnect.rawValue,
                Bayeux.clientID.rawValue:self.clientID!,
                Bayeux.connectionType.rawValue:BayeuxConnection.webSocket.rawValue
            ]
            
            if let s = JSON(payload).rawString() {
                self.transport?.write(string: s)
            }
        }
    }
    
    private func subscribe(to model: Subscription) {
        writeOperationQueue.sync { [unowned self] in
            do {
                let json = try model.toJSONString()
                self.transport?.write(string: json)
                self.pendingSubscriptions.append(model)
            }
            catch SubscriptionError.conversationError {

            }
            catch SubscriptionError.invalidClientID where !self.clientID!.isEmpty {
                model.clientID = self.clientID
                self.subscribe(to: model)
            }
            catch {

            }
        }
    }

    private func unsubscribe(from channel: String) {
        writeOperationQueue.sync { [unowned self] in
            if let clientID = self.clientID {
                let payload: [String:Any] = [
                    Bayeux.channel.rawValue:BayeuxChannel.unsubscribe.rawValue,
                    Bayeux.clientID.rawValue:clientID,
                    Bayeux.subscription.rawValue:channel
                ]
                
                if let s = JSON(payload).rawString() {
                    self.transport?.write(string: s)
                }
            }
        }
    }
    
    private func publish(data: [String:Any], to channel: String) {
        writeOperationQueue.sync { [weak self] in
            if let clientID = self?.clientID, let messageID = self?.nextMessageID(), self?.connected {
                let payload: [String:Any] = [
                    Bayeux.channel.rawValue:channel,
                    Bayeux.clientID.rawValue:clientID,
                    Bayeux.id.rawValue:messageID,
                    Bayeux.data.rawValue:data
                ]
                
                if let s = JSON(payload).rawString() {
                    self?.transport?.write(string: s)
                }
            }
        }
    }
    
    private func subscribeQueuedSubscriptions() {
        for channel in queuedSubscriptions {
            let _ = removeChannelFromQueuedSubscriptions(channel.subscription)
            subscribe(to: channel)
        }
    }
    
    private func resubscribeToPendingSubscriptions() {
        if !pendingSubscriptions.isEmpty {
            for channel in pendingSubscriptions {
                let _ = removeChannelFromPendingSubscriptions(channel.subscription)
                subscribe(to: channel)
            }
        }
    }

    private func unsubscribeAllSubscriptions() {
        (queuedSubscriptions + openSubscriptions + pendingSubscriptions).forEach {
            unsubscribe(from: $0.subscription)
        }
    }
    
    private func send(message: NSDictionary) {
        writeOperationQueue.async { [unowned self] in
            if let s = JSON(message).rawString() {
                self.transport?.write(string: s)
            }
        }
    }
    
    private func receive(message: String) {
        readOperationQueue.sync { [unowned self] in
            if let jsonData = message.data(using: String.Encoding.utf8) {
                self.parseFayeMessage(JSON(data: jsonData))
            }
        }
    }
    
    private func nextMessageID() -> String {
        messageNumber += 1
        
        if messageNumber >= UINT32_MAX {
            messageNumber = 0
        }
        
        return "\(messageNumber)"
    }
    
    func removeChannelFromQueuedSubscriptions(_ channel: String) -> Bool {
        objc_sync_enter(queuedSubscriptions)
        defer {
            objc_sync_exit(queuedSubscriptions)
        }
        
        if let index = queuedSubscriptions.index(where: { $0.subscription == channel }) {
            queuedSubscriptions.remove(at: index)
            return true
        }
        
        return false
    }
    
    func removeChannelFromPendingSubscriptions(_ channel: String) -> Bool {
        objc_sync_enter(pendingSubscriptions)
        defer {
            objc_sync_exit(pendingSubscriptions)
        }
        
        if let index = pendingSubscriptions.index(where: { $0.subscription == channel }) {
            pendingSubscriptions.remove(at: index)
            return true
        }
        
        return false
    }

    func removeChannelFromOpenSubscriptions(_ channel: String) -> Bool {
        objc_sync_enter(openSubscriptions)
        defer {
            objc_sync_exit(openSubscriptions)
        }
        
        if let index = openSubscriptions.index(where: { $0.subscription == channel }) {
            openSubscriptions.remove(at: index)
            return true
        }
        
        return false
    }

    // MARK: TransportDelegate
    
    public func didConnect() {
        connectionInitiated = false
        handshake()
    }
    
    public func didFailConnection(error: Error?) {
        delegate?.clientConnectionFailed(self)
        connectionInitiated = false
        connected = false
    }
    
    public func didDisconnect(error: Error?) {
        delegate?.clientDisconnectedFromServer(self)
        connectionInitiated = false
        connected = false
    }
    
    public func didWriteError(error: Error?) {
        delegate?.client(self, failedWithError: error)
    }
    
    public func didReceiveMessage(text: String) {
        receive(message: text)
    }
    
    public func didReceivePong() {
        delegate?.clientReceivedPong(self)
    }
    
}
