using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using nscreg.Data;
using nscreg.Data.Entities;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Services
{
    public class ReportService
    {
        private readonly NSCRegDbContext _ctx;

        public ReportService(NSCRegDbContext context)
        {
            _ctx = context;
        }

        public async Task<List<ReportTree>> GetReportTree(string sqlwalletUser)
        {
            var queryResult = await _ctx.ReportTree.FromSql("GetReportTree @p0", sqlwalletUser).ToListAsync();
            var resultNodes = new List<ReportTree>(queryResult);
            RemoveEmptyFolders(queryResult, resultNodes);

            var result = XXX();

            var host = "http://localhost:888";

            foreach (var node in resultNodes)
            {
                if (node.Type == "Report")
                    //node.ReportUrl =$"{host}/embed/{node.Id}?access_token={result}#{node.Id}";
                    node.ReportUrl = $"http://chiganockpc:888/run/226?access_token={result}";
            }

            return resultNodes; 
        }

        private static void RemoveEmptyFolders(ICollection<ReportTree> nodes, ICollection<ReportTree> resultNodes)
        {
            if (nodes == null || nodes.Count == 0)
                return;
            foreach (var reportTreeNode in nodes)
            {
                var childNodes = resultNodes.Where(x => x.ParentNodeId == reportTreeNode.Id).Select(x => x).ToList();
                RemoveEmptyFolders(childNodes, resultNodes);
                if (resultNodes.All(x => x.ParentNodeId != reportTreeNode.Id) && (reportTreeNode.ReportId == null && reportTreeNode.ParentNodeId != null))
                    resultNodes.Remove(reportTreeNode);
            }
        }

        private string XXX()
        {
            var authResponse = new SqlWalletResponse();

            var client = new HttpClient();

            var request = new HttpRequestMessage(HttpMethod.Post, "http://CHIGANOCKPC:888/connect/token")
            {
                Content = new StringContent("client_secret=secret&grant_type=client_credentials&client_id=sqlwallet&scope=sqlwallet",
                    Encoding.UTF8,
                    "application/x-www-form-urlencoded")
            };

            client.SendAsync(request).ContinueWith(responseTask =>
            {
                var content = responseTask.Result.Content.ReadAsStringAsync().Result;

                authResponse = JsonConvert.DeserializeObject<SqlWalletResponse>(content);
            }).Wait();


            var userRequest =
                new HttpRequestMessage(HttpMethod.Post, "http://CHIGANOCKPC:888/auth/accesstoken/admin")
                {
                    Content = new StringContent("",
                        Encoding.UTF8,
                        "application/json")
                };

            userRequest.Headers.Authorization = new AuthenticationHeaderValue(authResponse.Token_Type, authResponse.Access_Token);
            userRequest.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
            userRequest.Headers.Host = "CHIGANOCKPC:888";

            var accessToken = "";
            client.SendAsync(userRequest).ContinueWith(respTask =>
            {
                Debug.WriteLine($"http://chiganockpc:888/run/226?access_token={respTask.Result.Content.ReadAsStringAsync().Result}");
                //accessToken = respTask.Result.Content.ReadAsStringAsync().Result;
                //Debug.WriteLine(accessToken);
            }).Wait();

            return accessToken;

        }

        internal class SqlWalletResponse
        {
            public string Access_Token { get; set; }
            public string Expires_In { get; set; }
            public string Token_Type { get; set; }

        }
    }
}
