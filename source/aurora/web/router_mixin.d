/**
 * RouterMixin Template
 *
 * Package: aurora.web.router_mixin
 *
 * Features:
 * - Auto-creates router with prefix
 * - Auto-registers routes from module using UDAs
 * - Simplifies module-based routing
 */
module aurora.web.router_mixin;

import aurora.web.router;
import aurora.web.decorators;
import aurora.web.context;

/**
 * RouterMixin - Template for auto-registration
 *
 * Creates a module-level router and auto-registers handlers
 * decorated with @Get, @Post, @Put, @Delete, @Patch.
 *
 * Usage:
 *   @Get("/")
 *   void listUsers(Context ctx) { ... }
 *
 *   mixin RouterMixin!("/users");
 */
template RouterMixin(string prefix)
{
    // Global router for this module
    static Router router;
    
    // Module constructor (runs at startup)
    static this()
    {
        router = new Router(prefix);
        // autoRegister is now a method template in Router class
        router.autoRegister!(__MODULE__);
    }
}
