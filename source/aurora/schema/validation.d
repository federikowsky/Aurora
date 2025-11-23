/**
 * Schema Validation - UDA Markers and Validation Logic
 */
module aurora.schema.validation;

import aurora.schema.exceptions;
import std.traits;
import std.conv : to;

/**
 * UDA: Field is required (cannot be null/empty)
 */
struct Required {}

/**
 * UDA: Value must be in range [min, max]
 */
struct Range
{
    long min;
    long max;
}

/**
 * UDA: Value must be >= min
 */
struct Min
{
    long value;
}

/**
 * UDA: Value must be <= max
 */
struct Max
{
    long value;
}

/**
 * UDA: String must be valid email
 */
struct Email {}

/**
 * UDA: String length must be in range
 */
struct Length
{
    size_t min;
    size_t max;
}

/**
 * Validate a struct against its schema
 * 
 * Throws: ValidationException if validation fails
 */
void validate(T)(ref T value)
{
    static foreach (fieldName; __traits(allMembers, T))
    {{
        // Filter out functions, only process fields
        static if (__traits(compiles, __traits(getMember, value, fieldName)) &&
                   !isFunction!(__traits(getMember, T, fieldName)))
        {
            auto fieldRef() { return __traits(getMember, value, fieldName); }
            alias FieldType = typeof(fieldRef());
            
            // Get UDAs for this field
            alias udas = __traits(getAttributes, __traits(getMember, T, fieldName));
            
            // Check UDAs
            static foreach (uda; udas)
            {{
                // @Required (type-based UDA)
                static if (is(uda == Required))
                {
                    validateRequired(fieldRef(), fieldName);
                }
                // @Range(...) (value-based UDA)
                else static if (is(typeof(uda) == Range))
                {
                    validateRange(fieldRef(), fieldName, uda.min, uda.max);
                }
                else static if (is(typeof(uda) == Min))
                {
                    validateMin(fieldRef(), fieldName, uda.value);
                }
                else static if (is(typeof(uda) == Max))
                {
                    validateMax(fieldRef(), fieldName, uda.value);
                }
                // @Email (type-based UDA)
                else static if (is(uda == Email))
                {
                    validateEmail(fieldRef(), fieldName);
                }
                else static if (is(typeof(uda) == Length))
                {
                    validateLength(fieldRef(), fieldName, uda.min, uda.max);
                }
            }}
            
            // Recursively validate nested structs
            static if (is(FieldType == struct))
            {
                mixin("value." ~ fieldName ~ ".validate();");
            }
        }
    }}
}

// Validation helpers

private void validateRequired(T)(T value, string fieldName)
{
    static if (is(T == string))
    {
        if (value is null || value.length == 0)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' is required",
                fieldName, "Required"
            );
    }
    else
    {
        // For other types, check default value
        if (value == T.init)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' is required",
                fieldName, "Required"
            );
    }
}

private void validateRange(T)(T value, string fieldName, long min, long max)
{
    static if (isNumeric!T)
    {
        if (value < min || value > max)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' must be in range [" ~ 
                min.to!string ~ ", " ~ max.to!string ~ "], got " ~ value.to!string,
                fieldName, "Range"
            );
    }
}

private void validateMin(T)(T value, string fieldName, long min)
{
    static if (isNumeric!T)
    {
        if (value < min)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' must be >= " ~ min.to!string ~ 
                ", got " ~ value.to!string,
                fieldName, "Min"
            );
    }
}

private void validateMax(T)(T value, string fieldName, long max)
{
    static if (isNumeric!T)
    {
        if (value > max)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' must be <= " ~ max.to!string ~ 
                ", got " ~ value.to!string,
                fieldName, "Max"
            );
    }
}

private void validateEmail(T)(T value, string fieldName)
{
    static if (is(T == string))
    {
        import std.algorithm : canFind;
        
        if (!value.canFind('@') || !value.canFind('.'))
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' must be a valid email",
                fieldName, "Email"
            );
    }
}

private void validateLength(T)(T value, string fieldName, size_t min, size_t max)
{
    static if (is(T == string))
    {
        if (value.length < min || value.length > max)
            throw new ValidationException(
                "Field '" ~ fieldName ~ "' length must be in range [" ~ 
                min.to!string ~ ", " ~ max.to!string ~ "], got " ~ value.length.to!string,
                fieldName, "Length"
            );
    }
}
