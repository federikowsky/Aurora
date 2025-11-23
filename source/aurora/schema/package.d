/**
 * Aurora Schema System - Main Module
 * 
 * Provides compile-time schema validation and JSON serialization.
 * Inspired by Pydantic (Python) and similar validation frameworks.
 * 
 * Features:
 * - UDA-based validation (@Required, @Range, @Email, etc.)
 * - Compile-time reflection
 * - JSON serialization/deserialization
 * - Zero-allocation validation (where possible)
 * 
 * Example:
 * ---
 * struct User {
 *     @Required string name;
 *     @Range(0, 150) int age;
 *     @Email string email;
 * }
 * 
 * User user = User("Alice", 30, "alice@example.com");
 * user.validate();  // Throws ValidationException if invalid
 * 
 * string json = user.toJSON();
 * User user2 = fromJSON!User(json);
 * ---
 */
module aurora.schema;

public import aurora.schema.validation;
public import aurora.schema.json;
public import aurora.schema.exceptions;
