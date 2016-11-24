using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using nscreg.Data;
using nscreg.Data.Constants;
using nscreg.Data.Entities;
using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
// ReSharper disable UnusedMember.Global

namespace nscreg.Server
{
    public class Startup
    {
        private IConfiguration Configuration { get; }

        public Startup(IHostingEnvironment env)
        {
            var builder = new ConfigurationBuilder()
                .SetBasePath(env.ContentRootPath)
                .AddJsonFile("appSettings.json", true, true)
                .AddJsonFile($"appSettings.{env.EnvironmentName}.json", true);

            if (env.IsDevelopment()) builder.AddUserSecrets();

            builder.AddEnvironmentVariables();

            Configuration = builder.Build();
        }

        public void ConfigureServices(IServiceCollection services)
        {
            services.AddAntiforgery(options => options.CookieName = options.HeaderName = "X-XSRF-TOKEN");
            services.AddDbContext<NSCRegDbContext>(op =>
                op.UseNpgsql(Configuration.GetConnectionString("DefaultConnection")));
                //op.UseInMemoryDatabase());

            services.AddIdentity<User, Role>(ConfigureIdentity)
                .AddEntityFrameworkStores<NSCRegDbContext>()
                .AddDefaultTokenProviders();

            services.AddMvcCore(op =>
            {
                op.Filters.Add(new AuthorizeFilter(
                    new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build()));
            })
                .AddAuthorization()
                .AddJsonFormatters()
                .AddRazorViewEngine()
                .AddViews();
        }

        public void Configure(IApplicationBuilder app, IHostingEnvironment env, ILoggerFactory loggerFactory,
            NSCRegDbContext db, UserManager<User> userManager)
        {
            loggerFactory.AddConsole(Configuration.GetSection("Logging"))
                .AddDebug();

            app.UseStaticFiles();

            if (env.IsDevelopment())
            {
                SeedData(db, userManager);
                app.UseDeveloperExceptionPage();
            }
            else app.UseExceptionHandler(new ExceptionHandlerOptions
            {
                ExceptionHandler = async ctx => await ctx.Response.WriteAsync("Oops!")
            });

            app.UseIdentity()
                .UseMvc(routes =>
                    routes.MapRoute("default", "{*url}", new { controller = "Home", action = "Index" }));
        }

        public static void Main()
        {
            new WebHostBuilder()
                .UseKestrel()
                .UseContentRoot(Directory.GetCurrentDirectory())
                .UseIISIntegration()
                .UseStartup<Startup>()
                .Build()
                .Run();
        }

        private Action<IdentityOptions> ConfigureIdentity = op =>
        {
            // password settings
            op.Password.RequiredLength = 6;
            op.Password.RequireDigit = false;
            op.Password.RequireNonAlphanumeric = false;
            op.Password.RequireLowercase = false;
            op.Password.RequireUppercase = false;
            // auth settings
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
        };

        private void SeedData(NSCRegDbContext db, UserManager<User> userManager)
        {
            if (db.Roles.Any()) return;
            var role = new Role
            {
                Name = DefaultRoleNames.SystemAdministrator,
                Description = "System administrator role",
                NormalizedName = DefaultRoleNames.SystemAdministrator.ToUpper(),
                AccessToSystemFunctionsArray = new[] { (int)SystemFunction.AddUser },
                StandardDataAccessArray = new[] { 1, 2 },
            };
            db.Roles.Add(role);
            db.SaveChanges();
            var user = new User
            {
                Login = "admin",
                Name = "adminName",
                PhoneNumber = "555123456",
                Email = "admin@email.xyz",
                Status = UserStatuses.Active,
                Description = "System administrator account",
                NormalizedUserName = "admin".ToUpper(),
                DataAccessArray = new[] { 1, 2 },
            };
            var createResult = userManager.CreateAsync(user, "123qwe").Result;
            if (!createResult.Succeeded)
                throw new Exception($"Error while creating admin user.{createResult.Errors.Select(err => $" {err.Code} {err.Description}")}");
            db.UserRoles.Add(new IdentityUserRole<string> { UserId = user.Id, RoleId = role.Id });
            db.SaveChanges();
        }
    }
}
