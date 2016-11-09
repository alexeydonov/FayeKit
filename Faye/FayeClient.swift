//
//  FayeClient.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation
import SwiftyJSON

public protocol FayeClientDelegate: NSObjectProtocol {
    func fayeClient(_ client: FayeClient, received dictionary: [String:Any], in channel: String)
    func fayeClientReceivedPong(_ client: FayeClient)
    func fayeClientConnectedToServer(_ client: FayeClient)
    func fayeClientDisconnectedFromServer(_ client: FayeClient)
    func fayeClientConnectionFailed(_ client: FayeClient)
    func fayeClient(_ client: FayeClient, subscribedTo channel: String)
    func fayeClient(_ client: FayeClient, unsubscribedFrom channel: String)
    func fayeClient(_ client: FayeClient, failedWithError: Error)
}

public extension FayeClientDelegate {
    func fayeClient(_ client: FayeClient, received dictionary: [String:Any], in channel: String) { }
    func fayeClientReceivedPong(_ client: FayeClient) { }
    func fayeClientConnectedToServer(_ client: FayeClient) { }
    func fayeClientDisconnectedFromServer(_ client: FayeClient) { }
    func fayeClientConnectionFailed(_ client: FayeClient) { }
    func fayeClient(_ client: FayeClient, subscribedTo channel: String) { }
    func fayeClient(_ client: FayeClient, unsubscribedFrom channel: String) { }
    func fayeClient(_ client: FayeClient, failedWithError: Error) { }
}

public typealias ChannelSubscriptionBlock = ([String:Any]) -> Void

public class FayeClient: TransportDelegate {
    
    public weak var delegate: FayeClientDelegate?
    
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
    
    var connectionInitiated = false
    
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
    
    public func connect() {
        if !connectionInitiated {
            transport?.openConnection()
            connectionInitiated = true
        }
    }
    
    public func disconnect() {
        unsubscribeAllSubscriptions()
        writeDisconnectRequest()
    }
    
    public func send(message: [String:Any], to channel: String) {
        publish(data: message, to: channel)
    }
    
    public func ping(data: Data, completion: (() -> Void)?) {
        writeOperationQueue.async { [unowned self] in
            self.transport?.send(ping: data, completion: completion)
        }
    }
    
    public func subscribe(_ subscription: Subscription, block: ChannelSubscriptionBlock? = nil) -> SubscriptionState {
        guard !isSubscribed(to: subscription.subscription) else {
            return .subscribed(subscription)
        }
        
        guard !pendingSubscriptions.contains(subscription) else {
            return .pending(subscription)
        }
        
        if let block = block {
            channelSubscriptionBlocks[subscription.subscription] = block
        }
        
        if !connected {
            queuedSubscriptions.append(subscription)
            return .queued(subscription)
        }
        
        writeSubscribeRequest(to: subscription)
        
        return .subscribing(subscription)
    }
    
    public func subscribe(to channel: String, block: ChannelSubscriptionBlock? = nil) -> SubscriptionState {
        return subscribe(Subscription(subscription: channel, clientID: clientID), block: block)
    }
    
    public func unsubscribe(from channel: String) {
        let _ = removeChannelFromQueuedSubscriptions(channel)
        writeUnsubscribeRequest(from: channel)
        channelSubscriptionBlocks[channel] = nil
        let _ = removeChannelFromOpenSubscriptions(channel)
        let _ = removeChannelFromPendingSubscriptions(channel)
    }
    
    public func isSubscribed(to channel: String) -> Bool {
        return openSubscriptions.contains { $0.subscription == channel }
    }
    
    public var isTransportConnected: Bool {
        return transport!.isConnected
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
    
    private func writeConnectRequest() {
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
    
    private func writeDisconnectRequest() {
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
    
    private func writeSubscribeRequest(to model: Subscription) {
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
                self.writeSubscribeRequest(to: model)
            }
            catch {
                
            }
        }
    }
    
    private func writeUnsubscribeRequest(from channel: String) {
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
            if let clientID = self?.clientID, let messageID = self?.nextMessageID(), let connected = self?.connected, connected {
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
            writeSubscribeRequest(to: channel)
        }
    }
    
    private func resubscribeToPendingSubscriptions() {
        if !pendingSubscriptions.isEmpty {
            for channel in pendingSubscriptions {
                let _ = removeChannelFromPendingSubscriptions(channel.subscription)
                writeSubscribeRequest(to: channel)
            }
        }
    }

    private func unsubscribeAllSubscriptions() {
        (queuedSubscriptions + openSubscriptions + pendingSubscriptions).forEach {
            writeUnsubscribeRequest(from: $0.subscription)
        }
    }
    
    private func send(message: [String:Any]) {
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
        
        return "\(messageNumber)".encoded
    }
    
    private func removeChannelFromQueuedSubscriptions(_ channel: String) -> Bool {
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
    
    private func removeChannelFromPendingSubscriptions(_ channel: String) -> Bool {
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

    private func removeChannelFromOpenSubscriptions(_ channel: String) -> Bool {
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
    
    private func parseFayeMessage(_ message: JSON) {
        let payload = message[0]
        if let channel = payload[Bayeux.channel.rawValue].string {
            if let metaChannel = BayeuxChannel(rawValue: channel) {
                switch metaChannel {
                case .handshake:
                    clientID = payload[Bayeux.clientID.rawValue].stringValue
                    if payload[Bayeux.successful.rawValue].int == 1 {
                        delegate?.fayeClientConnectedToServer(self)
                        connected = true
                        writeConnectRequest()
                        subscribeQueuedSubscriptions()
                        let _ = pendingSubscriptionSchedule.isValid
                    }
                    
                case .connect:
                    if payload[Bayeux.successful.rawValue].int == 1 {
                        connected = true
                        writeConnectRequest()
                    }
                    
                case .disconnect:
                    if payload[Bayeux.successful.rawValue].int == 1 {
                        connected = true
                        transport?.closeConnection()
                        delegate?.fayeClientDisconnectedFromServer(self)
                    }
                    
                case .subscribe:
                    if let success = payload[Bayeux.successful.rawValue].int, success == 1 {
                        if let subscription = payload[Bayeux.subscription.rawValue].string {
                            let _ = removeChannelFromPendingSubscriptions(subscription)
                            openSubscriptions.append(Subscription(subscription: subscription, clientID: clientID))
                            delegate?.fayeClient(self, subscribedTo: subscription)
                        }
                    }
                    else {
                        if let error = payload[Bayeux.error.rawValue].string,
                            let subscription = payload[0][Bayeux.subscription.rawValue].string {
                            let _ = removeChannelFromPendingSubscriptions(subscription)
                            delegate?.fayeClient(self, failedWithError: SubscriptionError.general(subscription: subscription, error: error))
                        }
                    }
                    
                case .unsubscribe:
                    if let subscription = payload[Bayeux.subscription.rawValue].string {
                        let _ = removeChannelFromOpenSubscriptions(subscription)
                        delegate?.fayeClient(self, unsubscribedFrom: subscription)
                    }
                }
            }
            else if isSubscribed(to: channel) {
                if payload[Bayeux.data.rawValue] != JSON.null, let data = payload[Bayeux.data.rawValue].dictionaryObject {
                    if let channelBlock = channelSubscriptionBlocks[channel] {
                        channelBlock(data)
                    }
                    delegate?.fayeClient(self, received: data, in: channel)
                }
            }
        }
    }
    
    // MARK: TransportDelegate
    
    public func didConnect() {
        connectionInitiated = false
        handshake()
    }
    
    public func didFailConnection(error: Error?) {
        delegate?.fayeClientConnectionFailed(self)
        connectionInitiated = false
        connected = false
    }
    
    public func didDisconnect(error: Error?) {
        delegate?.fayeClientDisconnectedFromServer(self)
        connectionInitiated = false
        connected = false
    }
    
    public func didWriteError(error: Error?) {
        delegate?.fayeClient(self, failedWithError: error!)
    }
    
    public func didReceiveMessage(text: String) {
        receive(message: text)
    }
    
    public func didReceivePong() {
        delegate?.fayeClientReceivedPong(self)
    }
    
}
