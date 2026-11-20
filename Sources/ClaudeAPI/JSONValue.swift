// Copyright 2026 Anthropic PBC
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Loosely-typed JSON for tool inputs/outputs and schemas, where the shape
/// is determined at runtime.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
package enum JSONValue: Sendable, Hashable, Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  package init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
      return
    }
    if let v = try? c.decode(Bool.self) {
      self = .bool(v)
      return
    }
    if let v = try? c.decode(Double.self) {
      self = .number(v)
      return
    }
    if let v = try? c.decode(String.self) {
      self = .string(v)
      return
    }
    if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
      return
    }
    if let v = try? c.decode([String: JSONValue].self) {
      self = .object(v)
      return
    }
    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON value")
  }

  package func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
extension JSONValue {
  /// The named field of an object; `nil` for a missing field or a non-object.
  package subscript(field: String) -> JSONValue? {
    if case .object(let fields) = self { fields[field] } else { nil }
  }

  /// Decodes the value into a `Decodable` type by round-tripping through
  /// `Data` — payload shapes are small, so clarity wins over speed.
  package func decoded<Value: Decodable>() -> Value? {
    guard let data = try? JSONEncoder().encode(self) else { return nil }
    return try? JSONDecoder().decode(Value.self, from: data)
  }

  package static func encoded(_ value: some Encodable) -> JSONValue? {
    guard let data = try? JSONEncoder().encode(value) else { return nil }
    return try? JSONDecoder().decode(JSONValue.self, from: data)
  }

  package static func parsed(_ json: String) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
  }
}

// MARK: - Declared property order

/// JSON Schema objects are unordered, but a model generating structured output
/// writes an object's properties in the order they appear in the schema. Apple's
/// `GenerationSchema` records the declaration order of the properties in
/// `x-order`. Request bodies are encoded with sorted keys, so that equal values
/// always produce equal text. Without further care, this would reorder the
/// properties of a schema alphabetically, and a model that has to write a
/// property such as `activities` before the `title` that gives it context
/// sometimes answers with an empty structure.
///
/// To preserve the declared order, `RequestBuilder` keeps the order of an
/// object's properties under `propertyOrderKey` in the schema, and
/// `encodeBody(_:)` writes the `properties` of such an object in that order.
/// The hint itself never goes over the wire.
@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
extension JSONValue {
  /// In-memory key listing the property names of a schema object in declaration
  /// order. It is not part of JSON Schema and is removed by `encodeBody(_:)`.
  package static let propertyOrderKey = "x-property-order"

  /// The JSON for a request body: compact text with sorted keys, except that the
  /// `properties` of a schema object carrying `propertyOrderKey` are written in
  /// the declared order. A body without such an object is encoded as usual.
  package static func encodeBody(_ body: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(body)
    guard data.range(of: Data(propertyOrderKey.utf8)) != nil else {
      return data
    }
    return try JSONDecoder().decode(JSONValue.self, from: data).orderedJSON()
  }

  /// Compact JSON with sorted keys, except that the `properties` of an object
  /// carrying `propertyOrderKey` follow that order (properties missing from it
  /// come last, sorted). The hint key is not written.
  package func orderedJSON() throws -> Data {
    var text = ""
    try write(to: &text, using: JSONEncoder())
    return Data(text.utf8)
  }

  private func write(to text: inout String, using encoder: JSONEncoder) throws {
    switch self {
    case .null:
      text += "null"
    case .bool(let value):
      text += value ? "true" : "false"
    case .number(let value):
      guard value.isFinite else {
        throw EncodingError.invalidValue(
          value,
          .init(codingPath: [], debugDescription: "JSON cannot represent \(value)")
        )
      }
      if value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
        text += String(Int64(value))
      } else {
        text += "\(value)"
      }
    case .string(let value):
      text += String(decoding: try encoder.encode(value), as: UTF8.self)
    case .array(let items):
      text += "["
      for (index, item) in items.enumerated() {
        if index > 0 { text += "," }
        try item.write(to: &text, using: encoder)
      }
      text += "]"
    case .object(let fields):
      var declared: [String] = []
      if case .array(let names)? = fields[Self.propertyOrderKey] {
        declared = names.compactMap { if case .string(let name) = $0 { name } else { nil } }
      }
      let keys = fields.keys.filter { $0 != Self.propertyOrderKey }.sorted()
      text += "{"
      for (index, key) in keys.enumerated() {
        if index > 0 { text += "," }
        text += String(decoding: try encoder.encode(key), as: UTF8.self) + ":"
        if key == "properties", !declared.isEmpty, case .object(let properties)? = fields[key] {
          try Self.write(properties, in: Self.order(of: properties, declared: declared),
                         to: &text, using: encoder)
        } else {
          try fields[key]?.write(to: &text, using: encoder)
        }
      }
      text += "}"
    }
  }

  /// The keys of `properties`: the declared ones first, in their order, then
  /// the others, sorted.
  private static func order(of properties: [String: JSONValue], declared: [String]) -> [String] {
    var seen = Set<String>()
    let first = declared.filter { properties[$0] != nil && seen.insert($0).inserted }
    return first + properties.keys.filter { !seen.contains($0) }.sorted()
  }

  private static func write(
    _ fields: [String: JSONValue],
    in keys: [String],
    to text: inout String,
    using encoder: JSONEncoder
  ) throws {
    text += "{"
    for (index, key) in keys.enumerated() {
      if index > 0 { text += "," }
      text += String(decoding: try encoder.encode(key), as: UTF8.self) + ":"
      try fields[key]?.write(to: &text, using: encoder)
    }
    text += "}"
  }
}

@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)
extension JSONValue: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral,
  ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
  ExpressibleByStringLiteral, ExpressibleByArrayLiteral,
  ExpressibleByDictionaryLiteral
{
  package init(nilLiteral: ()) { self = .null }
  package init(booleanLiteral value: Bool) { self = .bool(value) }
  package init(integerLiteral value: Int) { self = .number(Double(value)) }
  package init(floatLiteral value: Double) { self = .number(value) }
  package init(stringLiteral value: String) { self = .string(value) }
  package init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
  package init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(.init(uniqueKeysWithValues: elements))
  }
}
