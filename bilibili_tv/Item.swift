//
//  Item.swift
//  bilibili_tv
//
//  Created by debiancc on 2026/4/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
