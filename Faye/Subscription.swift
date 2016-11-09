//
//  Subscription.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation
import SwiftyJSON

public enum SubscriptionState {
    case pending(Subscription)
    case subscribed(Subscription)
    case queued(Subscription)
    case subscribing(Subscription)
    case unknown(Subscription?)
}

public enum SubscriptionError: Error {
    case conversationError
    case invalidClientID
    case general(subscription: String, error: String)
}

public class Subscription: CustomStringConvertible, Equatable {
    
    public let subscription: String
    
    public let channel: BayeuxChannel
    
    public var clientID: String?
    
    public var hashValue: Int {
        return subscription.hashValue
    }
    
    public init(subscription: String, channel: BayeuxChannel = BayeuxChannel.subscribe, clientID: String?) {
        self.subscription = subscription
        self.channel = channel
        self.clientID = clientID
    }
    
    public func toJSONString() throws -> String {
        do {
            guard let model = try JSON(toDictionary()).rawString() else {
                throw SubscriptionError.conversationError
            }
            
            return model
        }
        catch {
            throw SubscriptionError.invalidClientID
        }
    }
    
    public func toDictionary() throws -> [String:Any] {
        guard let clientID = clientID else {
            throw SubscriptionError.invalidClientID
        }
        
        return [
            Bayeux.channel.rawValue:channel.rawValue,
            Bayeux.clientID.rawValue:clientID,
            Bayeux.subscription.rawValue:subscription
        ]
    }
    
    // MARK: CustomStringConvertible
    
    public var description: String {
        return "Subscription: \(try? self.toDictionary())"
    }
    
}

public func ==(lhs: Subscription, rhs: Subscription) -> Bool {
    return lhs.hashValue == rhs.hashValue
}
