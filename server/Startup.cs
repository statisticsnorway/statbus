using System;
using System.IO;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.AspNetCore.Http;
using Server.Data;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Authorization;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Identity;
// ReSharper disable UnusedMember.Global

namespace Server
{
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appsettings.json", true, true)
                .AddJsonFile($"appsettings.{env.EnvironmentName}.json", true);

            if (env.IsDevelopment()) builder.AddUserSecrets();

            builder.AddEnvironmentVariables();

            Configuration = builder.Build();
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddAntiforgery(options => options.CookieName = options.HeaderName = "X-XSRF-TOKEN");
            services.AddDbContext<DatabaseContext>(
                // TODO: check environment name here
                //op => op.UseNpgsql(Configuration.GetConnectionString("DefaultConnection")));
                op => op.UseInMemoryDatabase());

            services.AddIdentity<User, Role>(op =>
            {
                op.Password.RequiredLength = 6;
                op.Password.RequireDigit = false;
                op.Password.RequireNonAlphanumeric = false;
                op.Password.RequireLowercase = false;
                op.Password.RequireUppercase = false;

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
                    }
                };
            })
                .AddEntityFrameworkStores<DatabaseContext>()
                .AddDefaultTokenProviders();

            var defaultPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build();

            services.AddMvcCore(setup =>
            {
                setup.Filters.Add(new AuthorizeFilter(defaultPolicy));
            })
                .AddAuthorization()
                .AddJsonFormatters()
                .AddRazorViewEngine()
                .AddViews();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory,
            DatabaseContext db, UserManager<User> userManager)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"));
            loggerFactory.AddDebug();

            app.UseStaticFiles();

            if (env.IsDevelopment())
            {
                SeedData(db, userManager);
                app.UseDeveloperExceptionPage();
            }
            else
                app.UseExceptionHandler(new ExceptionHandlerOptions
                {ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")});

            app.UseIdentity();

            app.UseMvc(routes => routes.MapRoute("default", "{*url}", new {controller = "Home", action = "Index"}));
        }

        public static void Main()
        {
            var host = new WebHostBuilder()
                .UseKestrel()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .UseIISIntegration()
                .UseStartup<Startup>()
                .Build();

            host.Run();
        }

        private static void SeedData(DatabaseContext db, UserManager<User> userManager)
        {
            if (db.Roles.Any()) return;
            var role = Role.Create(DefaultRoleNames.SystemAdministrator, "System administrator role");
            db.Roles.Add(role);
            db.SaveChanges();
            var user = User.Create("admin");
            user.Name = "admin";
            user.PhoneNumber = "555123456";
            user.Email = "admin@email.xyz";
            user.Status = UserStatuses.Active;
            var createUserResult = userManager.CreateAsync(user, "123qwe").Result;
            if (!createUserResult.Succeeded)
                throw new Exception(
                    $"Can't seed the database - create user: {createUserResult.Errors.Select(err => $"{err.Code}: {err.Description}\n")}");
            var assignRoleResult = userManager.AddToRoleAsync(user, role.Name).Result;
            if (!assignRoleResult.Succeeded)
                throw new Exception(
                    $"Can't seed the database - assign role: {assignRoleResult.Errors.Select(err => $"{err.Code}: {err.Description}\n")}");
        }
    }
}
