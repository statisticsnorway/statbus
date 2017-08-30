using System;
using System.Threading.Tasks;
using AutoMapper;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using nscreg.Server.Common;

namespace nscreg.Server.Core
{
    public static class StartupConfiguration
    {
        public static readonly Func<IConfiguration, Action<DbContextOptionsBuilder>> ConfigureDbContext =
            config =>
                op =>
                {
                    var useInMemoryDb = config.GetValue<bool>("ConnectionSettings:UseInMemoryDatabase");
                    if (useInMemoryDb)
                        op.UseInMemoryDatabase();
                    else
                        op.UseNpgsql(config["ConnectionSettings:ConnectionString"],
                            op2 => op2.MigrationsAssembly("nscreg.Data"));
                };

        public static readonly Action<IdentityOptions> ConfigureIdentity =
            op =>
            {
                op.Password.RequiredLength = 6;
                op.Password.RequireDigit = false;
                op.Password.RequireNonAlphanumeric = false;
                op.Password.RequireLowercase = false;
                op.Password.RequireUppercase = false;

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
                            ctx.Response.StatusCode = 401;
                        else
                            ctx.Response.Redirect(ctx.RedirectUri);
                        return Task.FromResult(0);
                    }
                };
            };

        public static void ConfigureAutoMapper()
            => Mapper.Initialize(x => x.AddProfile<AutoMapperProfile>());
    }
}
