//
//  InAppButton.swift
//  Mixpanel
//
//  Created by Yarden Eitan on 1/24/17.
//  Copyright © 2017 Mixpanel. All rights reserved.
//

import Foundation

open class InAppButton {
    enum PayloadKey {
        static let text = "text"
        static let textColor = "text_color"
        static let backgroundColor = "bg_color"
        static let borderColor = "border_color"
        static let callToActionURL = "cta_url"
    }
    
    public let text: String
    public let textColor: UInt
    public let backgroundColor: UInt
    public let borderColor: UInt
    public let callToActionURLString: String?
    public let callToActionURL: URL?

    init?(JSONObject: [String: Any]?) {
        guard let object = JSONObject else {
            Logger.error(message: "notification button json object should not be nil")
            return nil
        }

        guard let text = object[PayloadKey.text] as? String else {
            Logger.error(message: "invalid notification button text")
            return nil
        }

        guard let textColor = object[PayloadKey.textColor] as? UInt else {
            Logger.error(message: "invalid notification button text color")
            return nil
        }

        guard let backgroundColor = object[PayloadKey.backgroundColor] as? UInt else {
            Logger.error(message: "invalid notification button background color")
            return nil
        }

        guard let borderColor = object[PayloadKey.borderColor] as? UInt else {
            Logger.error(message: "invalid notification button border color")
            return nil
        }

        var callToActionURL: URL?
        if let URLString = object[PayloadKey.callToActionURL] as? String {
            callToActionURLString = URLString
            callToActionURL = URL(string: URLString)
        } else {
            callToActionURLString = nil
        }

        self.text               = text
        self.textColor          = textColor
        self.backgroundColor    = backgroundColor
        self.borderColor        = borderColor
        self.callToActionURL    = callToActionURL

    }
    
    open func payload() -> [String: AnyObject] {
        var payload = [String: AnyObject]()
        payload[PayloadKey.text] = text as AnyObject
        payload[PayloadKey.textColor] = textColor as AnyObject
        payload[PayloadKey.backgroundColor] = backgroundColor as AnyObject
        payload[PayloadKey.borderColor] = borderColor as AnyObject
        if let callToActionURLString = callToActionURL?.absoluteString ?? callToActionURLString {
            payload[PayloadKey.callToActionURL] = callToActionURLString as AnyObject
        }
        return payload
        
    }
}
