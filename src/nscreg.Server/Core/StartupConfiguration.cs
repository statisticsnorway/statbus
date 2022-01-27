using System;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using nscreg.Server.Common;

namespace nscreg.Server.Core
{
    /// <summary>
    /// Application Launch Configuration Class
    /// </summary>
    public static class StartupConfiguration
    {
        /// <summary>
        /// Identity Configuration Method
        /// </summary>
        public static readonly Action<IdentityOptions> ConfigureIdentity =
            op =>
            {
                op.Password.RequiredLength = 6;
                op.Password.RequireDigit = false;
                op.Password.RequireNonAlphanumeric = false;
                op.Password.RequireLowercase = false;
                op.Password.RequireUppercase = false;
/*
                op.Cookies.ApplicationCookie.CookieHttpOnly = true;
                op.Cookies.ApplicationCookie.ExpireTimeSpan = TimeSpan.FromDays(7);
                op.Cookies.ApplicationCookie.LoginPath = "/account/login";
                op.Cookies.ApplicationCookie.LogoutPath = "/account/logout";
                op.Cookies.ApplicationCookie.Events = new CookieAuthenticationEvents
                {
                    OnRedirectToLogin = ctx =>
                    {
                        if (ctx.Request.Path.StartsWithSegments("/api") && ctx.Response.StatusCode == 200)
                            ctx.Response.StatusCode = 401;
                        else
                            ctx.Response.Redirect(ctx.RedirectUri);
                        return Task.FromResult(0);
                    },
                    OnRedirectToAccessDenied = ctx =>
                    {
                        if (ctx.Request.Path.StartsWithSegments("/api") && ctx.Response.StatusCode == 200)
                            ctx.Response.StatusCode = 403;
                        else
                            ctx.Response.Redirect(ctx.RedirectUri);
                        return Task.FromResult(0);
                    }
                };*/
            };
        private static object _thisLock = new object();
        private static bool _initialized = false;
        /// <summary>
        /// AutoMapper Configuration Method
        /// </summary>
        public static void ConfigureAutoMapper(IServiceCollection services)
        {
            lock (_thisLock)
            {
                if (!_initialized)
                {
                    services.AddAutoMapper(c => c.AddProfile<AutoMapperProfile>(), typeof(Startup));
                    _initialized = true;
                }
            }
        }
    }
}
