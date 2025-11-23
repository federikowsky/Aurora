/**
 * Schema System - JSON Serialization Tests
 * 
 * TDD: Tests for toJSON/fromJSON functionality
 */
module tests.unit.schema.json_test;

import unit_threaded;
import aurora.schema;

// Test 1: Simple struct to JSON
@("serialize simple struct to JSON")
unittest
{
    struct User {
        string name;
        int age;
    }
    
    User user = User("Alice", 30);
    string json = user.toJSON();
    
    // JSON field order is not guaranteed, so we verify by deserializing
    User deserialized = fromJSON!User(json);
    deserialized.name.shouldEqual("Alice");
    deserialized.age.shouldEqual(30);
}

// Test 2: JSON to struct (deserialization)
@("deserialize JSON to struct")
unittest
{
    struct User {
        string name;
        int age;
    }
    
    string json = `{"name":"Bob","age":25}`;
    User user = fromJSON!User(json);
    
    user.name.shouldEqual("Bob");
    user.age.shouldEqual(25);
}

// Test 3: Round-trip (serialize → deserialize)
@("JSON round-trip preserves data")
unittest
{
    struct User {
        string name;
        int age;
        bool active;
    }
    
    User original = User("Carol", 35, true);
    
    string json = original.toJSON();
    User deserialized = fromJSON!User(json);
    
    deserialized.name.shouldEqual(original.name);
    deserialized.age.shouldEqual(original.age);
    deserialized.active.shouldEqual(original.active);
}

// Test 4: Nested structs
@("serialize nested structs")
unittest
{
    struct Address {
        string city;
        int zipCode;
    }
    
    struct User {
        string name;
        Address address;
    }
    
    User user = User("Dave", Address("NYC", 10001));
    string json = user.toJSON();
    
    // Verify by round-trip (JSON field order not guaranteed)
    User deserialized = fromJSON!User(json);
    deserialized.name.shouldEqual("Dave");
    deserialized.address.city.shouldEqual("NYC");
    deserialized.address.zipCode.shouldEqual(10001);
}

// Test 5: Arrays
@("serialize arrays")
unittest
{
    struct User {
        string name;
        int[] scores;
    }
    
    User user = User("Eve", [95, 87, 92]);
    string json = user.toJSON();
    
    // Verify by round-trip
    User deserialized = fromJSON!User(json);
    deserialized.name.shouldEqual("Eve");
    deserialized.scores.shouldEqual([95, 87, 92]);
}

// Test 6: Malformed JSON throws exception
@("invalid JSON throws ParseException")
unittest  
{
    struct User {
        string name;
        int age;
    }
    
    string badJson = `{invalid json}`;
    
    fromJSON!User(badJson).shouldThrow!ParseException;
}
