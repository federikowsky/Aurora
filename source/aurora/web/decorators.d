/**
 * UDA Decorators for Route Registration
 *
 * Package: aurora.web.decorators
 *
 * Features:
 * - @Get, @Post, @Put, @Delete, @Patch decorators
 * - Auto-registration support
 */
module aurora.web.decorators;

/**
 * @Get - GET request decorator
 */
struct Get
{
    string path;
}

/**
 * @Post - POST request decorator
 */
struct Post
{
    string path;
}

/**
 * @Put - PUT request decorator
 */
struct Put
{
    string path;
}

/**
 * @Delete - DELETE request decorator
 */
struct Delete
{
    string path;
}

/**
 * @Patch - PATCH request decorator
 */
struct Patch
{
    string path;
}
