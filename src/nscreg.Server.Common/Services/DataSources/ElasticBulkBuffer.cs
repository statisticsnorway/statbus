using System;
using System.Threading;
using System.Threading.Tasks;
using Nest;
using nscreg.Data.Entities;
using nscreg.Resources.Languages;
using nscreg.Server.Common.Services.StatUnit;

namespace nscreg.Server.Common.Services.DataSources
{
    public class ElasticBulkBuffer : IElasticUpsertService
    {
        public static string StatUnitSearchIndexName { get; set; }
        private static readonly SemaphoreSlim SemaphoreBulkBuffer = new SemaphoreSlim(1, 1);
        private BulkDescriptor BulkDescriptorBuffer { get; set; }
        private static volatile int _bulkOperationsBufferedCount;
        private const int MaxBulkOperationsBufferedCount = 1000;
        public static string ServiceAddress { get; set; }
        private readonly ElasticClient _elasticClient;
        public ElasticBulkBuffer()
        {
            var settings = new ConnectionSettings(new Uri(ServiceAddress)).DisableDirectStreaming();
            _elasticClient = new ElasticClient(settings);

            BulkDescriptorBuffer = new BulkDescriptor();

        }
        public async Task EditDocument(ElasticStatUnit elasticItem)
        {

            await SemaphoreBulkBuffer.WaitAsync();
            try
            {
                BulkDescriptorBuffer.Update<ElasticStatUnit>(op => op.Index(StatUnitSearchIndexName).Id(elasticItem.Id).Doc(elasticItem));
                if (++_bulkOperationsBufferedCount >= MaxBulkOperationsBufferedCount)
                {
                    await FlushBulkBufferInner();
                }
            }
            catch
            {
                //TODO Обработка ошибок
            }
            finally
            {
                SemaphoreBulkBuffer.Release();
            }
        }
        public async Task AddDocument(ElasticStatUnit elasticItem)
        {
            await SemaphoreBulkBuffer.WaitAsync();
            try
            {
                BulkDescriptorBuffer.Index<ElasticStatUnit>(op => op.Index(StatUnitSearchIndexName).Id(elasticItem.Id).Document(elasticItem));
                if (++_bulkOperationsBufferedCount >= MaxBulkOperationsBufferedCount)
                {
                    await FlushBulkBufferInner();
                }
            }
            catch
            {
                //TODO Обработка ошибок
            }
            finally
            {
                SemaphoreBulkBuffer.Release();
            }
        }

        public async Task FlushBulkBuffer()
        {
            await SemaphoreBulkBuffer.WaitAsync();
            try
            {
                await FlushBulkBufferInner();
            }
            finally
            {
                SemaphoreBulkBuffer.Release();
            }
        }

        private async Task FlushBulkBufferInner()
        {
            if (_bulkOperationsBufferedCount > 0)
            {
                var result = await _elasticClient.BulkAsync(BulkDescriptorBuffer);
                BulkDescriptorBuffer = new BulkDescriptor();
                _bulkOperationsBufferedCount = 0;
                if (!result.IsValid)
                    throw new Exception(result.DebugInformation);
            }
        }

        public async Task CheckElasticSearchConnection()
        {
            var connect = await _elasticClient.PingAsync();
            if (!connect.IsValid)
            {
                throw new NotFoundException(nameof(Resource.ElasticSearchIsDisable));
            }
        }
        public async Task DeleteDocumentAsync(ElasticStatUnit elasticItem)
        {
            throw new NotImplementedException();
        }
    }
}
