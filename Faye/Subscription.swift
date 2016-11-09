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
    
    public func toJSONString(ext: [String:Any]?) throws -> String {
        do {
            guard let model = try JSON(toDictionary(ext: ext)).rawString(String.Encoding.utf8, options: JSONSerialization.WritingOptions()) else {
                throw SubscriptionError.conversationError
            }
            
            return model
        }
        catch {
            throw SubscriptionError.invalidClientID
        }
    }
    
    public func toDictionary(ext: [String:Any]? = nil) throws -> [String:Any] {
        guard let clientID = clientID else {
            throw SubscriptionError.invalidClientID
        }
        
        var result: [String:Any] = [
            Bayeux.channel.rawValue:channel.rawValue,
            Bayeux.clientID.rawValue:clientID,
            Bayeux.subscription.rawValue:subscription
        ]
        
        if let ext = ext {
            result[Bayeux.ext.rawValue] = ext
        }
        
        return result
    }
    
    // MARK: CustomStringConvertible
    
    public var description: String {
        return "Subscription: \(try? self.toDictionary())"
    }
    
}

public func ==(lhs: Subscription, rhs: Subscription) -> Bool {
    return lhs.hashValue == rhs.hashValue
}
