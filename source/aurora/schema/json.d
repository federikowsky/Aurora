/**
 * Schema JSON Serialization
 */
module aurora.schema.json;

import aurora.schema.exceptions;
import std.json;
import std.traits;
import std.conv : to;

/**
 * Serialize struct to JSON string
 */
string toJSON(T)(ref T value)
{
    JSONValue json = toJSONValue(value);
    return json.toString();
}

/**
 * Deserialize JSON string to struct
 */
T fromJSON(T)(string jsonString)
{
    try
    {
        JSONValue json = parseJSON(jsonString);
        return fromJSONValue!T(json);
    }
    catch (Exception e)
    {
        throw new ParseException("Failed to parse JSON: " ~ e.msg);
    }
}

// Internal helpers

private JSONValue toJSONValue(T)(ref T value)
{
    static if (is(T == struct))
    {
        JSONValue[string] jsonObj;
        
        static foreach (fieldName; __traits(allMembers, T))
        {{
            static if (__traits(compiles, __traits(getMember, value, fieldName)) &&
                       !isFunction!(__traits(getMember, T, fieldName)))
            {
                auto fieldValue = __traits(getMember, value, fieldName);
                jsonObj[fieldName] = toJSONValue(fieldValue);
            }
        }}
        
        return JSONValue(jsonObj);
    }
    else static if (is(T == string))
    {
        return JSONValue(value);
    }
    else static if (isNumeric!T)
    {
        return JSONValue(value);
    }
    else static if (is(T == bool))
    {
        return JSONValue(value);
    }
    else static if (isArray!T && !is(T == string))
    {
        JSONValue[] arr;
        foreach (item; value)
        {
            arr ~= toJSONValue(item);
        }
        return JSONValue(arr);
    }
    else
    {
        static assert(false, "Unsupported type for JSON serialization: " ~ T.stringof);
    }
}

private T fromJSONValue(T)(JSONValue json)
{
    static if (is(T == struct))
    {
        T result;
        
        static foreach (fieldName; __traits(allMembers, T))
        {{
            static if (__traits(compiles, __traits(getMember, result, fieldName)) &&
                       !isFunction!(__traits(getMember, T, fieldName)))
            {
                alias FieldType = typeof(__traits(getMember, T, fieldName));
                
                if (fieldName in json)
                {
                    __traits(getMember, result, fieldName) = 
                        fromJSONValue!FieldType(json[fieldName]);
                }
            }
        }}
        
        return result;
    }
    else static if (is(T == string))
    {
        return json.str;
    }
    else static if (is(T == int))
    {
        return cast(int)json.integer;
    }
    else static if (is(T == long))
    {
        return json.integer;
    }
    else static if (is(T == bool))
    {
        return json.boolean;
    }
    else static if (isArray!T && !is(T == string))
    {
        alias ElementType = typeof(T.init[0]);
        T result;
        
        foreach (item; json.array)
        {
            result ~= fromJSONValue!ElementType(item);
        }
        
        return result;
    }
    else
    {
        static assert(false, "Unsupported type for JSON deserialization: " ~ T.stringof);
    }
}
