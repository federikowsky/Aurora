/**
 * Form Data Parsing — Production-Grade Implementation
 *
 * Package: aurora.http.form
 *
 * Parses application/x-www-form-urlencoded data with:
 * - URL decoding with security defaults
 * - Multi-value field support
 * - @nogc raw field lookup
 *
 * Note: multipart/form-data is not yet supported (v2 feature).
 */
module aurora.http.form;

import aurora.http.url : urlDecode, formDecode, DecodeOptions;

// ════════════════════════════════════════════════════════════════════════════
// PUBLIC API
// ════════════════════════════════════════════════════════════════════════════

/**
 * Get a form field value by name.
 *
 * Parses the input as application/x-www-form-urlencoded and returns
 * the URL-decoded value for the specified field.
 *
 * Params:
 *   data = Form-encoded data (e.g., "name=John&email=test%40example.com")
 *   name = Field name to find
 *   defaultValue = Value to return if field not found
 *
 * Returns:
 *   URL-decoded field value, or defaultValue if not found
 *
 * Example:
 * ---
 * auto body = "email=test%40example.com&password=secret";
 * assert(getFormField(body, "email") == "test@example.com");
 * assert(getFormField(body, "missing", "default") == "default");
 * ---
 */
string getFormField(const(char)[] data, const(char)[] name, string defaultValue = "") pure @trusted
{
    auto raw = findFieldValue(data, name);
    if (raw is null)
        return defaultValue;
    
    return formDecode(raw);
}

/**
 * Get all values for a form field (multi-value support).
 *
 * Params:
 *   data = Form-encoded data
 *   name = Field name to find
 *
 * Returns:
 *   Array of URL-decoded values, empty if field not found
 *
 * Example:
 * ---
 * auto body = "tag=red&tag=blue&tag=green";
 * assert(getFormFieldAll(body, "tag") == ["red", "blue", "green"]);
 * ---
 */
string[] getFormFieldAll(const(char)[] data, const(char)[] name) pure @trusted
{
    string[] results;
    
    size_t pos = 0;
    while (pos < data.length)
    {
        // Find key end
        size_t keyEnd = pos;
        while (keyEnd < data.length && data[keyEnd] != '=' && data[keyEnd] != '&')
            keyEnd++;
        
        immutable keyLen = keyEnd - pos;
        
        // Check if key matches
        if (keyLen == name.length && keysMatch(data[pos .. keyEnd], name))
        {
            if (keyEnd < data.length && data[keyEnd] == '=')
            {
                // Extract value
                size_t valStart = keyEnd + 1;
                size_t valEnd = valStart;
                while (valEnd < data.length && data[valEnd] != '&')
                    valEnd++;
                
                results ~= formDecode(data[valStart .. valEnd]);
            }
            else
            {
                // Key without value
                results ~= "";
            }
        }
        
        // Skip to next pair
        while (pos < data.length && data[pos] != '&')
            pos++;
        pos++;  // Skip '&'
    }
    
    return results;
}

/**
 * Get raw field value without URL decoding.
 *
 * Zero-copy, @nogc. For performance-critical code.
 * WARNING: Returns slice into input buffer.
 *
 * Params:
 *   data = Form-encoded data
 *   name = Field name to find
 *
 * Returns:
 *   Raw field value slice, or null if not found
 */
pragma(inline, true)
const(char)[] findFieldValue(const(char)[] data, const(char)[] name) pure nothrow @nogc @trusted
{
    if (data.length == 0 || name.length == 0)
        return null;
    
    size_t pos = 0;
    
    while (pos < data.length)
    {
        // Find key end
        size_t keyEnd = pos;
        while (keyEnd < data.length && data[keyEnd] != '=' && data[keyEnd] != '&')
            keyEnd++;
        
        immutable keyLen = keyEnd - pos;
        
        // Check if key matches
        if (keyLen == name.length && keysMatch(data[pos .. keyEnd], name))
        {
            if (keyEnd < data.length && data[keyEnd] == '=')
            {
                // Extract value
                size_t valStart = keyEnd + 1;
                size_t valEnd = valStart;
                while (valEnd < data.length && data[valEnd] != '&')
                    valEnd++;
                
                return data[valStart .. valEnd];
            }
            else
            {
                // Key without value
                return "";
            }
        }
        
        // Skip to next pair
        while (pos < data.length && data[pos] != '&')
            pos++;
        pos++;  // Skip '&'
    }
    
    return null;
}

/**
 * Check if form field exists.
 */
pragma(inline, true)
bool hasFormField(const(char)[] data, const(char)[] name) pure nothrow @nogc @trusted
{
    return findFieldValue(data, name) !is null;
}

/**
 * Parse all form fields into an associative array.
 *
 * Note: For duplicate keys, only the first value is kept.
 * Use getFormFieldAll() for multi-value fields.
 *
 * Params:
 *   data = Form-encoded data
 *
 * Returns:
 *   Associative array of field name to decoded value
 */
string[string] parseFormData(const(char)[] data) pure @trusted
{
    string[string] result;
    
    size_t pos = 0;
    while (pos < data.length)
    {
        // Find key end
        size_t keyEnd = pos;
        while (keyEnd < data.length && data[keyEnd] != '=' && data[keyEnd] != '&')
            keyEnd++;
        
        if (keyEnd > pos)
        {
            string key = formDecode(data[pos .. keyEnd]);
            
            if (keyEnd < data.length && data[keyEnd] == '=')
            {
                size_t valStart = keyEnd + 1;
                size_t valEnd = valStart;
                while (valEnd < data.length && data[valEnd] != '&')
                    valEnd++;
                
                // Only set if key not already present (first value wins)
                if (key !in result)
                    result[key] = formDecode(data[valStart .. valEnd]);
                
                pos = valEnd;
            }
            else
            {
                if (key !in result)
                    result[key] = "";
                pos = keyEnd;
            }
        }
        
        // Skip '&'
        while (pos < data.length && data[pos] != '&')
            pos++;
        pos++;
    }
    
    return result;
}

/**
 * Streaming form parser (zero intermediate allocations)
 *
 * Parses form data in a single pass calling a callback for each field.
 * No intermediate arrays or associative arrays are allocated.
 *
 * Params:
 *   data = Form-encoded data (e.g., "name=John&email=test%40example.com")
 *   callback = Called for each key-value pair (values are URL-encoded)
 *              Callback receives slices into the input buffer
 *
 * Example:
 * ---
 * parseFormStreaming("a=1&b=2", (key, value) {
 *     writeln(key, " = ", formDecode(value));
 * });
 * ---
 */
void parseFormStreaming(
    const(char)[] data,
    scope void delegate(const(char)[] key, const(char)[] value) nothrow callback
) nothrow @trusted
{
    if (data.length == 0)
        return;

    size_t pos = 0;

    // Single-pass parsing
    while (pos < data.length)
    {
        // Find key end
        size_t keyEnd = pos;
        while (keyEnd < data.length && data[keyEnd] != '=' && data[keyEnd] != '&')
            keyEnd++;

        if (keyEnd > pos)
        {
            const(char)[] key = data[pos .. keyEnd];

            if (keyEnd < data.length && data[keyEnd] == '=')
            {
                // Extract value
                size_t valStart = keyEnd + 1;
                size_t valEnd = valStart;
                while (valEnd < data.length && data[valEnd] != '&')
                    valEnd++;

                const(char)[] value = data[valStart .. valEnd];

                // Invoke callback with raw (still encoded) key and value
                callback(key, value);

                pos = valEnd;
            }
            else
            {
                // Key without value
                callback(key, "");
                pos = keyEnd;
            }
        }

        // Skip '&'
        if (pos < data.length && data[pos] == '&')
            pos++;
    }
}

// ════════════════════════════════════════════════════════════════════════════
// HELPERS
// ════════════════════════════════════════════════════════════════════════════

/**
 * Compare two key slices for equality.
 */
pragma(inline, true)
private bool keysMatch(const(char)[] a, const(char)[] b) pure nothrow @nogc @safe
{
    if (a.length != b.length) return false;
    
    for (size_t i = 0; i < a.length; i++)
    {
        if (a[i] != b[i]) return false;
    }
    
    return true;
}
