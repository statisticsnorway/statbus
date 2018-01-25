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
using nscreg.Utilities.Configuration;
using Newtonsoft.Json;

namespace nscreg.Server.Common.Services
{
    public class ReportService
    {
        private readonly NSCRegDbContext _ctx;
        private readonly ReportingSettings _settings;

        public ReportService(NSCRegDbContext context, ReportingSettings settings)
        {
            _ctx = context;
            _settings = settings;
        }

        public async Task<List<ReportTree>> GetReportsTree()
        {
            var queryResult = await _ctx.ReportTree.FromSql("GetReportsTree @p0", _settings.NscUserName).ToListAsync();
            var resultNodes = new List<ReportTree>(queryResult);
            RemoveEmptyFolders(queryResult, resultNodes);

            var result = GetAccessToken(_settings);

            foreach (var node in resultNodes)
            {
                if (node.Type == "Report")
                    node.ReportUrl = $"http://{_settings.HostName}/run/{node.ReportId}?access_token={result}";
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

        private string GetAccessToken(ReportingSettings settings)
        {
            var authResponse = new SqlWalletResponse();

            var client = new HttpClient();

            var request = new HttpRequestMessage(HttpMethod.Post, $"http://{settings.HostName}/connect/token")
            {
                Content = new StringContent($"client_secret={settings.SecretKey}&grant_type=client_credentials&client_id=sqlwallet&scope=sqlwallet",
                    Encoding.UTF8,
                    "application/x-www-form-urlencoded")
            };

            request.Headers.ExpectContinue = true;

            client.SendAsync(request).ContinueWith(responseTask =>
            {
                var content = responseTask.Result.Content.ReadAsStringAsync().Result;

                authResponse = JsonConvert.DeserializeObject<SqlWalletResponse>(content);
            }).Wait();


            var userRequest =
                new HttpRequestMessage(HttpMethod.Post, $"http://{settings.HostName}/auth/accesstoken/{settings.NscUserName}")
                {
                    Content = new StringContent("", Encoding.UTF8, "application/json")
                };

            userRequest.Headers.Authorization = new AuthenticationHeaderValue(authResponse.Token_Type, authResponse.Access_Token);
            userRequest.Headers.CacheControl = new CacheControlHeaderValue { NoCache = true };
            userRequest.Headers.Host = settings.HostName;

            var accessToken = "";
            client.SendAsync(userRequest).ContinueWith(respTask =>
            {
                accessToken = respTask.Result.Content.ReadAsStringAsync().Result;
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
