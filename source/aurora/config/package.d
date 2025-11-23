/**
 * Aurora Configuration System
 * 
 * Features:
 * - Load from JSON/ENV
 * - Type-safe access
 * - Nested keys (dot notation)
 * - Defaults
 * - Validation
 * 
 * Usage:
 * ---
 * auto config = Config.fromFile("config.json");
 * auto port = config.get!int("server.port", 8080);
 * ---
 */
module aurora.config;

import std.json;
import std.file : readText;
import std.conv : to;
import std.string : split, strip;
import std.process : environment;
import std.algorithm : startsWith;

/**
 * Configuration manager
 */
class Config
{
    private JSONValue data;
    
    /**
     * Create empty config
     */
    this()
    {
        data = JSONValue.emptyObject;
    }
    
    /**
     * Load from JSON string
     */
    static Config fromJSON(string json)
    {
        auto config = new Config();
        config.data = parseJSON(json);
        return config;
    }
    
    /**
     * Load from JSON file
     */
    static Config fromFile(string path)
    {
        auto content = readText(path);
        return fromJSON(content);
    }
    
    /**
     * Load from environment variables
     * 
     * Params:
     *   prefix = Environment variable prefix (e.g., "APP_")
     */
    static Config fromEnv(string prefix = "")
    {
        auto config = new Config();
        
        foreach (key, value; environment.toAA())
        {
            if (prefix.length == 0 || key.startsWith(prefix))
            {
                auto configKey = prefix.length > 0 ? key[prefix.length .. $] : key;
                config.setString(configKey, value);
            }
        }
        
        return config;
    }
    
    /**
     * Load environment variables and override existing config
     */
    void loadEnv(string prefix = "")
    {
        import std.uni : toLower;
        
        foreach (key, value; environment.toAA())
        {
            if (prefix.length == 0 || key.startsWith(prefix))
            {
                auto configKey = prefix.length > 0 ? key[prefix.length .. $] : key;
                configKey = configKey.toLower();  // Norm to lowercase
                
                // Set value (parse types automatically)
                setString(configKey, value);
            }
        }
    }
    
    /**
     * Get value with type conversion
     */
    T get(T)(string key, T defaultValue = T.init)
    {
        auto value = getValueByPath(key);
        
        if (value.isNull || value.type == JSONType.null_)
        {
            return defaultValue;
        }
        
        static if (is(T == string))
        {
            return value.str;
        }
        else static if (is(T == int))
        {
            if (value.type == JSONType.integer)
                return cast(int)value.integer;
            else if (value.type == JSONType.string)
                return to!int(value.str);
            else
                return defaultValue;
        }
        else static if (is(T == long))
        {
            return value.integer;
        }
        else static if (is(T == bool))
        {
            if (value.type == JSONType.true_)
                return true;
            else if (value.type == JSONType.false_)
                return false;
            else
                return defaultValue;
        }
        else static if (is(T == double))
        {
            if (value.type == JSONType.float_)
                return value.floating;
            else if (value.type == JSONType.integer)
                return cast(double)value.integer;
            else
                return defaultValue;
        }
        else
        {
            return defaultValue;
        }
    }
    
    /**
     * Set value
     */
    void set(T)(string key, T value)
    {
        setValueByPath(key, JSONValue(value));
    }
    
    /**
     * Validate required keys exist
     */
    bool validate(string[] requiredKeys)
    {
        foreach (key; requiredKeys)
        {
            auto value = getValueByPath(key);
            if (value.isNull || value.type == JSONType.null_)
            {
                return false;
            }
        }
        return true;
    }
    
    // Private helpers
    
    private JSONValue getValueByPath(string path)
    {
        auto parts = path.split(".");
        JSONValue current = data;
        
        foreach (part; parts)
        {
            if (current.type != JSONType.object)
                return JSONValue(null);
            
            if (part !in current.object)
                return JSONValue(null);
            
            current = current.object[part];
        }
        
        return current;
    }
    
    private void setValueByPath(string path, JSONValue value)
    {
        auto parts = path.split(".");
        
        if (parts.length == 1)
        {
            data.object[parts[0]] = value;
            return;
        }
        
        JSONValue* current = &data;
        
        foreach (i, part; parts[0 .. $ - 1])
        {
            if (current.type != JSONType.object)
            {
                *current = JSONValue.emptyObject;
            }
            
            if (part !in current.object)
            {
                current.object[part] = JSONValue.emptyObject;
            }
            
            current = &current.object[part];
        }
        
        if (current.type != JSONType.object)
        {
            *current = JSONValue.emptyObject;
        }
        
        current.object[parts[$ - 1]] = value;
    }
    
    private void setString(string key, string value)
    {
        // Try to parse as number or bool
        try
        {
            auto intVal = to!int(value);
            setValueByPath(key, JSONValue(intVal));
            return;
        }
        catch (Exception) {}
        
        if (value == "true")
        {
            setValueByPath(key, JSONValue(true));
            return;
        }
        else if (value == "false")
        {
            setValueByPath(key, JSONValue(false));
            return;
        }
        
        setValueByPath(key, JSONValue(value));
    }
}
