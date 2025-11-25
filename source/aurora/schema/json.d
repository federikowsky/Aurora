/**
 * Aurora JSON Module - High-Performance JSON with fastjsond
 *
 * Uses fastjsond native API for parsing (zero-copy, SIMD-accelerated)
 * and custom serialization for struct → JSON conversion.
 *
 * Key features:
 * - 10-20x faster parsing than std.json via simdjson
 * - Zero-copy string access during parsing
 * - Thread-local parser for efficiency
 * - Compile-time struct serialization
 */
module aurora.schema.json;

import aurora.schema.exceptions;
import fastjsond;
import std.traits;
import std.array : Appender, appender;
import std.conv : to;
import std.format : format;

// ═══════════════════════════════════════════════════════════════════════════════
// Thread-Local Parser (reused for efficiency)
// ═══════════════════════════════════════════════════════════════════════════════

// Use static storage for thread-local parser
private Parser _tlsParser;
private bool _tlsParserInitialized = false;

/// Get thread-local parser instance (creates on first use)
private ref Parser getParser() @trusted {
    if (!_tlsParserInitialized) {
        _tlsParser = Parser.create();
        _tlsParserInitialized = true;
    }
    return _tlsParser;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Serialization (struct → JSON string)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Serialize any D value to JSON string.
 *
 * Supports: structs, strings, numbers, bools, arrays, associative arrays, null.
 *
 * Example:
 * ---
 * struct User { string name; int age; }
 * auto user = User("Alice", 30);
 * string json = serialize(user);  // {"name":"Alice","age":30}
 * ---
 */
string serialize(T)(auto ref T value) {
    auto buf = appender!string;
    serializeImpl(buf, value);
    return buf[];
}

/// Serialize with pre-allocated buffer (for hot paths)
void serializeTo(T)(ref Appender!string buf, auto ref T value) {
    serializeImpl(buf, value);
}

private void serializeImpl(T)(ref Appender!string buf, auto ref T value) {
    static if (is(T == typeof(null))) {
        buf ~= "null";
    }
    else static if (is(T == bool)) {
        buf ~= value ? "true" : "false";
    }
    else static if (is(T == string) || is(T == const(char)[])) {
        serializeString(buf, value);
    }
    else static if (is(T == char)) {
        buf ~= '"';
        escapeChar(buf, value);
        buf ~= '"';
    }
    else static if (isIntegral!T) {
        buf ~= to!string(value);
    }
    else static if (isFloatingPoint!T) {
        if (value != value) {  // NaN
            buf ~= "null";
        } else if (value == T.infinity) {
            buf ~= "null";
        } else if (value == -T.infinity) {
            buf ~= "null";
        } else {
            buf ~= format("%.17g", value);
        }
    }
    else static if (is(T == struct)) {
        serializeStruct(buf, value);
    }
    else static if (is(T == class)) {
        if (value is null) {
            buf ~= "null";
        } else {
            serializeClass(buf, value);
        }
    }
    else static if (isArray!T && !is(T == string) && !is(T == const(char)[])) {
        serializeArray(buf, value);
    }
    else static if (isAssociativeArray!T) {
        serializeAA(buf, value);
    }
    else static if (is(T : E*, E)) {
        // Pointer
        if (value is null) {
            buf ~= "null";
        } else {
            serializeImpl(buf, *value);
        }
    }
    else {
        static assert(false, "Cannot serialize type: " ~ T.stringof);
    }
}

private void serializeString(ref Appender!string buf, const(char)[] s) {
    buf ~= '"';
    foreach (char c; s) {
        escapeChar(buf, c);
    }
    buf ~= '"';
}

private void escapeChar(ref Appender!string buf, char c) {
    switch (c) {
        case '"':  buf ~= `\"`; break;
        case '\\': buf ~= `\\`; break;
        case '\b': buf ~= `\b`; break;
        case '\f': buf ~= `\f`; break;
        case '\n': buf ~= `\n`; break;
        case '\r': buf ~= `\r`; break;
        case '\t': buf ~= `\t`; break;
        default:
            if (c < 0x20) {
                buf ~= format(`\u%04x`, cast(uint)c);
            } else {
                buf ~= c;
            }
    }
}

private void serializeStruct(T)(ref Appender!string buf, auto ref T value) {
    buf ~= '{';
    bool first = true;
    
    static foreach (fieldName; __traits(allMembers, T)) {{
        static if (__traits(compiles, __traits(getMember, value, fieldName)) &&
                   !isCallable!(__traits(getMember, T, fieldName)) &&
                   fieldName != "Monitor" &&
                   !fieldName.startsWith("__"))
        {
            if (!first) buf ~= ',';
            first = false;
            
            buf ~= '"';
            buf ~= fieldName;
            buf ~= `":`;
            serializeImpl(buf, __traits(getMember, value, fieldName));
        }
    }}
    
    buf ~= '}';
}

private void serializeClass(T)(ref Appender!string buf, T value) if (is(T == class)) {
    buf ~= '{';
    bool first = true;
    
    static foreach (fieldName; __traits(allMembers, T)) {{
        static if (__traits(compiles, __traits(getMember, value, fieldName)) &&
                   !isCallable!(__traits(getMember, T, fieldName)) &&
                   fieldName != "Monitor" &&
                   !fieldName.startsWith("__"))
        {
            if (!first) buf ~= ',';
            first = false;
            
            buf ~= '"';
            buf ~= fieldName;
            buf ~= `":`;
            serializeImpl(buf, __traits(getMember, value, fieldName));
        }
    }}
    
    buf ~= '}';
}

private void serializeArray(T)(ref Appender!string buf, T arr) {
    buf ~= '[';
    bool first = true;
    foreach (ref elem; arr) {
        if (!first) buf ~= ',';
        first = false;
        serializeImpl(buf, elem);
    }
    buf ~= ']';
}

private void serializeAA(T)(ref Appender!string buf, T aa) {
    buf ~= '{';
    bool first = true;
    foreach (key, ref val; aa) {
        if (!first) buf ~= ',';
        first = false;
        
        // Key must be string-like
        static if (is(typeof(key) == string) || is(typeof(key) == const(char)[])) {
            serializeString(buf, key);
        } else {
            buf ~= '"';
            buf ~= to!string(key);
            buf ~= '"';
        }
        buf ~= ':';
        serializeImpl(buf, val);
    }
    buf ~= '}';
}

private bool startsWith(string s, string prefix) {
    return s.length >= prefix.length && s[0 .. prefix.length] == prefix;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Deserialization (JSON string → struct)
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse JSON and deserialize to struct.
 *
 * Uses fastjsond (simdjson) for high-performance parsing.
 *
 * Example:
 * ---
 * struct User { string name; int age; }
 * auto user = deserialize!User(`{"name":"Alice","age":30}`);
 * ---
 */
T deserialize(T)(const(char)[] jsonString) {
    auto doc = getParser().parse(jsonString);
    
    if (!doc.valid) {
        throw new ParseException("Failed to parse JSON: " ~ doc.errorMessage.idup);
    }
    
    return deserializeValue!T(doc.root);
}

/// Deserialize from existing Value (for nested parsing)
T deserializeValue(T)(Value val) {
    static if (is(T == struct)) {
        return deserializeStruct!T(val);
    }
    else static if (is(T == string)) {
        return val.getString().idup;
    }
    else static if (is(T == const(char)[])) {
        // WARNING: Zero-copy, valid only while Document exists
        return val.getString();
    }
    else static if (is(T == bool)) {
        return val.getBool();
    }
    else static if (is(T == int)) {
        return cast(int) val.getInt();
    }
    else static if (is(T == uint)) {
        return cast(uint) val.getUint();
    }
    else static if (is(T == long)) {
        return val.getInt();
    }
    else static if (is(T == ulong)) {
        return val.getUint();
    }
    else static if (is(T == float)) {
        return cast(float) val.getDouble();
    }
    else static if (is(T == double)) {
        return val.getDouble();
    }
    else static if (isArray!T && !is(T == string) && !is(T == const(char)[])) {
        alias E = typeof(T.init[0]);
        T result;
        foreach (elem; val) {
            result ~= deserializeValue!E(elem);
        }
        return result;
    }
    else {
        static assert(false, "Cannot deserialize type: " ~ T.stringof);
    }
}

private T deserializeStruct(T)(Value val) if (is(T == struct)) {
    T result;
    
    static foreach (fieldName; __traits(allMembers, T)) {{
        static if (__traits(compiles, __traits(getMember, result, fieldName)) &&
                   !isCallable!(__traits(getMember, T, fieldName)) &&
                   fieldName != "Monitor" &&
                   !fieldName.startsWith("__"))
        {
            alias FieldType = typeof(__traits(getMember, T, fieldName));
            
            if (val.hasKey(fieldName)) {
                try {
                    __traits(getMember, result, fieldName) = 
                        deserializeValue!FieldType(val[fieldName]);
                } catch (Exception e) {
                    // Skip fields that fail to deserialize
                }
            }
        }
    }}
    
    return result;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Legacy API Compatibility
// ═══════════════════════════════════════════════════════════════════════════════

/// Serialize struct to JSON (legacy name)
alias toJSON = serialize;

/// Deserialize JSON to struct (legacy name)
alias fromJSON = deserialize;

// ═══════════════════════════════════════════════════════════════════════════════
// Raw JSON Parsing
// ═══════════════════════════════════════════════════════════════════════════════

/**
 * Parse JSON string and return root Value.
 *
 * WARNING: The returned Document must be kept alive while using Value.
 * Values contain zero-copy references to the original JSON buffer.
 *
 * Example:
 * ---
 * auto doc = parseRaw(`{"name":"Alice"}`);
 * if (doc.valid) {
 *     const(char)[] name = doc.root["name"].getString;  // Zero-copy!
 *     string nameCopy = name.idup;  // Copy when needed
 * }
 * ---
 */
Document parseRaw(const(char)[] json) {
    return getParser().parse(json);
}

/// Check if JSON string is valid
bool isValidJSON(const(char)[] json) {
    auto doc = getParser().parse(json);
    return doc.valid;
}
