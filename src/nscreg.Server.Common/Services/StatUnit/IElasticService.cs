using System.Collections.Generic;
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
        Task<SearchVm<ElasticStatUnit>> Search(SearchQueryM filter, string userId, bool isDeleted);
        Task UpsertDocumentList(List<ElasticStatUnit> entities);
        Task DeleteDocumentRangeAsync(IEnumerable<ElasticStatUnit> enumerable);
    }
}
