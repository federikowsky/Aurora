/**
 * Schema Validation Middleware
 *
 * Package: aurora.web.middleware.validation
 *
 * Features:
 * - Request body validation using Schema system
 * - Returns 400 on validation error
 * - Supports JSON
 * - Custom error messages
 * - Stores validated data in context
 */
module aurora.web.middleware.validation;

import aurora.web.middleware;
import aurora.web.context;
import aurora.http;
// TODO: Complete schema implementation
// import aurora.core.schema;

/**
 * ValidationMiddleware - Schema-based request validation
 */
class ValidationMiddleware(Schema)
{
    string errorMessage = "Validation failed";
    
    /**
     * Handle request (middleware interface)
     */
    void handle(Context ctx, NextFunction next)
    {
        try
        {
            // Parse request body as JSON
            auto bodyStr = cast(string)ctx.request.body;
            
            // Handle empty body
            if (bodyStr.length == 0)
            {
                sendValidationError(ctx, "Request body is empty");
                return;
            }
            
            // Parse JSON
            import std.json : parseJSON, JSONException;
            auto jsonData = parseJSON(bodyStr);
            
            // Validate against schema
            Schema validated = validateJSON!Schema(jsonData);
            
            // Store validated data in context
            ctx.storage.set("validated", validated);
            
            // Call next middleware/handler
            next();
        }
        catch (JSONException e)
        {
            sendValidationError(ctx, "Invalid JSON: " ~ e.msg);
        }
        catch (ValidationException e)
        {
            sendValidationError(ctx, e.msg);
        }
        catch (Exception e)
        {
            sendValidationError(ctx, errorMessage ~ ": " ~ e.msg);
        }
    }
    
    private:
    
    /**
     * Send validation error response
     */
    void sendValidationError(Context ctx, string message)
    {
        if (!ctx.response) return;
        
        ctx.response.setStatus(400);
        
        // Create JSON error response
        import std.format : format;
        string errorJson = format(`{"error":"%s","status":400}`, message);
        ctx.response.body = cast(ubyte[])errorJson;
        ctx.response.setHeader("Content-Type", "application/json");
    }
}

/**
 * ValidationException - Thrown when validation fails
 */
class ValidationException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}

/**
 * Validate JSON against schema
 */
Schema validateJSON(Schema)(ref const std.json.JSONValue json)
{
    import std.json : JSONType;
    import std.traits : Fields, FieldNameTuple;
    import std.conv : to;
    
    Schema result;
    
    // Validate object type
    if (json.type != JSONType.object)
    {
        throw new ValidationException("Expected object, got " ~ json.type.to!string);
    }
    
    // Validate each field
    static foreach (i, Field; Fields!Schema)
    {
        {
            enum fieldName = FieldNameTuple!Schema[i];
            
            // Check if field exists in JSON
            if (fieldName !in json.object)
            {
                // Check if field has default value
                static if (__traits(compiles, Schema.init.tupleof[i]))
                {
                    // Use default value
                    result.tupleof[i] = Schema.init.tupleof[i];
                }
                else
                {
                    throw new ValidationException("Missing required field: " ~ fieldName);
                }
            }
            else
            {
                // Extract and validate field value
                auto jsonField = json.object[fieldName];
                
                static if (is(Field == string))
                {
                    if (jsonField.type != JSONType.string)
                    {
                        throw new ValidationException("Field '" ~ fieldName ~ "' must be string");
                    }
                    result.tupleof[i] = jsonField.str;
                }
                else static if (is(Field == int) || is(Field == long))
                {
                    if (jsonField.type != JSONType.integer)
                    {
                        throw new ValidationException("Field '" ~ fieldName ~ "' must be integer");
                    }
                    result.tupleof[i] = cast(Field)jsonField.integer;
                }
                else static if (is(Field == bool))
                {
                    if (jsonField.type == JSONType.true_)
                    {
                        result.tupleof[i] = true;
                    }
                    else if (jsonField.type == JSONType.false_)
                    {
                        result.tupleof[i] = false;
                    }
                    else
                    {
                        throw new ValidationException("Field '" ~ fieldName ~ "' must be boolean");
                    }
                }
                else static if (is(Field == struct))
                {
                    // Nested struct
                    result.tupleof[i] = validateJSON!Field(jsonField);
                }
                else static if (is(Field == string[]))
                {
                    // Array of strings
                    if (jsonField.type != JSONType.array)
                    {
                        throw new ValidationException("Field '" ~ fieldName ~ "' must be array");
                    }
                    string[] arr;
                    foreach (elem; jsonField.array)
                    {
                        if (elem.type != JSONType.string)
                        {
                            throw new ValidationException("Array elements must be strings");
                        }
                        arr ~= elem.str;
                    }
                    result.tupleof[i] = arr;
                }
                else
                {
                    // Unsupported type
                    throw new ValidationException("Unsupported field type: " ~ Field.stringof);
                }
            }
        }
    }
    
    return result;
}

/**
 * Helper function to create validation middleware
 */
Middleware validateRequest(Schema)()
{
    auto validator = new ValidationMiddleware!Schema();
    
    return (ref Context ctx, NextFunction next) {
        validator.handle(ctx, next);
    };
}
