//
//  String+Encoded.swift
//  FayeKit
//
//  Created by Alexey Donov on 09/11/2016.
//  Copyright © 2016 Alexey Donov. All rights reserved.
//

import Foundation

extension String {
    
    var encoded: String {
        guard let utf8 = data(using: String.Encoding.utf8) else {
            return ""
        }
        
        let base64 = utf8.base64EncodedString(options: Data.Base64EncodingOptions())
        
        guard let data = Data(base64Encoded: base64, options: Data.Base64DecodingOptions()), let base64Decoded = String(data: data, encoding: String.Encoding.utf8) else {
            return ""
        }
        
        return base64Decoded
    }
    
}
