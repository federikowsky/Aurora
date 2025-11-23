/**
 * Schema Validation Exceptions
 */
module aurora.schema.exceptions;

/**
 * Thrown when validation fails
 */
class ValidationException : Exception
{
    string field;  /// Field that failed validation
    string constraint;  /// Constraint that was violated
    
    this(string msg, string field = "", string constraint = "",
         string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        this.field = field;
        this.constraint = constraint;
    }
}

/**
 * Thrown when JSON parsing fails
 */
class ParseException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }
}
