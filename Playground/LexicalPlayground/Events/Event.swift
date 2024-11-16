//
//  Event.swift
//  LexicalPlayground
//
//  Created by Nemanja Kovacevic on 15.11.24..
//

public struct Event : Codable {
  
  let title: String
  
  init(title: String) {
    self.title = title
  }
  
}
