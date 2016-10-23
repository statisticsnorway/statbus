using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Server.Models;

namespace Server
{
    public class Startup
    {
        public void ConfigureServices(IServiceCollection services)
        {
            // TODO: move to config file
            var connection = @"Server=127.0.0.1;Port=5432;Database=nscreg;User Id=postgres;Password=1";
            services
                .AddEntityFrameworkNpgsql()
                .AddDbContext<DatabaseContext>(op => op.UseNpgsql(connection));
        }

        public void Configure(IApplicationBuilder app)
        {
            app.Run(async ctx => { await ctx.Response.WriteAsync("Hey!")});
        }
    }
}
