//
//  Transport.swift
//  Faye
//
//  Created by Alexey Donov on 08/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

public protocol Transport {
    
    func write(string: String)
    func openConnection()
    func closeConnection()
    var isConnected: Bool { get }
    
}

public protocol TransportDelegate: class {
    
    func didConnect()
    func didFailConnection(error: Error?)
    func didDisconnect(error: Error?)
    func didWriteError(error: Error?)
    func didReceiveMessage(text: String)
    func didReceivePong()
    
}
