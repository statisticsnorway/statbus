using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using nscreg.Data.Entities;
using nscreg.Server.Common.Models;
using nscreg.Server.Common.Models.StatUnits;

namespace nscreg.Server.Common.Services.StatUnit
{
    public interface IElasticUpsertService
    {
        Task EditDocument(ElasticStatUnit elasticItem);
        Task DeleteDocumentAsync(ElasticStatUnit elasticItem);
        Task AddDocument(ElasticStatUnit elasticItem);
        Task CheckElasticSearchConnection();
    }
}
