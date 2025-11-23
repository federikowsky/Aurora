/**
 * Schema System Tests
 * 
 * TDD approach: Write tests first, then implement.
 */
module tests.unit.schema.validation_test;

import unit_threaded;
import aurora.schema;

// Test 1: Simple struct validation (happy path)
@("validate simple struct with valid data")
unittest
{
    struct User {
        @Required string name;
        @Range(0, 150) int age;
    }
    
    User validUser = User("Alice", 30);
    
    // Should NOT throw
    validUser.validate();
}

// Test 2: Required field missing (error case)
@("validate detects missing required field")
unittest  
{
    struct User {
        @Required string name;
        int age;
    }
    
    User invalidUser = User("", 25);  // Empty name
    
    // Should throw ValidationException
    invalidUser.validate().shouldThrow!ValidationException;
}

// Test 3: Value out of range (error case)
@("validate detects value out of range")
unittest
{
    struct User {
        string name;
        @Range(0, 150) int age;
    }
    
    User invalidUser = User("Bob", 200);  // Age > 150
    
    // Should throw ValidationException
    invalidUser.validate().shouldThrow!ValidationException;
}

// Test 4: Multiple validations
@("validate checks all constraints")
unittest
{
    struct User {
        @Required string name;
        @Range(18, 65) int age;
        @Email string email;
    }
    
    // Valid user
    User valid = User("Carol", 35, "carol@example.com");
    valid.validate();  // Should NOT throw
    
    // Invalid: missing name
    User invalid1 = User("", 35, "carol@example.com");
    invalid1.validate().shouldThrow!ValidationException;
    
    // Invalid: age out of range
    User invalid2 = User("Carol", 70, "carol@example.com");
    invalid2.validate().shouldThrow!ValidationException;
    
    // Invalid: bad email
    User invalid3 = User("Carol", 35, "not-an-email");
    invalid3.validate().shouldThrow!ValidationException;
}

// Test 5: Optional fields with defaults
@("optional fields use defaults")
unittest
{
    struct User {
        @Required string name;
        int age = 25;  // Optional with default
        string city = "Unknown";  // Optional with default
    }
    
    User u = User("Dave");
    u.validate();  // Should pass
    
    u.age.shouldEqual(25);
    u.city.shouldEqual("Unknown");
}

// Test 6: Nested struct validation
@("validate nested structs")
unittest
{
    struct Address {
        @Required string city;
        @Range(10000, 99999) int zipCode;
    }
    
    struct User {
        @Required string name;
        @Required Address address;
    }
    
    // Valid nested
    User valid = User("Eve", Address("NYC", 10001));
    valid.validate();
    
    // Invalid: missing city
    User invalid = User("Eve", Address("", 10001));
    invalid.validate().shouldThrow!ValidationException;
}
