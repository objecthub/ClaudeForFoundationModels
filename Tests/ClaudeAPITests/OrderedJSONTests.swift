// Copyright 2026 Anthropic PBC
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing

@testable import ClaudeAPI

/// A model writes the properties of a structured response in schema order, so
/// the declared order of a schema's properties has to reach the wire, even
/// though request bodies are otherwise encoded with sorted keys.
@Suite struct OrderedJSONTests {
  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  private static var order: String { JSONValue.propertyOrderKey }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  private func text(_ value: JSONValue) throws -> String {
    String(decoding: try value.orderedJSON(), as: UTF8.self)
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `properties follow the declared order and the hint is not written`() throws {
    let schema: JSONValue = [
      "type": "object",
      Self.order: ["title", "activities", "budget"],
      "properties": [
        "activities": ["type": "array"],
        "budget": ["type": "integer"],
        "title": ["type": "string"],
      ],
      "required": ["title", "activities", "budget"],
    ]
    #expect(
      try text(schema)
        == #"{"properties":{"title":{"type":"string"},"activities":{"type":"array"},"#
        + #""budget":{"type":"integer"}},"required":["title","activities","budget"],"type":"object"}"#
    )
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `undeclared properties come last, sorted, and unknown names are ignored`() throws {
    let schema: JSONValue = [
      Self.order: ["z", "gone", "z", "m"],
      "properties": ["a": 1, "b": 2, "m": 3, "z": 4],
    ]
    #expect(try text(schema) == #"{"properties":{"z":4,"m":3,"a":1,"b":2}}"#)
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `nested objects keep their own declared order`() throws {
    let inner: JSONValue = [
      Self.order: ["second", "first"],
      "properties": ["first": 1, "second": 2],
    ]
    let schema: JSONValue = [
      Self.order: ["outer2", "outer1"],
      "properties": ["outer1": inner, "outer2": inner],
      "$defs": ["Day": inner],
    ]
    #expect(
      try text(schema)
        == #"{"$defs":{"Day":{"properties":{"second":2,"first":1}}},"#
        + #""properties":{"outer2":{"properties":{"second":2,"first":1}},"#
        + #""outer1":{"properties":{"second":2,"first":1}}}}"#
    )
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `a property named like a keyword is not mistaken for the hint`() throws {
    let schema: JSONValue = [
      Self.order: ["properties", "type"],
      "properties": ["type": ["type": "string"], "properties": ["type": "string"]],
    ]
    #expect(
      try text(schema)
        == #"{"properties":{"properties":{"type":"string"},"type":{"type":"string"}}}"#
    )
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `values are written faithfully`() throws {
    let value: JSONValue = [
      "n": .null, "t": true, "f": false, "i": 16000, "neg": -3, "d": 0.5,
      "s": "quote \" slash / newline \n unicode é 😀",
      "a": [1, "x", .null, [:]],
    ]
    let written = try value.orderedJSON()
    // Valid JSON that decodes back to the same value
    #expect(try JSONDecoder().decode(JSONValue.self, from: written) == value)
    #expect(String(decoding: written, as: UTF8.self).hasPrefix(#"{"a":[1,"x",null,{}],"d":0.5,"f":false,"i":16000,"#))
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `non-finite numbers are rejected`() {
    #expect(throws: EncodingError.self) { try JSONValue.number(.infinity).orderedJSON() }
    #expect(throws: EncodingError.self) { try JSONValue.number(.nan).orderedJSON() }
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `a body without schema order is encoded as before`() throws {
    let request = MessagesRequest(
      model: "claude-opus-4-7",
      maxTokens: 1024,
      messages: [.user("hi")],
      tools: [
        .init(
          name: "echo",
          description: "Echoes input",
          inputSchema: ["type": "object", "properties": ["y": ["type": "string"], "x": ["type": "string"]]]
        )
      ]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(try JSONValue.encodeBody(request) == (try encoder.encode(request)))
  }

  @available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
  @Test func `a request body carries declared order in tools and output format`() throws {
    let schema: JSONValue = [
      "type": "object",
      Self.order: ["title", "activities"],
      "properties": ["activities": ["type": "array"], "title": ["type": "string"]],
    ]
    let request = MessagesRequest(
      model: "claude-opus-4-7",
      maxTokens: 1024,
      messages: [.user("a message mentioning \(Self.order) is harmless")],
      tools: [.init(name: "plan", description: "Plans", inputSchema: schema)],
      outputConfig: .init(format: .init(schema: schema))
    )
    let body = try JSONValue.encodeBody(request)
    let json = String(decoding: body, as: UTF8.self)
    // Both schemas list `title` before `activities`; the hint is gone from the schemas
    let ordered = #""properties":{"title":{"type":"string"},"activities":{"type":"array"}}"#
    #expect(json.components(separatedBy: ordered).count == 3)
    #expect(!json.contains(#""\#(Self.order)""#))
    // Still a valid request
    let decoded = try JSONDecoder().decode(JSONValue.self, from: body)
    #expect(decoded["model"] == "claude-opus-4-7")
    #expect(decoded["max_tokens"] == 1024)
  }
}
